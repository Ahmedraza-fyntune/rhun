#!/usr/bin/env python3
"""The window losing and getting the keyboard back (Alt+Tab, a click on another window) leaves the
editor where it was scrolled, also far from the cursor (issue 85), and the caret shows at once when
the keyboard comes back. tests/linux-focus.py switches real X11 and Wayland windows."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()

CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n'
          '[editor]\ncursor_blink = {blink}\nword_wrap = {wrap}\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')


class WindowFocus(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-focus-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        self.file = self.proj / 'lines.txt'
        self.file.write_text(''.join(f'line {i}\n' for i in range(3000)), encoding='utf-8')
        self.config = self.work / 'config/rhun/config'
        self.config.parent.mkdir(parents=True)
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix())

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions, blink=False, wrap=False):
        self.config.write_text(CONFIG.format(blink=str(blink).lower(), wrap=str(wrap).lower()),
                               encoding='utf-8')
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 200', *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), self.file.as_posix(),
                                 '--headless', '1000x700', '--scale', '1',
                                 '--script', script.as_posix()],
                                env=self.env, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8').splitlines()

    def offsets(self, scroll, wrap=False):
        """the scroll offset (1/256 lines) and state after scroll(), after focus out, after focus in"""
        out = self.run_editor([*scroll, 'wait 60', 'print-scroll', 'print-state',
                               'focus out', 'wait 60', 'print-scroll',
                               'focus in', 'wait 60', 'print-scroll', 'print-state'], wrap=wrap)
        ys = [int(dict(part.split('=') for part in line.split())['y'])
              for line in out if line.startswith('x=')]
        states = [line for line in out if line.startswith('tabs=')]
        self.assertEqual(len(ys), 3, out)
        self.assertGreater(ys[0], 0, 'the editor did not scroll')
        self.assertIn(' line=1 col=1 ', states[0], 'the cursor moved')
        return ys, states

    def test_wheel_scroll_stays(self):
        ys, states = self.offsets(['move 500 400', 'scroll 3000'])
        self.assertEqual(ys, [ys[0]] * 3)
        self.assertEqual(states[0], states[1])

    def test_wheel_scroll_stays_with_word_wrap(self):
        ys, _ = self.offsets(['move 500 400', 'scroll 3000'], wrap=True)
        self.assertEqual(ys, [ys[0]] * 3)

    def test_scrollbar_drag_stays(self):
        # the issue's steps: the scrollbar dragged down, the cursor left on the first line
        ys, _ = self.offsets(['move 990 100', 'down', 'move 990 300', 'move 990 699', 'up'])
        self.assertGreater(ys[0], 1000 * 256)
        self.assertEqual(ys, [ys[0]] * 3)

    def test_typing_after_focus_in_shows_the_cursor(self):
        out = self.run_editor(['move 500 400', 'scroll 3000', 'focus out', 'focus in', 'type x',
                               'wait 60', 'print-scroll', 'print-state'])
        self.assertEqual(out[0].split()[1], 'y=0', out)
        self.assertIn(' line=1 col=2 ', out[1])

    def test_caret_shows_at_once_on_focus_in(self):
        # 800 ms after the last caret activity a blinking caret is off; the keyboard coming back
        # starts its blink again, on, as a key does
        on = self.work / 'on.ppm'
        back = self.work / 'back.ppm'
        self.run_editor(['key Right', 'key Left', 'shot ' + on.as_posix(), 'focus out', 'wait 800',
                         'focus in', 'shot ' + back.as_posix()], blink=True)
        self.assertEqual(on.read_bytes(), back.read_bytes(), 'the caret is not shown on focus in')


if __name__ == '__main__':
    unittest.main()
