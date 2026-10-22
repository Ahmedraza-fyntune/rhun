#!/usr/bin/env python3
"""Data extensions (docs/extensions/v1.1.md "Manifest: data extensions"): a manifest with no run,
run.TARGET, runtime, [commands], [provides] or pack is data. Its themes, grammars, icon themes and [language.NAME]
keys load, it is listed, installs from a folder like any extension, and no process ever starts;
its page has no Resources block. A manifest naming a program only for other targets, or commands
or language features without a program, still fails.
And a theme an extension brings, named in the config, is the theme rhun starts with."""
import configparser
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
host = __import__('ext-host')
updates = __import__('ext-updates')
import extrel  # noqa: E402

MANIFEST = 'name = {name}\nowner = demo\ntitle = {title}\nversion = 1.0.0\nprotocol = 1\n{extra}'
THEME = 'name = Oceanic Next\nkind = dark\nbg = #1b2b34\nfg = #d8dee9\naccent = #6699cc\n'
LIGHT = 'name = Oceanic Light\nkind = light\nbg = #f4f1e8\nfg = #2b303b\naccent = #4f6fa0\n'
SYNTAX = 'name = Oceanic Script\nfiles = *.oce\ncomment = #\nkeywords = when then done\n'
ICONS = 'title = Mini\n[icons]\ncfg = rhun:config orange\n[extensions]\noce = cfg\n'
OTHER = next(t for t in ('linux-x86_64', 'macos-arm64', 'windows-x64') if t != extrel.TARGET)
BG = (0x1b, 0x2b, 0x34)


def data_ext(root, name='oceanic', title='Oceanic', extra='', themes=None, syntax=None, icons=None):
    """A data extension ROOT/demo/NAME: a manifest without a program and its data files."""
    d = root / 'demo' / name
    d.mkdir(parents=True, exist_ok=True)
    (d / 'extension.ini').write_text(MANIFEST.format(name=name, title=title, extra=extra), encoding='utf-8')
    for folder, files in (('themes', themes), ('syntax', syntax), ('icon-themes', icons)):
        for fname, text in (files or {}).items():
            (d / folder).mkdir(exist_ok=True)
            (d / folder / fname).write_text(text, encoding='utf-8')
    return d


