#!/usr/bin/env python3
"""Saving a read-only file asks first: Overwrite replaces it and it stays read-only, Cancel leaves it.
Closing or quitting with it modified asks the same after Save; vim's :wa leaves it; Save As and
writable files save as before."""
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
CONFIG = ('[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
DIALOG = 'focus=5'


@unittest.skipIf(hasattr(os, 'geteuid') and os.geteuid() == 0, 'root may write any file')
class ReadOnlySave(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-readonly-')
        self.home = Path(self.tmp.name).resolve()
        self.work = self.home / 'work'
        self.work.mkdir()
        self.note = self.work / 'note.txt'
        self.other = self.work / 'other.txt'
        self.note.write_bytes(b'before\n')
        self.other.write_bytes(b'other\n')
        os.chmod(self.note, 0o444)
        self.config = self.home / 'config/rhun/config'
        self.config.parent.mkdir(parents=True)
        self.config.write_text(CONFIG, encoding='utf-8')
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix())

    def tearDown(self):
        for path in self.work.rglob('*'):
            os.chmod(path, 0o644)
        for _ in range(50):
            try:
                self.tmp.cleanup()
                return
            except OSError:
                time.sleep(0.2)
        self.tmp.cleanup()

    def run_editor(self, paths, actions):
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join(['wait 100', *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), *map(str, paths), '--headless', '1280x800', '--scale', '1',
                                 '--script', script.as_posix()], env=self.env, capture_output=True,
                                timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', errors='replace'))
        output = result.stdout.decode('utf-8')
        self.assertNotIn('unknown command', output)
        return output.splitlines()

    def assert_read_only(self, path, text):
        self.assertEqual(path.read_bytes(), text)
        self.assertFalse(os.access(path, os.W_OK))
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode) & 0o222, 0)

    def state(self, line, field):
        return dict(part.split('=', 1) for part in line.split() if '=' in part)[field]

    def test_save_asks_and_cancel_keeps_the_file(self):
        lines = self.run_editor([self.note], ['type x', 'cmd save', 'print-state', 'key Escape',
                                              'print-state', 'key ctrl+s', 'print-state', 'key Escape'])
        self.assertIn(DIALOG, lines[0])
        self.assertEqual(self.state(lines[0], 'dirty'), '1')
        self.assertNotIn(DIALOG, lines[1])
        self.assertEqual(self.state(lines[1], 'dirty'), '1')
        self.assertIn(DIALOG, lines[2])
        self.assert_read_only(self.note, b'before\n')

    def test_overwrite_replaces_it_and_it_stays_read_only(self):
        lines = self.run_editor([self.note], ['type x', 'cmd save', 'key Return', 'print-state',
                                              'print-toast'])
        self.assertNotIn(DIALOG, lines[0])
        self.assertEqual(self.state(lines[0], 'dirty'), '0')
        self.assertEqual(lines[1], 'toast=Saved')
        self.assert_read_only(self.note, b'xbefore\n')
        # it asks again next time
        lines = self.run_editor([self.note], ['type y', 'cmd save', 'print-state', 'key Escape'])
        self.assertIn(DIALOG, lines[0])
        self.assert_read_only(self.note, b'xbefore\n')

    def test_writable_files_save_without_asking(self):
        lines = self.run_editor([self.other], ['type x', 'cmd save', 'print-state', 'print-toast'])
        self.assertNotIn(DIALOG, lines[0])
        self.assertEqual(lines[1], 'toast=Saved')
        self.assertEqual(self.other.read_bytes(), b'xother\n')

    def test_closing_asks_again_after_save(self):
        # Save in the close dialog, then Cancel: the tab stays, modified
        lines = self.run_editor([self.note], ['type x', 'cmd close_tab', 'print-state', 'key Return',
                                              'print-state', 'key Escape', 'print-state'])
        self.assertIn(DIALOG, lines[0])
        self.assertIn(DIALOG, lines[1])
        self.assertEqual(self.state(lines[1], 'tabs'), '1')
        self.assertNotIn(DIALOG, lines[2])
        self.assertEqual(self.state(lines[2], 'tabs'), '1')
        self.assertEqual(self.state(lines[2], 'dirty'), '1')
        self.assert_read_only(self.note, b'before\n')
        # Save, then Overwrite: saved and closed
        lines = self.run_editor([self.note], ['type x', 'cmd close_tab', 'key Return', 'key Return',
                                              'print-state'])
        self.assertTrue(lines[0].startswith('tabs=0'), lines[0])
        self.assert_read_only(self.note, b'xbefore\n')

    def test_quitting_saves_it_after_overwrite(self):
        lines = self.run_editor([self.note], ['type x', 'cmd quit', 'key Return', 'key Escape',
                                              'print-state'])
        self.assertEqual(self.state(lines[0], 'tabs'), '1')
        self.assertNotIn(DIALOG, lines[0])
        self.assert_read_only(self.note, b'before\n')
        # the script ends where the editor quits
        self.run_editor([self.note], ['type x', 'cmd quit', 'key Return', 'key Return', 'wait 100'])
        self.assert_read_only(self.note, b'xbefore\n')

    def test_vim_write_all_leaves_read_only_files(self):
        lines = self.run_editor([self.note, self.other], [
            'cmd toggle_vim', 'type x', 'cmd prev_tab', 'type x', 'type :wa', 'key Return', 'print-toast',
            'print-state'])
        self.assertEqual(lines[0], 'toast=Read-only files were not saved (:w asks to overwrite)')
        self.assertNotIn(DIALOG, lines[1])
        self.assertEqual(self.other.read_bytes(), b'ther\n')
        self.assert_read_only(self.note, b'before\n')

    def test_save_as_writes_a_new_file(self):
        copy = self.work / 'copy.txt'
        lines = self.run_editor([self.note], ['type x', 'cmd save_as', 'key ctrl+a',
                                              'type ' + copy.as_posix(), 'key Return', 'print-state'])
        self.assertNotIn(DIALOG, lines[0])
        self.assertEqual(self.state(lines[0], 'active'), 'copy.txt')
        self.assertEqual(copy.read_bytes(), b'xbefore\n')
        self.assert_read_only(self.note, b'before\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
