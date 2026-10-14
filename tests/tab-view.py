#!/usr/bin/env python3
"""Each tab shows where it was scrolled when it is shown again, also far from its cursor: after
Ctrl+Tab, a click on the tab, or closing the tab in front of it (as switching windows, issue 85).
A cursor placed while its tab was not shown, as a restored session does, is in view when that tab
is first shown."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()

CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n'
          '[editor]\ncursor_blink = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
Y = 58
A_TAB = 30                      # a.txt, the first tab, left of its close button


class TabView(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-tabview-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        for name in ('a', 'b', 'c'):
            (self.proj / (name + '.txt')).write_text(''.join(f'{name} line {i}\n' for i in range(3000)),
                                                     encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix())

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions):
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 200', *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', '1000x700', '--scale', '1',
                                 '--script', script.as_posix()],
                                env=self.env, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8').splitlines()

    def open(self, *names):
        return ['open ' + (self.proj / (name + '.txt')).as_posix() for name in names]

    @staticmethod
    def scrolls(out):
        """the y of each print-scroll, in 1/256 lines, and each print-state"""
        return ([int(dict(part.split('=') for part in line.split())['y']) for line in out
                 if line.startswith('x=')], [line for line in out if line.startswith('tabs=')])

    def test_ctrl_tab_keeps_each_tab_where_it_was_scrolled(self):
        out = self.run_editor([*self.open('a', 'b'),
                               'move 500 400', 'scroll 3000', 'wait 60', 'print-scroll',      # b
                               'key ctrl+Tab', 'scroll 6000', 'wait 60', 'print-scroll',      # a
                               'key ctrl+Tab', 'wait 60', 'print-scroll', 'print-state',      # b
                               'key ctrl+Tab', 'wait 60', 'print-scroll', 'print-state'])     # a
        ys, states = self.scrolls(out)
        self.assertGreater(ys[0], 0)
        self.assertGreater(ys[1], ys[0])
        self.assertEqual(ys[2:], [ys[0], ys[1]], out)
        self.assertIn('active=b.txt line=1 col=1 ', states[0])
        self.assertIn('active=a.txt line=1 col=1 ', states[1])

    def test_a_click_on_a_tab_keeps_where_it_was_scrolled(self):
        out = self.run_editor([*self.open('a', 'b'),
                               f'click {A_TAB} {Y}', 'move 500 400', 'scroll 3000', 'wait 60', 'print-scroll',
                               'key ctrl+Tab', 'wait 60', 'print-state',
                               f'click {A_TAB} {Y}', 'wait 60', 'print-scroll', 'print-state'])
        ys, states = self.scrolls(out)
        self.assertGreater(ys[0], 0)
        self.assertIn('active=b.txt ', states[0])
        self.assertEqual(ys[1], ys[0])
        self.assertIn('active=a.txt line=1 col=1 ', states[1])

    def test_closing_a_tab_shows_the_next_where_it_was_scrolled(self):
        out = self.run_editor([*self.open('a', 'b'),
                               'move 500 400', 'scroll 3000', 'wait 60', 'print-scroll',      # b
                               'key ctrl+Tab', 'key ctrl+w', 'wait 60', 'print-scroll', 'print-state'])
        ys, states = self.scrolls(out)
        self.assertGreater(ys[0], 0)
        self.assertEqual(ys[1], ys[0])
        self.assertIn('tabs=1 active=b.txt ', states[0])

    def test_typing_after_a_switch_shows_the_cursor(self):
        out = self.run_editor([*self.open('a', 'b'),
                               'move 500 400', 'scroll 3000', 'key ctrl+Tab', 'key ctrl+Tab', 'type x',
                               'wait 60', 'print-scroll', 'print-state'])
        ys, states = self.scrolls(out)
        self.assertEqual(ys, [0])
        self.assertIn('active=b.txt line=1 col=2 ', states[0])

    def test_restored_cursors_are_in_view_when_their_tabs_show(self):
        # a session with a at line 2000 and b at line 1500, b in front
        goto = lambda line: ['key ctrl+g', f'type {line}', 'key Return']
        self.run_editor([*self.open('a'), *goto(2000), *self.open('b'), *goto(1500)])
        out = self.run_editor(['wait 60', 'print-scroll', 'print-state',
                               'key ctrl+Tab', 'wait 60', 'print-scroll', 'print-state'])
        ys, states = self.scrolls(out)
        self.assertIn('tabs=2 active=b.txt line=1500 ', states[0])
        self.assertIn('active=a.txt line=2000 ', states[1])
        for y, line in zip(ys, (1500, 2000)):
            top = y // 256 + 1
            # 1000x700 at scale 1 shows 28 lines
            self.assertTrue(top <= line < top + 28, f'line {line} not shown from line {top}: {out}')


if __name__ == '__main__':
    unittest.main()
