#!/usr/bin/env python3
"""The settings page's search field filters its rows as you type (PR 78): each word has to be in a row's
title, its description, its config name (section.key) or its section's title, ignoring case. Esc
clears the query, then hands the keys to the page; the field has the keys whenever the settings tab
comes to the front, and Find there goes to it. A new settings tab starts with no query."""
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

    def rows(self, *actions):
        return self.run_editor(['cmd settings', *actions, 'print-settings']).split()

    def test_words_not_scattered_letters(self):
        # "font" once kept Explorer width ("of the file explorer in points") and the like
        self.assertEqual(self.rows('type font'), [
            'ui.font_size', 'ui.font', 'editor.font_size', 'editor.font', 'editor.line_height',
            'terminal.font_size', 'terminal.font', 'terminal.line_height'])
        self.assertEqual(self.rows('type terminal font'),
                         ['terminal.font_size', 'terminal.font', 'terminal.line_height'])

    def test_names_and_case(self):
        self.assertEqual(self.rows('type vim_mode'), ['editor.vim_mode'])
        self.assertEqual(self.rows('type VIM'), ['editor.vim_mode'])
        self.assertEqual(self.rows('type editor.font'), ['editor.font_size', 'editor.font'])
        appearance = self.rows('type appearance')
        self.assertTrue(appearance and all(row.startswith('ui.') for row in appearance), appearance)
        self.assertIn('ui.scale', appearance)

    def test_no_match(self):
        self.assertEqual(self.rows('type zzzzz'), [])

    def test_escape_clears_then_leaves(self):
        everything = self.rows()
        self.assertGreater(len(everything), 40)
        self.assertEqual(self.rows('type font', 'key Escape'), everything)
        # the second Escape hands the keys to the page: typing filters nothing
        self.assertEqual(self.rows('type font', 'key Escape', 'key Escape', 'type vim'), everything)

    def test_the_tab_coming_back_has_the_keys(self):
        out = self.run_editor(['cmd settings', 'type vim', 'key ctrl+Tab', 'key ctrl+Tab',
                               'key BackSpace', 'key BackSpace', 'key BackSpace', 'type wrap',
                               'print-settings'])
        self.assertEqual(out.split(), ['editor.word_wrap'])

    def test_find_goes_to_the_search_field(self):
        self.assertEqual(self.rows('type vim', 'key Return', 'type x', f'key {MOD}+f', 'type wrap'),
                         ['editor.word_wrap'])

    def test_a_new_settings_tab_starts_unfiltered(self):
        everything = self.rows()
        self.assertEqual(self.rows('type vim', 'cmd close_tab', 'cmd settings'), everything)


if __name__ == '__main__':
    unittest.main()
