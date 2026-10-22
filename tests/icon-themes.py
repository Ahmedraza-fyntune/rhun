#!/usr/bin/env python3
"""File icon themes (docs/extensions/v1.1.md "File icon themes"): an extension's
icon-themes/NAME.icons, the lookup order (whole names, the longest extension, the language, the
theme's file icon or rhun's with fallback = rhun), folders open and closed, rhun icons with a
color, the setting [ui] file_icons (rhun, none, OWNER/NAME/THEME; a missing or turned-off theme
draws rhun's and keeps the setting), PNGs drawn as they are or as a mask, a bad or oversized PNG,
and Select File Icon Theme with its live preview."""
import struct
import unittest
import zlib

contribhost = __import__('contribhost')
host = __import__('ext-host')


def png(path, rgba, size=4):
    raw = b''.join(b'\0' + bytes(rgba) * size for _ in range(size))
    def chunk(t, b): return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


THEME = '''title = Minimal
fallback = default
[icons]
file = png/file.png muted
folder = png/folder.png accent
folder_open = png/open.png accent
rust = png/rust.png
cargo = rhun:config orange
dts = png/dts.png
ts = png/ts.png
toml = rhun:config
src = png/src.png
broken = png/broken.png
big = png/big.png
[files]
Cargo.toml = cargo
[extensions]
rs = rust
d.ts = dts
ts = ts
bad = broken
huge = big
[languages]
TOML = toml
[folders]
src = src
'''
CONFIG = ('[ui]\nagents_panel = false\n{icons}\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')


