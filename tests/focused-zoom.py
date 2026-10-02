#!/usr/bin/env python3
"""Editor and terminal font zoom follows focus, persists independently, and leaves images alone."""
import configparser
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
MOD = 'cmd' if sys.platform == 'darwin' else 'ctrl'


class FocusedZoom(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-focused-zoom-')
        self.home = Path(self.tmp.name).resolve()
        self.file = self.home / 'a.txt'
        self.file.write_text('hello\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix())
        self.config = self.home / 'config/rhun/config'
        self.config.parent.mkdir(parents=True)
        self.configure()

    def tearDown(self):
        self.tmp.cleanup()

    def configure(self, editor=17, terminal=12, keys=''):
        self.config.write_text('[editor]\nfont_size = ' + str(editor) + '\n'
                               '[terminal]\nfont_size = ' + str(terminal) + '\n'
                               'shell = ' + Path(sys.executable).as_posix() + '\n'
                               '[ui]\nsidebar = false\nagents_panel = false\n'
                               '[updates]\ncheck = false\n[git]\nenabled = false\n' + keys,
                               encoding='utf-8')

    def run_editor(self, actions, path=None):
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(self.home), str(path or self.file),
                                 '--headless', '1000x700', '--script', str(script)],
                                env=self.env, capture_output=True, text=True,
                                encoding='utf-8', timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def sizes(self):
        config = configparser.ConfigParser(interpolation=None, strict=False)
        config.read(self.config, encoding='utf-8')
        return config.getint('editor', 'font_size'), config.getint('terminal', 'font_size')

    def terminal(self):
        return ['cmd new_terminal', 'wait 300']

    def test_zoom_switches_with_mouse_focus_and_persists(self):
        self.run_editor([*self.terminal(), 'click 100 100', f'key {MOD}+=',
                         'click 100 480', f'key {MOD}+=', f'key {MOD}+shift++',
                         f'key {MOD}+-'])
        self.assertEqual(self.sizes(), (18, 13))
        self.run_editor([*self.terminal(), f'key {MOD}+='])
        self.assertEqual(self.sizes(), (18, 14))

    def test_editor_reset_leaves_terminal_size(self):
        self.run_editor([*self.terminal(), 'click 100 100', f'key {MOD}+0'])
        self.assertEqual(self.sizes(), (14, 12))

    def test_terminal_reset_leaves_editor_size(self):
        self.run_editor([*self.terminal(), f'key {MOD}+0'])
        self.assertEqual(self.sizes(), (17, 14))

    def test_each_font_uses_its_setting_limits(self):
        self.configure(editor=40, terminal=24)
        self.run_editor([f'key {MOD}+=', *self.terminal(), f'key {MOD}+='])
        self.assertEqual(self.sizes(), (40, 24))
        self.configure(editor=8, terminal=9)
        self.run_editor([f'key {MOD}+-', *self.terminal(), f'key {MOD}+-'])
        self.assertEqual(self.sizes(), (8, 9))

    def test_terminal_focus_leaves_visible_image_zoom(self):
        output = self.run_editor([*self.terminal(), f'key {MOD}+=', 'print-state'],
                                 ROOT / 'tests/data/images/rgba.png')
        self.assertEqual(self.sizes(), (17, 13))
        self.assertIn('zoom=100 fit=1', output)

    def test_remapped_zoom_shortcut_works_in_terminal(self):
        self.configure(keys='[keys]\nctrl+j = zoom_in\n')
        self.run_editor([*self.terminal(), f'key {MOD}+j'])
        self.assertEqual(self.sizes(), (17, 13))

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS distinguishes Command from Control')
    def test_physical_control_stays_terminal_input(self):
        self.run_editor([*self.terminal(), 'key ctrl+=', 'key ctrl+-', 'key ctrl+0'])
        self.assertEqual(self.sizes(), (17, 12))


if __name__ == '__main__':
    unittest.main(verbosity=2)