class Data(updates.Updates):
    def state_of(self, out, name='oceanic'):
        return [l for l in out if l.startswith('demo/%s ' % name)]

    def no_state_folder_log(self, name='oceanic'):
        folder = self.work / 'state/rhun/extensions' / ('demo--' + name)
        return not folder.exists() or not any(folder.iterdir())

    def test_a_theme_only_extension_is_listed_applies_and_never_starts(self):
        # on = startup asks for a start: there is nothing to start
        data_ext(self.exts, extra='on = startup\n', themes={'oceanic-next.theme': THEME})
        shot = self.work / 'shot.ppm'
        out = self.ui(['wait 300', 'print-extensions', 'ext-set oceanic restart', 'wait 300', 'print-extensions',
                       'cmd select_theme', 'type oceanic next', 'print-palette', 'key Return', 'print-state',
                       'shot ' + shot.as_posix(), 'print-ext-resources demo/oceanic', 'echo end-resources',
                       'ext-page oceanic', 'print-ext-page'])
        self.assertEqual(self.state_of(out), ['demo/oceanic state=idle pid=0 cmds= confined=0'] * 2)
        self.assertTrue(any('Oceanic Next' in l for l in out if not l.startswith('demo/')), out)
        self.assertIn('theme=oceanic-next', [l for l in out if l.startswith('tabs=')][0])
        self.assertEqual(host.ppm_pixel(shot, 700, 560), BG)
        # no Resources block: nothing between print-ext-resources and the echo
        i = out.index('end-resources')
        self.assertTrue(out[i - 1].startswith('tabs='), out)
        self.assertIn('Oceanic 1.0.0 on', out)
        self.assertFalse(any('problem=' in l for l in out), out)
        self.assertTrue(self.no_state_folder_log())
        # the picked theme is saved by its name and applies at the next start
        saved = configparser.ConfigParser(interpolation=None, strict=False)
        saved.read(self.work / 'config/rhun/config', encoding='utf-8')
        self.assertEqual(saved.get('ui', 'dark_theme'), 'oceanic-next')

    def test_a_grammar_only_extension_colours_a_file(self):
        (self.proj / 'x.oce').write_text('when a then b\n', encoding='utf-8')
        plain = self.ui(['print-state', 'print-syntax 1'], files=('x.oce',))
        data_ext(self.exts, name='oce-lang', title='Oceanic Script', syntax={'oce.syn': SYNTAX},
                 extra='[language.Oceanic_Script]\ncontinue = #\n')
        out = self.ui(['print-extensions', 'print-state', 'print-syntax 1', 'print-langconf'], files=('x.oce',))
        self.assertEqual(self.state_of(out, 'oce-lang'), ['demo/oce-lang state=idle pid=0 cmds= confined=0'])
        self.assertNotIn('lang=Oceanic Script', plain[0])
        self.assertIn('lang=Oceanic Script', [l for l in out if l.startswith('tabs=')][0])
        # print-syntax: the line, then a class digit per byte
        before, after = plain[2], out[3]
        self.assertEqual(len(set(before[:4])), 1, before)        # plain text: one class throughout
        self.assertNotEqual(after[:4], after[4:6] * 2, after)     # "when" is a keyword, " a" is not
        self.assertEqual(after[:4], after[7:11], after)          # "then" too
        self.assertIn('continue=# source=ext:demo/oce-lang', out)
        self.assertTrue(self.no_state_folder_log('oce-lang'))

    def test_an_icon_theme_only_extension_draws_its_icons(self):
        (self.work / 'config/rhun/config').write_text(host.CONFIG.replace('[ui]\n', '[ui]\nfile_icons = demo/icons/mini\n'),
                                                      encoding='utf-8')
        data_ext(self.exts, name='icons', title='Mini Icons', icons={'mini.icons': ICONS})
        out = self.ui(['print-extensions', 'print-icon x.oce'], files=())
        self.assertEqual(self.state_of(out, 'icons'), ['demo/icons state=idle pid=0 cmds= confined=0'])
        self.assertIn('icon=rhun:config color=orange', out)

    def test_installed_from_a_folder_its_theme_is_offered_at_once(self):
        src = data_ext(self.work / 'src', themes={'oceanic-next.theme': THEME})
        out = self.ui(['ext-install-folder %s copy' % src.as_posix(), 'wait-install', 'print-dialog', 'dialog yes',
                       'wait 300', 'print-extensions', 'print-ext-versions demo/oceanic',
                       'cmd select_theme', 'type oceanic next', 'print-palette', 'key Return', 'print-state'])
        self.assertIn('dialog=Add “Oceanic”?', out)
        self.assertEqual(self.state_of(out), ['demo/oceanic state=idle pid=0 cmds= confined=0'])
        self.assertIn('version=1.0.0 source=folder tag=- previous=- link=no fresh=0', out)
        self.assertTrue((self.exts / 'demo/oceanic/themes/oceanic-next.theme').exists())
        self.assertIn('theme=oceanic-next', [l for l in out if l.startswith('tabs=')][0])
        self.assertTrue(self.no_state_folder_log())
        # removing it takes its folder
        out = self.ui(['ext-remove oceanic', 'dialog yes', 'print-extensions'])
        self.assertEqual(self.state_of(out), [])
        self.assertFalse((self.exts / 'demo/oceanic').exists())

    def test_a_program_for_other_targets_only_still_fails(self):
        data_ext(self.exts, extra='run.%s = bin/x\n' % OTHER, themes={'oceanic-next.theme': THEME})
        data_ext(self.exts, name='script', title='Script', extra='run = main.py\n')
        # commands and language features need a program to answer them
        data_ext(self.exts, name='cmds', title='Cmds', extra='[commands]\nsay = Say\n')
        data_ext(self.exts, name='feats', title='Feats', extra='[provides]\ncomplete = *.txt\n')
        out = self.ui(['print-extensions', 'cmd select_theme', 'type oceanic next', 'print-palette'])
        self.assertIn('demo/oceanic state=failed reason=no program for this target in extension.ini pid=0 cmds= '
                      'confined=0', out)
        for name, cmds in (('script', ''), ('cmds', 'cmds.say'), ('feats', '')):
            self.assertIn('demo/%s state=failed reason=no program for this target in extension.ini pid=0 cmds=%s '
                          'confined=0' % (name, cmds), out)
        self.assertFalse(any('Oceanic Next' in l for l in out if not l.startswith('demo/')), out)

    # --- an extension's theme named in the config is the one rhun starts with ---

    def start_with(self, ui, system=None):
        (self.work / 'config/rhun/config').write_text(host.CONFIG.replace('[ui]\n', '[ui]\n' + ui), encoding='utf-8')
        if system:
            self.env['RHUN_APPEARANCE'] = system
        else:
            self.env.pop('RHUN_APPEARANCE', None)
        shot = self.work / 'start.ppm'
        out = self.ui(['print-appearance', 'shot ' + shot.as_posix()], files=())
        return dict(p.split('=', 1) for p in next(l for l in out if l.startswith('system=')).split()), shot

    def test_a_configured_extension_theme_applies_at_startup(self):
        data_ext(self.exts, themes={'oceanic-next.theme': THEME, 'oceanic-light.theme': LIGHT})
        # a config from before dark_theme and light_theme: its theme becomes the dark mode's, as a
        # theme in the user's own folder does
        state, shot = self.start_with('theme = oceanic-next\n')
        self.assertEqual((state['dark'], state['shown']), ('oceanic-next', 'oceanic-next'), state)
        self.assertEqual(host.ppm_pixel(shot, 500, 560), BG)
        state, _ = self.start_with('theme = oceanic-light\n', system='light')
        self.assertEqual((state['light'], state['shown']), ('oceanic-light', 'oceanic-light'), state)
        # follow_system with both modes named
        state, _ = self.start_with('follow_system = true\ndark_theme = oceanic-next\nlight_theme = oceanic-light\n',
                                   system='light')
        self.assertEqual(state['shown'], 'oceanic-light', state)
        state, shot = self.start_with('follow_system = true\ndark_theme = oceanic-next\nlight_theme = oceanic-light\n',
                                      system='dark')
        self.assertEqual(state['shown'], 'oceanic-next', state)
        self.assertEqual(host.ppm_pixel(shot, 500, 560), BG)
        # without follow_system, theme alone
        state, _ = self.start_with('follow_system = false\ntheme = oceanic-light\n', system='dark')
        self.assertEqual(state['shown'], 'oceanic-light', state)
        # a theme nobody has still falls back to the default, and the setting is kept
        state, _ = self.start_with('follow_system = false\ntheme = nosuch-theme\n')
        self.assertEqual((state['theme'], state['shown']), ('nosuch-theme', 'rhun-dark'), state)

    def test_a_configured_theme_of_a_program_extension_applies_at_startup(self):
        files = updates.files('0.1.0')
        d = self.exts / 'demo/hello'
        (d / 'themes').mkdir(parents=True)
        for name, text in files.items():
            (d / name).write_text(text, encoding='utf-8')
        (d / 'themes/oceanic-next.theme').write_text(THEME, encoding='utf-8')
        state, shot = self.start_with('theme = oceanic-next\n')
        self.assertEqual((state['dark'], state['shown']), ('oceanic-next', 'oceanic-next'), state)
        self.assertEqual(host.ppm_pixel(shot, 500, 560), BG)


for _name in dir(host.Host):
    if _name.startswith('test_'):
        setattr(Data, _name, None)
for _name in dir(updates.Updates):
    if _name.startswith('test_'):
        setattr(Data, _name, None)

if __name__ == '__main__':
    unittest.main()
