#!/usr/bin/env python3
"""Versioned native placement records: bounded parsing, atomic saves and isolation."""
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / ('build/windows/window_state_test.exe' if os.name == 'nt' else 'build/window_state_test')
MAGIC = 0x31535752
NORMAL = struct.pack('<IiiIII', MAGIC, -200, 120, 900, 640, 3)


class WindowState(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='rhun-window-record-')
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.state = self.work / 'state/rhun'
        self.state.mkdir(parents=True)
        self.record = self.state / 'window-fixture'
        self.env = dict(os.environ, HOME=str(self.work), XDG_STATE_HOME=str(self.work / 'state'),
                        XDG_CONFIG_HOME=str(self.work / 'config'))

    def read(self, data=None, mode='load'):
        if data is not None:
            self.record.write_bytes(data)
        result = subprocess.run([str(EXE), mode], env=self.env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout)
        return result.stdout

    def test_missing_and_invalid_records_leave_output_unchanged(self):
        self.assertEqual(self.read(), b'invalid\n')
        for data in [NORMAL[:n] for n in range(len(NORMAL))] + [NORMAL + b'x', b'x' * 65536]:
            with self.subTest(length=len(data)):
                self.assertEqual(self.read(data), b'invalid\n')
        for index, value in [(0, MAGIC + 1), (1, -1048577), (1, 1048577), (2, -1048577),
                             (2, 1048577), (3, 0), (3, 8193), (3, 0xffffffff),
                             (4, 0), (4, 8193), (4, 0xffffffff), (5, 4), (5, 0xffffffff)]:
            values = [MAGIC, -200, 120, 900, 640, 3]
            values[index] = value
            with self.subTest(index=index, value=value):
                self.assertEqual(self.read(struct.pack('<IiiIII', *values)), b'invalid\n')

    def test_valid_records_are_copied_exactly(self):
        for width, height in [(900, 640), (1, 1), (63, 63), (8192, 8192)]:
            for flags in range(4):
                data = struct.pack('<IiiIII', MAGIC, -200, 120, width, height, flags)
                self.assertEqual(self.read(data), b'valid\n' + data)

    def test_save_is_separate_from_other_state(self):
        peer = self.state / 'project.session'
        peer.write_bytes(b'project state')
        self.assertEqual(self.read(mode='save'), b'valid\n' + NORMAL)
        self.assertEqual(self.record.read_bytes(), NORMAL)
        self.assertEqual(peer.read_bytes(), b'project state')
        self.assertEqual(sorted(p.name for p in self.state.iterdir()), ['project.session', 'window-fixture'])

    def test_invalid_save_preserves_existing_record(self):
        self.assertEqual(self.read(NORMAL, mode='save-invalid'), b'valid\n' + NORMAL)
        self.assertEqual(self.record.read_bytes(), NORMAL)

    def test_headless_does_not_change_native_placement(self):
        for backend in ('windows', 'x11', 'wayland'):
            (self.state / ('window-' + backend)).write_bytes(NORMAL)
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[updates]\ncheck = false\n[git]\nenabled = false\n')
        script = self.work / 'actions.rsc'
        script.write_text('quit\n')
        editor = ROOT / ('build/windows/rhun.com' if os.name == 'nt' else 'build/rhun')
        result = subprocess.run([str(editor), str(self.work), '--headless', '800x600',
                                 '--script', str(script)], env=self.env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout)
        for backend in ('windows', 'x11', 'wayland'):
            self.assertEqual((self.state / ('window-' + backend)).read_bytes(), NORMAL)

    @unittest.skipUnless(hasattr(os, 'mkfifo'), 'FIFO fixture requires Unix')
    def test_fifo_does_not_block_startup(self):
        os.mkfifo(self.record)
        self.assertEqual(self.read(), b'invalid\n')


if __name__ == '__main__':
    unittest.main()