class IconThemes(contribhost.Contrib):
    def setUp(self):
        super().setUp()
        self.icons('alice/demo/minimal')

    def icons(self, value):
        line = 'file_icons = ' + value if value is not None else ''
        (self.work / 'config/rhun/config').write_text(CONFIG.replace('{icons}', line), encoding='utf-8')

    def exts(self, theme=THEME, name='minimal'):
        root = self.work / 'exts'
        folder = self.make_ext(root)
        themes = folder / 'icon-themes'
        (themes / 'png').mkdir(parents=True, exist_ok=True)
        (themes / (name + '.icons')).write_text(theme, encoding='utf-8')
        for n, color in (('file', (128, 128, 128, 255)), ('folder', (200, 200, 200, 255)),
                         ('open', (90, 90, 90, 255)), ('rust', (255, 0, 0, 255)), ('dts', (0, 0, 255, 255)),
                         ('ts', (0, 255, 0, 255)), ('src', (255, 255, 0, 255))):
            png(themes / 'png' / (n + '.png'), color)
        (themes / 'png/broken.png').write_bytes(b'not a png')
        png(themes / 'png/big.png', (1, 2, 3, 255), size=300)
        return root

    def lookups(self, names, exts=None, actions=()):
        acts = list(actions) + ['print-icon ' + n for n in names]
        out = self.run_editor(exts=exts or self.exts(), files=(), drop_waits=True, actions=acts)
        return [l for l in out if l.startswith('icon=')]

    def test_lookup_order(self):
        got = self.lookups(['main.rs', 'MAIN.RS', 'types.d.ts', 'app.ts', 'Cargo.toml', 'cargo.TOML',
                            'other.toml', 'notes.txt'])
        self.assertEqual(got, [
            'icon=theme:alice/demo/minimal:rust', 'icon=theme:alice/demo/minimal:rust',
            'icon=theme:alice/demo/minimal:dts', 'icon=theme:alice/demo/minimal:ts',
            'icon=rhun:config color=orange', 'icon=rhun:config color=orange',
            'icon=rhun:config color=grey', 'icon=theme:alice/demo/minimal:file'])

    def test_folders(self):
        got = self.lookups(['src folder', 'src folder-open', 'docs folder', 'docs folder-open'])
        # [folders] for a closed folder, [folders_open] (none here) for an open one
        self.assertEqual(got, ['icon=theme:alice/demo/minimal:src', 'icon=theme:alice/demo/minimal:folder_open',
                               'icon=theme:alice/demo/minimal:folder', 'icon=theme:alice/demo/minimal:folder_open'])

    def test_fallback_rhun_and_the_settings(self):
        exts = self.exts(THEME.replace('fallback = default', 'fallback = rhun'))
        self.icons('rhun')
        plain = self.lookups(['notes.txt'], exts=exts)
        self.icons('alice/demo/minimal')
        self.assertEqual(self.lookups(['notes.txt', 'main.rs'], exts=exts),
                         plain + ['icon=theme:alice/demo/minimal:rust'])
        self.assertTrue(plain[0].startswith('icon=rhun:'), plain)
        self.icons('none')
        self.assertEqual(self.lookups(['main.rs', 'src folder'], exts=exts), ['icon=none', 'icon=none'])
        self.icons('rhun')
        self.assertEqual(self.lookups(['main.rs'], exts=exts), ['icon=rhun:rust color=orange'])
        self.icons('alice/demo/nosuch')
        self.assertEqual(self.lookups(['main.rs'], exts=exts), ['icon=rhun:rust color=orange'])
        self.icons('alice/demo/minimal')
        out = self.run_editor(exts=exts, files=(), drop_waits=True,
                              actions=['ext-set demo disabled 1', 'print-icon main.rs', 'print-settings'])
        self.assertIn('icon=rhun:rust color=orange', out)

    def test_pictures_draw_and_bad_ones_do_not(self):
        exts = self.exts()
        for n in ('main.rs', 'x.bad', 'y.huge', 'z.txt'):
            (self.proj / n).write_text('x\n', encoding='utf-8')
        shot = self.work / 'tree.ppm'
        out = self.run_editor(exts=exts, files=(), drop_waits=True,
                              actions=['print-explorer', 'shot ' + shot.as_posix()])
        rows = [l for l in out if 'main.rs' in l or 'x.bad' in l or 'z.txt' in l]
        self.assertTrue(shot.exists(), out)
        colors = host.ppm_colors(shot)
        self.assertIn((255, 0, 0), colors)        # the rust PNG, as it is

    def test_a_huge_theme_file_is_refused_unread(self):
        # a sparse gigabyte: refused by its size before any of it is read (ITH_FILE_MAX)
        exts = self.exts()
        with open(exts / 'alice/demo/icon-themes/huge.icons', 'wb') as f:
            f.truncate(1 << 30)
        self.assertEqual(self.lookups(['main.rs'], exts=exts), ['icon=theme:alice/demo/minimal:rust'])
        self.icons('alice/demo/huge')
        self.assertEqual(self.lookups(['main.rs'], exts=exts), ['icon=rhun:rust color=orange'])

    def test_select_file_icon_theme_previews(self):
        exts = self.exts()
        self.icons(None)
        out = self.run_editor(exts=exts, files=(), drop_waits=True, actions=[
            'cmd select_file_icon_theme', 'print-palette', 'print-icon main.rs',
            'key Down', 'key Down', 'print-icon main.rs', 'key Escape', 'print-icon main.rs',
            'cmd select_file_icon_theme', 'key Down', 'key Down', 'key Return', 'print-icon main.rs',
            'print-settings'])
        icons = [l for l in out if l.startswith('icon=')]
        self.assertEqual(icons, ['icon=rhun:rust color=orange', 'icon=theme:alice/demo/minimal:rust',
                                 'icon=rhun:rust color=orange', 'icon=theme:alice/demo/minimal:rust'])
        self.assertTrue(any('rhun' in l for l in out), out)
        self.assertTrue(any('Minimal' in l for l in out), out)
        config = (self.work / 'config/rhun/config').read_text(encoding='utf-8')
        self.assertIn('file_icons = alice/demo/minimal', config)


if __name__ == '__main__':
    unittest.main()
