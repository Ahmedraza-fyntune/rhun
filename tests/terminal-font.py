#!/usr/bin/env python3
"""The terminal's own font and line height (issue 90). line_height is a multiple of the font's own line
height, as terminals scale it: 1.0 keeps the terminal as it was, and every step above gives taller
lines, so fewer rows. font names a .ttf for the terminal alone; empty, or one that does not load, uses the editor's
font. Both apply from Settings and from the file while rhun runs (the editor's and interface's font
paths too). The grid is what the shell's stty sees."""
import os
from pathlib import Path
import re
import socket
import struct
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
IOSEVKA = ROOT / 'assets/fonts/IosevkaFixed-Regular.ttf'
MEASURE = ['cmd new_terminal', 'wait 400', 'type echo R$((1+1))X $(stty size)', 'key Return',
           'wait-term R2X', 'print-term']


def wide_font(path):
    """Iosevka with every advance doubled: cells twice as wide, the same height"""
    ttf = bytearray(IOSEVKA.read_bytes())
    tables = {}
    for i in range(struct.unpack_from('>H', ttf, 4)[0]):
        tag, _, offset, _ = struct.unpack_from('>4sIII', ttf, 12 + i * 16)
        tables[tag] = offset
    metrics = struct.unpack_from('>H', ttf, tables[b'hhea'] + 34)[0]
    for i in range(metrics):
        at = tables[b'hmtx'] + i * 4
        struct.pack_into('>H', ttf, at, min(2 * struct.unpack_from('>H', ttf, at)[0], 0xffff))
    path.write_bytes(ttf)


@unittest.skipIf(os.name == 'nt', 'the grid is measured with stty and the control socket')
class TerminalFont(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-tfont-', dir='/tmp')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'p'
        self.proj.mkdir()
        (self.proj / 'long.txt').write_text('x' * 600 + '\n', encoding='utf-8')
        self.wide = self.work / 'wide.ttf'
        wide_font(self.wide)
        self.config = self.work / 'config/rhun/config'
        self.config.parent.mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'), SHELL='/bin/sh')

    def tearDown(self):
        self.tmp.cleanup()

    def configure(self, terminal='', editor=''):
        self.config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                               '[editor]\n' + editor +
                               '[terminal]\nshell = /bin/sh\nheight = 300\n' + terminal +
                               '[files]\nrestore_session = false\nrestore_project = false\n'
                               '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')

    def measure(self, terminal='', editor=''):
        """(rows, cols) the shell sees, and the editor's horizontal scroll range for a long line"""
        self.configure(terminal, editor)
        script = self.work / 's.rsc'
        script.write_text('\n'.join(['wait 200', 'print-scroll', *MEASURE, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(self.proj), str(self.proj / 'long.txt'),
                                 '--headless', '1000x700', '--scale', '1', '--script', str(script)],
                                env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.grid(result.stdout), self.editor_width(result.stdout)

    @staticmethod
    def grid(out):
        match = re.search(r'R2X (\d+) (\d+)', out)
        assert match, out
        return int(match.group(1)), int(match.group(2))

    @staticmethod
    def editor_width(out):
        return int(re.search(r'max=(\d+)', out).group(1))

    def test_line_height_gives_fewer_rows(self):
        (rows, cols), _ = self.measure()
        self.assertEqual(self.measure('line_height = 1.0\n')[0], (rows, cols))
        (rows11, cols11), _ = self.measure('line_height = 1.1\n')
        self.assertLess(rows11, rows, 'a small step did nothing')
        self.assertEqual(cols11, cols)
        (rows15, cols15), _ = self.measure('line_height = 1.5\n')
        (rows20, cols20), _ = self.measure('line_height = 2.0\n')
        self.assertEqual((cols15, cols20), (cols, cols))
        self.assertLess(rows15, rows)
        self.assertLess(rows20, rows15)
        # 2.0 is twice the font size: about half the rows of 1.0, whose lines are the font's own height
        self.assertLess(rows20, rows * 0.8)

    def test_its_own_font(self):
        (rows, cols), width = self.measure()
        (wrows, wcols), wwidth = self.measure(f'font = {self.wide}\n')
        self.assertEqual(wrows, rows)
        self.assertLessEqual(abs(wcols - cols // 2), 1, (cols, wcols))
        self.assertEqual(wwidth, width, 'the editor took the terminal font')

    def test_empty_uses_the_editor_font_and_its_own_wins(self):
        (rows, cols), width = self.measure()
        (erows, ecols), ewidth = self.measure(editor=f'font = {self.wide}\n')
        self.assertEqual(erows, rows)
        self.assertLessEqual(abs(ecols - cols // 2), 1, (cols, ecols))
        self.assertGreater(ewidth, width)
        self.assertEqual(self.measure(f'font = {IOSEVKA}\n', f'font = {self.wide}\n'),
                         ((rows, cols), ewidth))

    def test_a_font_that_does_not_load_uses_the_editor_font(self):
        default = self.measure()
        self.assertEqual(self.measure(f'font = {self.work / "missing café.ttf"}\n'), default)
        (self.work / 'broken.ttf').write_bytes(b'not a font')
        self.assertEqual(self.measure(f'font = {self.work / "broken.ttf"}\n'), default)

    def test_the_file_applies_while_running(self):
        self.configure()
        control = self.work / 'c'
        log = open(self.work / 'rhun.log', 'w')
        process = subprocess.Popen([str(EXE), str(self.proj), str(self.proj / 'long.txt'), '--headless',
                                    '1000x700', '--scale', '1', '--control', str(control)],
                                   env=self.env, stdout=log, stderr=log)
        try:
            # the socket file is there from bind, before listen
            deadline = time.monotonic() + 15
            while True:
                client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                try:
                    client.connect(str(control))
                    break
                except (FileNotFoundError, ConnectionRefusedError):
                    client.close()
                    self.assertLess(time.monotonic(), deadline,
                                    'no control socket: ' + (self.work / 'rhun.log').read_text())
                    time.sleep(.05)
            client.settimeout(30)
            reader = client.makefile('r', encoding='utf-8')

            def command(line):
                client.sendall((line + '\n').encode())
                parts = []
                while True:
                    reply = reader.readline()
                    if reply == 'ok\n':
                        return ''.join(parts)
                    self.assertNotIn(reply, ('', 'error\n'), line)
                    parts.append(reply)
            command('wait 200')
            width = self.editor_width(command('print-scroll'))
            out = ''.join(command(line) for line in MEASURE)
            rows, cols = self.grid(out)
            self.configure(f'line_height = 2.0\nfont = {self.wide}\n', f'font = {self.wide}\n')
            # the shell sees the new grid once the file is read again
            seen = None
            for _ in range(50):
                command('wait 100')
                command('type clear; echo R$((2+2))X $(stty size)')
                command('key Return')
                match = re.search(r'R4X (\d+) (\d+)', command('wait-term R4X') + command('print-term'))
                seen = match and (int(match.group(1)), int(match.group(2)))
                if seen and seen != (rows, cols):
                    break
            self.assertTrue(seen, 'the shell printed no grid')
            self.assertLess(seen[0], rows * 0.8, seen)
            self.assertLessEqual(abs(seen[1] - cols // 2), 1, seen)
            self.assertGreater(self.editor_width(command('print-scroll')), width)
            command('quit')
            reader.close()
            client.close()
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)
            log.close()


if __name__ == '__main__':
    unittest.main()
