#!/usr/bin/env python3
"""The editor's horizontal scrollbar (issue 49): with word wrap off, lines wider than the text area get a
bar along its bottom. Dragging or clicking it scrolls without moving the caret, a sideways wheel stops at
the widest line, and word wrap or short lines leave no bar."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()


@unittest.skipIf(os.name == 'nt', 'the control socket is Unix only')
class EditorHScroll(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-hscroll-', dir='/tmp')
        self.work = Path(self.tmp.name).resolve()
        self.project = self.work / 'project'
        self.project.mkdir()
        lines = [f'line {i:02d} ' + ('short' if i % 5 else 'wide ' * 60 + f'END{i}') for i in range(40)]
        (self.project / 'wide.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
        (self.project / 'narrow.txt').write_text('a\nfew\nnarrow lines\n', encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n'
                          '[editor]\ncursor_blink = false\ntab_width = 4\n'
                          '[ui]\nagents_panel = false\nsidebar = false\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'))
        self.process = self.client = self.reader = None

    def tearDown(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
                self.process.wait(timeout=10)
            self.reader.close()
            self.client.close()
            self.process.stderr.close()
        self.tmp.cleanup()

    def start(self, name='wide.txt'):
        control = self.work / 'control'
        self.process = subprocess.Popen([str(EXE), str(self.project), str(self.project / name),
                                         '--headless', '1280x800', '--scale', '1',
                                         '--control', str(control)], env=self.env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.client.settimeout(15)
        deadline = time.monotonic() + 10
        while True:
            try:
                self.client.connect(str(control))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if self.process.poll() is not None or time.monotonic() > deadline:
                    self.fail('editor did not start')
                time.sleep(0.01)
        self.reader = self.client.makefile('r', encoding='utf-8')
        self.command('wait 100')

    def command(self, line):
        self.client.sendall((line + '\n').encode('utf-8'))
        output = []
        while True:
            reply = self.reader.readline()
            if reply == 'ok\n':
                return ''.join(output)
            self.assertNotIn(reply, ('', 'error\n'), line)
            output.append(reply)

    def scroll(self):
        """x, max and the track (x, y, w, h), or None without the bar"""
        fields = dict(part.split('=') for part in self.command('print-scroll').split())
        track = tuple(map(int, fields['track'].split(','))) if 'track' in fields else None
        return int(fields['x']), int(fields['max']), track

    def state(self):
        return self.command('print-state').strip()

    def shot(self):
        path = self.work / 'shot.ppm'
        self.command(f'shot {path}')
        magic, size, maximum, pixels = path.read_bytes().split(b'\n', 3)
        return pixels

    def test_wide_lines_get_a_bar_that_scrolls_them(self):
        self.start()
        x, limit, track = self.scroll()
        self.assertEqual(x, 0)
        self.assertGreater(limit, 0)
        tx, ty, tw, th = track
        # the thumb is drawn along the bottom of the text area, at its left end
        pixels = self.shot()
        row = ty + th - 5
        def pixel(px):
            return pixels[(row * 1280 + px) * 3:(row * 1280 + px) * 3 + 3]
        self.assertNotEqual(pixel(tx + 10), pixel(tx + tw - 10))
        before = self.state()
        # a drag of the thumb scrolls, and the caret stays where it was
        self.command(f'move {tx + 20} {ty + th - 5}')
        self.command('wait 50')
        self.command('down')
        self.command(f'move {tx + 220} {ty + th - 5}')
        self.command('wait 50')
        self.command('up')
        x, _, _ = self.scroll()
        self.assertGreater(x, 0)
        self.assertLess(x, limit)
        self.assertEqual(self.state(), before)
        # a click at the end of the track goes to the end
        self.command(f'click {tx + tw - 3} {ty + th // 2}')
        self.assertEqual(self.scroll()[0], limit)
        self.assertEqual(self.state(), before)
        # the thumb went with it
        pixels = self.shot()
        self.assertNotEqual(pixel(tx + tw - 10), pixel(tx + 10))

    def test_sideways_scrolling_stops_at_the_widest_line(self):
        self.start()
        _, limit, _ = self.scroll()
        self.command('move 600 400')    # the wheel goes to what is under the pointer
        self.command('scroll-x 100000')
        self.command('wait 50')
        self.assertEqual(self.scroll()[0], limit)
        self.command('scroll-x -100000')
        self.command('wait 50')
        self.assertEqual(self.scroll()[0], 0)

    def test_the_end_of_a_wide_line_shows_within_the_scroll(self):
        self.start()
        self.command('key End')
        self.command('wait 50')
        x, limit, _ = self.scroll()
        self.assertIn('line=1 col=', self.state())
        self.assertGreater(x, 0)
        self.assertLessEqual(x, limit)

    def test_no_bar_for_narrow_lines_or_word_wrap(self):
        self.start('narrow.txt')
        self.assertEqual(self.scroll(), (0, 0, None))
        self.command(f'open {self.project / "wide.txt"}')
        self.command('wait 50')
        self.assertIsNotNone(self.scroll()[2])
        self.command('cmd toggle_word_wrap')
        self.command('wait 50')
        self.assertEqual(self.scroll(), (0, 0, None))
        self.command('move 600 400')
        self.command('scroll-x 500')
        self.command('wait 50')
        self.assertEqual(self.scroll(), (0, 0, None))

    def test_tabs_and_wide_characters_count_as_drawn(self):
        # 300 columns three ways: ASCII, double-width characters, tabs of 4
        texts = {'ascii.txt': 'x' * 300, 'wide-chars.txt': '日' * 150, 'tabs.txt': '\t' * 75}
        for name, text in texts.items():
            (self.project / name).write_text(text + '\n', encoding='utf-8')
        self.start('ascii.txt')
        limits = []
        for name in texts:
            self.command(f'open {self.project / name}')
            self.command('wait 50')
            limits.append(self.scroll()[1])
        self.assertGreater(limits[0], 0)
        self.assertEqual(limits, [limits[0]] * 3)

    def test_a_large_text_is_measured_again_once_editing_pauses(self):
        # past a megabyte, typing widens the bar from the lines on screen; a narrower text shows
        # once editing pauses, without a frame of its own afterwards
        big = self.project / 'big.txt'
        big.write_text(''.join(f'{i:06d} an ordinary line of text\n' for i in range(60000)),
                       encoding='utf-8')
        self.start('big.txt')
        self.assertEqual(self.scroll(), (0, 0, None))
        self.command('key End')
        self.command('type ' + 'w' * 300)
        self.command('wait 0')
        self.assertGreater(self.scroll()[1], 0)
        for _ in range(300):
            self.command('key BackSpace')
        self.command('wait 700')
        self.assertEqual(self.scroll(), (0, 0, None))
        self.command('print-frames')
        self.command('wait 1500')
        self.assertEqual(self.command('print-frames'), 'frames=0\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
