#!/usr/bin/env python3
"""Terminal tabs own hover close buttons without changing another tab's selection."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()


class TerminalTabs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-terminal-tabs-')
        self.home = Path(self.tmp.name).resolve()
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix())
        config = self.home / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        # Python provides the same interactive terminal and OSC titles on every platform.
        config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                          '[terminal]\nshell = ' + Path(sys.executable).as_posix() + '\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions, width=1000):
        lines = []
        for index in range(3):
            lines += ['cmd new_terminal', 'wait 300',
                      f"type print('\\x1b]0;tab\\x07SESSION_{index}')",
                      'key Return', 'wait 200']
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join([*lines, *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(self.home), '--headless', f'{width}x700',
                                 '--script', str(script)], env=self.env, capture_output=True,
                                text=True, encoding='utf-8', timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def states(self, output):
        return [line for line in output.splitlines() if line.startswith('tabs=')]

    def close_crop(self, path, tab):
        magic, dimensions, maximum, pixels = path.read_bytes().split(b'\n', 3)
        self.assertEqual((magic, maximum), (b'P6', b'255'))
        width, height = map(int, dimensions.split())
        self.assertEqual((width, height), (1000, 700))
        # Fixed UI metrics: 66 px tabs, 20 px close target inside each tab.
        x = 46 + tab * 66
        return b''.join(pixels[(y * width + x) * 3:(y * width + x + 20) * 3]
                        for y in range(418, 438))

    def test_close_buttons_follow_each_hovered_tab(self):
        idle = self.home / 'idle.ppm'
        shots = [self.home / f'hover-{i}.ppm' for i in range(3)]
        away = self.home / 'away.ppm'
        actions = ['move 500 200', f'shot {idle.as_posix()}']
        for i, shot in enumerate(shots):
            actions += [f'move {18 + i * 66} 428', f'shot {shot.as_posix()}']
        actions += ['move 500 200', f'shot {away.as_posix()}']
        self.run_editor(actions)
        for i, shot in enumerate(shots):
            for tab in range(3):
                before, after = self.close_crop(idle, tab), self.close_crop(shot, tab)
                if tab == i:
                    self.assertNotEqual(before, after)
                else:
                    self.assertEqual(before, after)
                self.assertEqual(before, self.close_crop(away, tab))

    def test_closing_inactive_tab_preserves_current_terminal(self):
        output = self.run_editor(['move 56 428', 'down', 'print-state', 'print-term',
                                  'up', 'print-state', 'print-term'])
        states = self.states(output)
        self.assertEqual(len(states), 2, output)
        self.assertIn('term=3', states[0])
        self.assertIn('term=2', states[1])
        self.assertEqual(output.count('\nSESSION_2\n'), 2, output)
        self.assertNotIn('SESSION_0', output)

    def test_middle_active_and_last_tabs_close_individually(self):
        output = self.run_editor(['click 122 428', 'print-state', 'print-term',
                                  'click 122 428', 'print-state', 'print-term',
                                  'click 56 428', 'print-state'])
        states = self.states(output)
        self.assertEqual(len(states), 3, output)
        self.assertIn('term=2', states[0])
        self.assertIn('term=1', states[1])
        self.assertNotIn('term=', states[2])
        self.assertIn('\nSESSION_2\n', output)
        self.assertIn('\nSESSION_0\n', output)
        self.assertNotIn('SESSION_1', output)

    def test_crowded_tabs_do_not_take_toolbar_clicks(self):
        output = self.run_editor(['click 152 428', 'print-state',
                                  'click 180 428', 'print-state'], width=200)
        states = self.states(output)
        self.assertEqual(len(states), 2, output)
        self.assertIn('term=4', states[0])
        self.assertIn('term=4 hidden', states[1])


if __name__ == '__main__':
    unittest.main(verbosity=2)
