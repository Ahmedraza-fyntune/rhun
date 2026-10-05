#!/usr/bin/env python3
"""The terminal panel's height follows only its own top edge: not a press on another panel's row
that shares its widget id, and a drag of the edge leaves the editor above it alone."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
HEIGHT = 260
# 1280x800 at scale 1: the status bar starts at 774, so the panel's top edge is at 774 - HEIGHT
EDGE = 774 - HEIGHT
# the agents panel (380 wide on the right): its first session row
AGENT_ROW = (1000, 105)


class TerminalPanel(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-terminal-panel-')
        self.home = Path(self.tmp.name).resolve()
        self.project = self.home / 'project'
        self.project.mkdir()
        (self.project / 'long.txt').write_text(
            ''.join(f'line {i:04d}\n' for i in range(1, 2001)), encoding='utf-8')
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix())
        self.config = self.home / 'config/rhun/config'
        self.config.parent.mkdir(parents=True)

    def tearDown(self):
        for _ in range(50):
            try:
                self.tmp.cleanup()
                return
            except OSError:
                time.sleep(0.2)
        self.tmp.cleanup()

    def run_editor(self, actions, agents=False):
        self.config.write_text(
            '[ui]\nsidebar = false\nagents_panel = ' + str(agents).lower() + '\n'
            '[terminal]\nheight = ' + str(HEIGHT) + '\nshell = ' + Path(sys.executable).as_posix() + '\n'
            '[editor]\ncursor_blink = false\nscroll_past_end = true\n'
            '[files]\nrestore_session = false\nrestore_project = false\n'
            '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join(['cmd toggle_terminal', 'wait 300', *actions, 'quit']) + '\n',
                          encoding='utf-8')
        result = subprocess.run([str(EXE), str(self.project), str(self.project / 'long.txt'),
                                 '--headless', '1280x800', '--scale', '1', '--script', str(script)],
                                env=self.env, capture_output=True, text=True, encoding='utf-8',
                                timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def height(self):
        """The terminal height rhun saved on exit."""
        match = re.search(r'^\[terminal\][^\[]*?^height = (\d+)$', self.config.read_text(encoding='utf-8'),
                          re.M | re.S)
        self.assertIsNotNone(match)
        return int(match.group(1))

    def test_a_press_on_an_agent_session_keeps_the_height(self):
        # a Claude session of the project, so the agents panel lists a row
        slug = re.sub(r'[^A-Za-z0-9]', '-', self.project.as_posix())
        sessions = self.home / '.claude/projects' / slug
        sessions.mkdir(parents=True)
        fixture = (ROOT / 'tests/data/agents/claude.jsonl').read_text(encoding='utf-8')
        (sessions / 's1.jsonl').write_text(fixture.replace('@PROJECT@', self.project.as_posix()),
                                           encoding='utf-8')
        x, y = AGENT_ROW
        self.run_editor([f'move {x} {y}', 'wait 50', 'down', 'wait 50', f'move {x} {y + 4}',
                          'wait 50', 'up', 'wait 50'], agents=True)
        self.assertEqual(self.height(), HEIGHT)

    def test_dragging_the_edge_leaves_the_editor_alone(self):
        # pressed just above the line, inside the editor's last rows, and dragged down 100: the
        # height follows the pointer, from the edge to the status bar
        out = self.run_editor([f'move 600 {EDGE - 2}', 'wait 50', 'down', 'wait 50',
                               f'move 600 {EDGE + 40}', 'wait 50', f'move 600 {EDGE + 98}',
                               'wait 300', 'up', 'wait 50', 'print-state'])
        state = [line for line in out.splitlines() if line.startswith('tabs=')][-1]
        self.assertIn('line=1 col=1 sel=0', state)
        self.assertEqual(self.height(), HEIGHT - 98)


if __name__ == '__main__':
    unittest.main(verbosity=2)
