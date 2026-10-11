#!/usr/bin/env python3
"""The settings page's search field filters its rows as you type."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
MOD = 'cmd' if sys.platform == 'darwin' else 'ctrl'


class SettingsSearch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-settings-search-')
        self.home = Path(self.tmp.name).resolve()
        self.file = self.home / 'a.txt'
        self.file.write_text('hello\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix())
        self.config = self.home / 'config/rhun/config'
        self.config.parent.mkdir(parents=True)
        self.config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                               '[updates]\ncheck = false\n[git]\nenabled = false\n',
                               encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions):
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(self.home), str(self.file),
                                 '--headless', '1000x700', '--script', str(script)],
                                env=self.env, capture_output=True, text=True,
                                encoding='utf-8', timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def vim_mode(self):
        return self.config.read_text(encoding='utf-8') if self.config.exists() else ''

    # the field is focused on open: typing filters, the matching row's control works
    def test_search_filters_rows(self):
        self.run_editor(['cmd settings', 'type vim_mode', 'click 827 348'])
        self.assertIn('vim_mode = true', self.vim_mode())

    # a query with no match leaves no row to click
    def test_no_match_hides_rows(self):
        self.run_editor(['cmd settings', 'type zzzzz', 'click 827 348'])
        self.assertNotIn('vim_mode', self.vim_mode())


if __name__ == '__main__':
    unittest.main()
