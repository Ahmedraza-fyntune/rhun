#!/usr/bin/env python3
"""The Extensions page's Contributions block (contribpage.s): an extension's commands with their
keys, its [keys] bindings with how each stands (active, overrides built-in, shadowed by your
[keys], refused), its menu items, status items, settings, grammars and [language.NAME] keys, file
icon themes, declared views, and the manifest entries that were dropped; drawn on its details."""
import sys
import unittest

contribhost = __import__('contribhost')
host = __import__('ext-host')

CONFIG = ('[ui]\nagents_panel = false\nfile_icons = alice/demo/tiny\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n'
          '[keys]\nctrl+alt+u = rhun.save\n')
EXTRA = '''[keys]
ctrl+k ctrl+h = ping hello there when editorFocus
ctrl+shift+p = pong
ctrl+alt+u = ping
x = ping
[menu.editor]
say.command = ping
say.when = editorHasSelection
say.group = demo
broken.command = ping
broken.when = (editorFocus
[menu.explorer]
more.submenu = tools
[submenu.tools]
title = Demo Tools
later.command = registered_later
[status]
build.text = $(play) Build
build.command = ping
build.align = left
build.priority = -5
build.when = projectOpen
[settings]
greeting.type = string
greeting.title = Greeting
greeting.default = hello
loud.type = bool
[language.Lua]
autoclose = ( ) [ ]
continue = ---
[views]
todo.title = TODO
todo.place = sidebar
todo.kind = tree
todo.when = projectOpen
[menu.nowhere]
a.command = ping
'''
SYN = 'name = Demo Lang\nfiles = *.demo\ncomment = #\n'
ICONS = 'title = Tiny\n[icons]\nfile = rhun:file\nrust = rhun:rust red\n[extensions]\nrs = rust\n'


class ContribPage(contribhost.Contrib):
    def setUp(self):
        super().setUp()
        (self.work / 'config/rhun/config').write_text(CONFIG, encoding='utf-8')

    def exts(self):
        root = self.work / 'exts'
        folder = self.make_ext(root, hello='hello 1 command-args commands', extra=EXTRA,
                               commands=('ping = Ping | ctrl+alt+g', 'pong = Pong'))
        (folder / 'syntax').mkdir()
        (folder / 'syntax/demo.syn').write_text(SYN, encoding='utf-8')
        (folder / 'icon-themes').mkdir()
        (folder / 'icon-themes/tiny.icons').write_text(ICONS, encoding='utf-8')
        return root

    def page(self, actions=()):
        out = self.run_editor(exts=self.exts(), files=(), drop_waits=True,
                              actions=list(actions) + ['print-ext-page-contributions alice/demo'])
        return [l for l in out if l.startswith(('head ', 'row '))]

    def section(self, rows, head):
        i = rows.index('head ' + head)
        rest = []
        for r in rows[i + 1:]:
            if r.startswith('head '):
                break
            rest.append(r)
        return rest

    def test_headings_in_order(self):
        rows = self.page()
        heads = [r[5:] for r in rows if r.startswith('head ')]
        self.assertEqual(heads, ['Commands', 'Keys', 'Menus', 'Status bar', 'Settings', 'Languages',
                                 'File icon themes', 'Views', 'Problems'])

    def test_commands_with_their_keys(self):
        rows = self.section(self.page(), 'Commands')
        self.assertEqual(len(rows), 2, rows)
        # the key in force: its [keys] chord wins over its [commands] default key
        chord = '⌘K ⌃H' if sys.platform == 'darwin' else 'Ctrl+K Ctrl+H'
        self.assertEqual(rows[0], 'row plain Ping -- demo.ping · ' + chord)
        self.assertTrue(rows[1].startswith('row plain Pong -- '), rows)

    def test_keys_and_how_each_stands(self):
        rows = self.section(self.page(), 'Keys')
        text = '\n'.join(rows)
        chord = [r for r in rows if 'Ping' in r and 'when editorFocus' in r]
        self.assertEqual(len(chord), 1, text)
        self.assertIn('active', chord[0])
        self.assertIn('arguments hello there', chord[0])
        self.assertTrue(chord[0].startswith('row plain '), chord)
        over = [r for r in rows if 'Pong' in r]
        self.assertEqual(len(over), 1, text)
        self.assertIn('overrides built-in Command Palette', over[0])
        shadowed = [r for r in rows if 'shadowed by your [keys]' in r]
        self.assertEqual(len(shadowed), 1, text)
        self.assertTrue(shadowed[0].startswith('row warning '), shadowed)
        refused = [r for r in rows if 'refused: a typing key needs a when guard' in r]
        self.assertEqual(len(refused), 1, text)
        self.assertTrue(refused[0].startswith('row warning '), refused)
        default = [r for r in rows if "the command's default key" in r]
        self.assertEqual(len(default), 1, text)

    def test_menus_status_settings(self):
        rows = self.page()
        menus = self.section(rows, 'Menus')
        self.assertIn('row plain editor: Ping -- group demo · when editorHasSelection', menus)
        self.assertIn('row warning editor: Ping -- its when clause does not compile', menus)
        self.assertIn('row plain explorer: Demo Tools >', menus)
        self.assertIn('row plain submenu tools: registered_later -- runs registered_later', menus)
        status = self.section(rows, 'Status bar')
        self.assertEqual(status, ['row plain $(play) Build -- left · priority -5 · runs ping'
                                  ' · when projectOpen'])
        settings = self.section(rows, 'Settings')
        self.assertEqual(settings, ['row plain Greeting -- greeting · text · default hello',
                                    'row plain loud -- loud · on or off · default no'])

    def test_languages_icons_views_problems(self):
        rows = self.page()
        langs = self.section(rows, 'Languages')
        self.assertEqual(langs, ['row plain Demo Lang -- a grammar · files *.demo',
                                 'row plain Lua -- language keys: autoclose, continue'])
        icons = self.section(rows, 'File icon themes')
        self.assertEqual(icons, ['row plain Tiny -- alice/demo/tiny · 2 icons · in use'])
        views = self.section(rows, 'Views')
        self.assertEqual(views, ['row plain TODO -- todo · tree · in the sidebar · when projectOpen'])
        problems = self.section(rows, 'Problems')
        self.assertTrue(problems, rows)
        self.assertTrue(all(p.startswith('row error ') for p in problems), problems)
        self.assertTrue(any('nowhere' in p for p in problems), problems)

    def test_the_page_draws_it(self):
        shot = self.work / 'page.ppm'
        out = self.run_editor(exts=self.exts(), files=(), drop_waits=True, actions=[
            'ext-page demo', 'move 500 400', 'scroll 900', 'shot ' + shot.as_posix(),
            'print-ext-page'])
        self.assertTrue(shot.exists(), out)
        self.assertTrue(any(l.startswith('Demo ') for l in out), out)


if __name__ == '__main__':
    unittest.main()
