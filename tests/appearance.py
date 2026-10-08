#!/usr/bin/env python3
"""Follow system dark mode: the theme for the system's mode at startup and when it changes, the
theme list saving for the mode in use, Toggle Light/Dark Theme, live config reloads, and configs
from before dark_theme and light_theme keeping their theme.

Headless, so the system's mode comes from RHUN_APPEARANCE at startup and from the `appearance`
script command later, as a platform reports it (tests/linux-appearance.py covers the real sources).
"""
import configparser
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
BASE = ('[updates]\ncheck = false\n[git]\nenabled = false\n'
        '[files]\nrestore_session = false\nrestore_project = false\n'
        '[editor]\ncursor_blink = false\nauto_pairs = false\n')


class Appearance(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-appearance-')
        self.work = Path(self.tmp.name).resolve()
        (self.work / 'project').mkdir()
        self.config = self.work / 'config/rhun/config'
        self.config.parent.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions, config='', system=None):
        if config is not None:
            self.config.write_text(BASE + config, encoding='utf-8')
        env = dict(os.environ, HOME=self.work.as_posix(),
                   XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                   XDG_STATE_HOME=(self.work / 'state').as_posix())
        env.pop('RHUN_APPEARANCE', None)
        if system:
            env['RHUN_APPEARANCE'] = system
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), (self.work / 'project').as_posix(), '--headless',
                                 '1000x700', '--scale', '1', '--script', script.as_posix()],
                                env=env, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return [line for line in result.stdout.decode('utf-8').splitlines()]

    def states(self, *args, **kwargs):
        lines = self.run_editor(*args, **kwargs)
        return [dict(part.split('=', 1) for part in line.split())
                for line in lines if line.startswith('system=')]

    def saved(self):
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        parser.read(self.config, encoding='utf-8')
        return {key: parser.get('ui', key) for key in
                ('follow_system', 'theme', 'dark_theme', 'light_theme')}

    def test_defaults_follow_the_system(self):
        for system, shown in ((None, 'rhun-dark'), ('dark', 'rhun-dark'), ('light', 'rhun-light')):
            with self.subTest(system=system):
                state, = self.states(['print-appearance'], system=system)
                self.assertEqual(state, {'system': system or 'unknown', 'follow': '1',
                                         'theme': 'rhun-dark', 'dark': 'rhun-dark',
                                         'light': 'rhun-light', 'shown': shown})

    def test_system_changes_switch_the_theme_live(self):
        states = self.states(['appearance light', 'print-appearance', 'appearance dark',
                              'print-appearance', 'appearance light', 'appearance unknown',
                              'print-appearance', 'appearance light', 'appearance light',
                              'print-appearance'],
                             config='[ui]\ndark_theme = nord\nlight_theme = github-light\n')
        self.assertEqual([s['shown'] for s in states],
                         ['github-light', 'nord', 'nord', 'github-light'])
        # without follow_system the mode changes nothing
        states = self.states(['appearance light', 'print-appearance', 'appearance dark',
                              'print-appearance'],
                             config='[ui]\nfollow_system = false\ntheme = dracula\n', system='dark')
        self.assertEqual([s['shown'] for s in states], ['dracula', 'dracula'])

    def test_theme_list_saves_for_the_mode_in_use(self):
        for system, key in (('light', 'light_theme'), ('dark', 'dark_theme'), (None, 'dark_theme')):
            with self.subTest(system=system):
                states = self.states(['cmd select_theme', 'type everforest', 'key Return',
                                      'print-appearance'], system=system)
                self.assertEqual(states[0]['shown'], 'everforest')
                saved = self.saved()
                self.assertEqual(saved[key], 'everforest')
                self.assertEqual(saved['theme'], 'rhun-dark')
                other = 'dark_theme' if key == 'light_theme' else 'light_theme'
                self.assertEqual(saved[other], 'rhun-' + other.split('_')[0])
        # without follow_system, theme
        self.states(['cmd select_theme', 'type everforest', 'key Return'],
                    config='[ui]\nfollow_system = false\n', system='light')
        self.assertEqual(self.saved(), {'follow_system': 'false', 'theme': 'everforest',
                                        'dark_theme': 'rhun-dark', 'light_theme': 'rhun-light'})

    def test_theme_list_preview_escape_and_a_system_change_while_open(self):
        # Escape shows the settings' theme again; a mode change while the list is open waits for it
        states = self.states(['cmd select_theme', 'type github', 'key Down',
                              'print-appearance', 'appearance light', 'print-appearance',
                              'key Escape', 'print-appearance'], system='dark')
        self.assertEqual([s['shown'] for s in states], ['github-light', 'github-light', 'rhun-light'])
        # accepting after the change still saves for the mode the list was opened for
        self.states(['cmd select_theme', 'appearance light', 'type nord', 'key Return',
                     'print-appearance'], system='dark')
        self.assertEqual(self.saved()['dark_theme'], 'nord')
        self.assertEqual(self.saved()['light_theme'], 'rhun-light')

    def test_toggle_light_dark_theme(self):
        lines = self.run_editor(['cmd toggle_light_dark_theme', 'print-toast', 'print-appearance'],
                                system='light')
        self.assertIn("toast=The theme follows the system's dark mode (Settings)", lines)
        self.assertIn('shown=rhun-light', lines[-1])
        states = self.states(['cmd toggle_light_dark_theme', 'print-appearance',
                              'cmd toggle_light_dark_theme', 'print-appearance'],
                             config='[ui]\nfollow_system = false\ntheme = nord\n'
                                    'dark_theme = dracula\nlight_theme = github-light\n')
        self.assertEqual([s['shown'] for s in states], ['github-light', 'dracula'])
        self.assertEqual(self.saved()['theme'], 'dracula')

    def test_old_configs_keep_their_theme(self):
        # (theme, system) -> dark_theme, light_theme. The theme goes to its kind's setting and to
        # the one for the system's mode, so nothing changes on screen.
        cases = {('nord', 'dark'): ('nord', 'rhun-light'),
                 ('nord', 'light'): ('nord', 'nord'),
                 ('nord', None): ('nord', 'rhun-light'),
                 ('github-light', 'light'): ('rhun-dark', 'github-light'),
                 ('github-light', 'dark'): ('github-light', 'github-light'),
                 # the old default: the new defaults take over
                 ('rhun-dark', 'light'): ('rhun-dark', 'rhun-light'),
                 # a theme rhun does not have: the defaults
                 ('missing', 'dark'): ('rhun-dark', 'rhun-light')}
        for (theme, system), (dark, light) in cases.items():
            with self.subTest(theme=theme, system=system):
                state, = self.states(['print-appearance'], config=f'[ui]\ntheme = {theme}\n',
                                     system=system)
                self.assertEqual((state['dark'], state['light'], state['theme']), (dark, light, theme))
                if theme not in ('rhun-dark', 'missing'):
                    self.assertEqual(state['shown'], theme)
                    self.assertEqual(self.saved()['dark_theme'], dark)
                    self.assertEqual(self.saved()['light_theme'], light)
        # A config that has the new keys is taken as it is
        state, = self.states(['print-appearance'], system='light',
                             config='[ui]\ntheme = nord\nlight_theme = rhun-light\n')
        self.assertEqual((state['dark'], state['light'], state['shown']),
                         ('rhun-dark', 'rhun-light', 'rhun-light'))

    def test_old_configs_wait_for_a_mode_reported_later(self):
        # X11's XSETTINGS is read with the window and a portal may answer late: the mode found then
        # gets the old theme too, so the screen stays the same
        states = self.states(['print-appearance', 'appearance light', 'print-appearance',
                              'appearance dark', 'appearance light', 'print-appearance'],
                             config='[ui]\ntheme = nord\n')
        self.assertEqual([(s['system'], s['shown']) for s in states],
                         [('unknown', 'nord'), ('light', 'nord'), ('light', 'nord')])
        self.assertEqual((self.saved()['dark_theme'], self.saved()['light_theme']), ('nord', 'nord'))
        # unless a theme was picked first
        states = self.states(['cmd select_theme', 'type everforest', 'key Return', 'appearance light',
                              'print-appearance'], config='[ui]\ntheme = nord\n')
        self.assertEqual((states[0]['dark'], states[0]['light'], states[0]['shown']),
                         ('everforest', 'rhun-light', 'rhun-light'))
        # a light theme, the mode light after all: the dark mode's setting is as when light was known
        # at once
        state, = self.states(['appearance light', 'print-appearance'],
                             config='[ui]\ntheme = github-light\n')
        self.assertEqual(state['shown'], 'github-light')
        self.assertEqual((self.saved()['dark_theme'], self.saved()['light_theme']),
                         ('rhun-dark', 'github-light'))

    def test_escape_keeps_the_fallback_of_a_missing_theme(self):
        states = self.states(['print-appearance', 'cmd select_theme', 'type github', 'key Down',
                              'print-appearance', 'key Escape', 'print-appearance'],
                             config='[ui]\ndark_theme = nope\n')
        self.assertEqual([s['shown'] for s in states], ['rhun-dark', 'github-light', 'rhun-dark'])

    def test_unknown_theme_names_fall_back(self):
        state, = self.states(['print-appearance'], system='light',
                             config='[ui]\ndark_theme = nope\nlight_theme = nope\n')
        self.assertEqual(state['shown'], 'rhun-light')
        state, = self.states(['print-appearance'], system='dark',
                             config='[ui]\ndark_theme = nope\nlight_theme = nope\n')
        self.assertEqual(state['shown'], 'rhun-dark')
        # and when the system's mode changes to it while rhun runs
        state, = self.states(['appearance light', 'print-appearance'], system='dark',
                             config='[ui]\nlight_theme = nope\n')
        self.assertEqual(state['shown'], 'rhun-light')

    def test_leaving_the_theme_list_for_another_list(self):
        # a preview, or a change of the system's mode the open list held back, does not outlive it
        for actions, shown in ((['type github', 'key Down'], 'rhun-dark'),
                               (['appearance light'], 'rhun-light')):
            with self.subTest(actions=actions):
                state, = self.states(['cmd select_theme', *actions, 'cmd quick_open', 'key Escape',
                                      'print-appearance'], system='dark')
                self.assertEqual(state['shown'], shown)

    def edit_config(self, *lines):
        actions = ['cmd open_config', 'cmd select_all', 'key BackSpace']
        for line in (*lines, '[updates]', 'check = false'):
            actions += ['type ' + line, 'key Return']
        return actions + ['cmd save']

    def test_old_config_edited_to_the_old_default(self):
        # written in while rhun runs, rhun-dark is picked, not the old default left in the file
        states = self.states(['print-appearance', *self.edit_config('[ui]', 'theme = rhun-dark'),
                              'print-appearance'], config='[ui]\ntheme = nord\n', system='dark')
        self.assertEqual([s['shown'] for s in states], ['nord', 'rhun-dark'])

    def test_follow_system_turned_off_in_the_file(self):
        # theme becomes the theme shown, as in Settings
        states = self.states(['print-appearance',
                              *self.edit_config('[ui]', 'follow_system = false', 'theme = rhun-dark',
                                                'light_theme = github-light'),
                              'print-appearance'],
                             config='[ui]\nlight_theme = github-light\n', system='light')
        self.assertEqual([s['shown'] for s in states], ['github-light', 'github-light'])
        self.assertEqual(states[1]['theme'], 'github-light')
        # unless theme was changed too
        states = self.states(['print-appearance',
                              *self.edit_config('[ui]', 'follow_system = false', 'theme = nord'),
                              'print-appearance'],
                             config='[ui]\nlight_theme = github-light\n', system='light')
        self.assertEqual([s['shown'] for s in states], ['github-light', 'nord'])

    def test_saving_the_config_applies_it(self):
        lines = ['cmd open_config', 'cmd select_all', 'key BackSpace']
        for line in ('[ui]', 'follow_system = true', 'dark_theme = dracula',
                     'light_theme = everforest', '[updates]', 'check = false'):
            lines += ['type ' + line, 'key Return']
        states = self.states(['print-appearance', *lines, 'cmd save', 'print-appearance',
                              'appearance dark', 'print-appearance'],
                             config='[ui]\nfollow_system = false\ntheme = nord\n', system='light')
        self.assertEqual([s['shown'] for s in states], ['nord', 'everforest', 'dracula'])
        self.assertEqual(states[1]['follow'], '1')


if __name__ == '__main__':
    unittest.main(verbosity=2)
