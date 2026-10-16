#!/usr/bin/env python3
"""The extensions as users meet them (docs/extensions/v1.md): the title bar's extensions button and
its dropdown, pinning, the Extensions page, an extension's own settings, on by default, turning
one off, removing one, and installing one from a release server (a local file:// tree laid out
as GitHub's, through RHUN_EXT_BASE): the permission dialog, the checksum, archives that reach
outside themselves. tests/ext-install-github.py does the same against github.com itself."""
import hashlib
import io
import os
from pathlib import Path
import sys
import tarfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
host = __import__('ext-host')

TARGET = 'macos-arm64' if sys.platform == 'darwin' else 'linux-x86_64'
HELLO_INI = '''name = hello
owner = demo
title = Hello
version = 1.2.0
description = Says hello.
protocol = 1
runtime = python3
run = main.py

[commands]
say = Say Hello | ctrl+alt+8

[settings]
word.type = string
word.default = hi

[needs]
documents = write
project = read
'''
HELLO_PY = r'''import sys
out = sys.stdout
out.write('hello 1\n'); out.flush()
word = 'hi'
doc_version = {}
for line in sys.stdin:
    f = line.rstrip('\n').split(' ')
    if f[:2] == ['0', 'setting'] and f[2] == 'word':
        word = line.rstrip('\n').split(' ', 3)[3]
    elif f[:2] in (['0', 'opened'], ['0', 'changed']):
        doc_version[f[2]] = f[3]
    elif f[:2] == ['0', 'run']:
        doc = f[3]
        out.write('1 insert %s %s %d\n%s' % (doc, doc_version.get(doc, '0'), len(word), word)); out.flush()
    elif f[:2] == ['0', 'bye']:
        break
'''


def archive(files, link=None):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w:gz') as tar:
        for name, text in files.items():
            data = text.encode()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            tar.addfile(info, io.BytesIO(data))
        if link:
            info = tarfile.TarInfo(link[0])
            info.type = tarfile.SYMTYPE
            info.linkname = link[1]
            tar.addfile(info)
    return buf.getvalue()


class UI(host.Host):
    def ui(self, actions, **kw):
        return self.run_editor(actions, drop_waits=True, **kw)

    def ini(self):
        p = self.work / 'config/rhun/extensions.ini'
        return p.read_text(encoding='utf-8') if p.exists() else ''

    # --- the dropdown, pins, the page ---

    def test_the_dropdown_opens_and_escape_closes_it(self):
        out = self.ui(['print-extbar', 'cmd extensions_menu', 'print-extbar', 'key Escape', 'print-extbar'])
        self.assertEqual(out[0], 'menu=closed')
        self.assertEqual(out[2], 'menu=open')
        self.assertEqual(out[4], 'menu=closed')

    def test_a_pin_is_remembered(self):
        out = self.ui(['ext-set echo pinned 1', 'print-extbar'])
        self.assertEqual(out[1], 'pinned=echo')
        self.assertIn('[rhun-tests/echo]\npinned = yes\n', self.ini())
        out = self.ui(['print-extbar'])
        self.assertEqual(out[1], 'pinned=echo')

    def test_the_page_lists_and_details_without_jargon(self):
        out = self.ui(['cmd extensions', 'print-ext-page', 'ext-page echo', 'print-ext-page', 'print-tabs'])
        self.assertEqual(out[0], 'Echo 0.0.1 on')
        self.assertEqual(out[1], 'Echo 0.0.1 on')
        self.assertEqual(out[2], 'pinned=0')
        self.assertEqual(out[3], 'can: read and change the files you have open, suggest terminal commands, which you run yourself')
        self.assertIn('setting greeting=Hello', out)
        self.assertIn('setting loud=no', out)
        self.assertIn('setting width=4', out)
        self.assertIn('setting style=plain', out)
        self.assertTrue(any('Extensions' in l for l in out), out)

    # --- its own settings ---

    def test_settings_reach_the_program_and_are_saved(self):
        out = self.ui(['ext-setting echo greeting Good morning', 'ext-setting echo loud yes', 'cmd echo.greet',
                       'wait-ext echo running', 'wait 300', 'wait 300', 'print-doc'])
        self.assertEqual(out[0], 'GOOD MORNINGhello world')
        log = self.echo_log(settings=True)
        self.assertIn('0 setting greeting Good morning', log)
        self.assertIn('0 setting loud yes', log)
        self.assertIn('setting.greeting = Good morning\n', self.ini())
        # a change while it runs arrives as an event
        self.ui(['cmd echo.toast', 'wait-ext echo running', 'wait 300', 'ext-setting echo width 6', 'wait 300'])
        self.assertIn('0 setting width 6', self.echo_log(settings=True))

    def test_settings_are_checked_against_their_type(self):
        out = self.ui(['ext-setting echo width 99', 'ext-setting echo style shiny', 'ext-setting echo loud maybe',
                       'ext-page echo', 'print-ext-page'])
        self.assertIn('setting width=8', out)          # clamped to its max
        self.assertIn('setting style=plain', out)      # not an option: unchanged
        self.assertIn('setting loud=no', out)          # not yes or no: unchanged

    # --- on by default, off, removed ---

    def test_an_extension_without_on_runs_from_the_start(self):
        exts = self.manifest_variant('startup', **{'on = command\n': ''})
        out = self.ui(['wait-ext echo running', 'print-extensions'], exts=exts)
        self.assertIn('state=running', out[0])

    def test_off_stops_it_and_keeps_it_off(self):
        out = self.ui(['cmd echo.toast', 'wait-ext echo running', 'ext-set echo disabled 1', 'wait 500',
                       'cmd echo.toast', 'wait 300', 'print-ext-page', 'cmd extensions', 'print-ext-page'])
        self.assertTrue(out[-1].startswith('Echo 0.0.1 off'), out)
        self.assertIn('disabled = yes', self.ini())
        out = self.ui(['print-extensions'])
        self.assertIn('state=disabled', out[0])

    def test_remove_asks_and_then_everything_goes(self):
        exts = self.manifest_variant('removable')
        out = self.ui(['cmd echo.toast', 'wait-ext echo running', 'ext-remove echo', 'print-dialog', 'dialog yes',
                       'wait 300', 'print-extensions', 'print-toast', 'key ctrl+shift+p', 'type echo', 'print-palette'],
                      exts=exts)
        self.assertEqual(out[0], 'dialog=Remove “Echo”?')
        self.assertEqual(out[2], 'button=Remove')
        self.assertEqual(out[3], 'toast=Removed Echo')
        self.assertFalse((exts / 'rhun-tests/echo').exists())
        self.assertNotIn('Echo', '\n'.join(out[4:]))     # no command of it left in the palette

    # --- installing ---

    def release(self, files=None, link=None, bad_sum=False, name='hello', owner='demo'):
        base = self.work / 'releases'
        d = base / owner / name / 'releases/latest/download'
        d.mkdir(parents=True, exist_ok=True)
        data = archive(files or {'extension.ini': HELLO_INI, 'main.py': HELLO_PY}, link)
        asset = '%s-%s.tar.gz' % (name, TARGET)
        (d / asset).write_bytes(data)
        digest = hashlib.sha256(data + (b'x' if bad_sum else b'')).hexdigest()
        (d / 'sha256sums.txt').write_text('%s  %s\n' % (digest, asset))
        self.env['RHUN_EXT_BASE'] = 'file://' + base.as_posix()
        return base

    def test_install_asks_with_the_permissions_and_runs_it(self):
        self.release()
        exts = self.manifest_variant('installs')
        out = self.ui(['ext-install demo/hello', 'wait-install', 'print-dialog', 'dialog yes', 'wait-ext hello running',
                       'wait 300', 'print-ext-page', 'cmd hello.say', 'wait 300', 'wait 300', 'print-doc'], exts=exts)
        self.assertEqual(out[0], 'install=asking')
        self.assertEqual(out[1], 'dialog=Add “Hello”?')
        self.assertEqual(out[2], 'text=Version 1.2.0 from github.com/demo/hello. It can read and change the files you have '
                                 'open, read the files in your project.')
        self.assertEqual(out[3], 'button=Add extension')
        self.assertTrue((exts / 'demo/hello/extension.ini').exists())
        self.assertFalse(any(p.name.startswith('.install') for p in exts.iterdir()))
        self.assertIn('hihello world', out)

    def test_cancel_leaves_nothing_behind(self):
        self.release()
        exts = self.manifest_variant('cancels')
        out = self.ui(['ext-install https://github.com/demo/hello', 'wait-install', 'dialog no', 'print-extensions'],
                      exts=exts)
        self.assertEqual(out[0], 'install=asking')
        self.assertFalse((exts / 'demo').exists() and any((exts / 'demo').iterdir()))
        self.assertFalse(any(p.name.startswith('.install') for p in exts.iterdir()))
        self.assertFalse(any(l.startswith('demo/hello') for l in out))

    def test_a_wrong_checksum_is_refused(self):
        self.release(bad_sum=True)
        exts = self.manifest_variant('badsum')
        out = self.ui(['ext-install demo/hello', 'wait-install', 'print-toast'], exts=exts)
        self.assertEqual(out[0], 'install=failed')
        self.assertEqual(out[1], 'toast=Could not install demo/hello: the download does not match its checksum')

    def test_an_archive_with_a_link_is_refused(self):
        self.release(link=('evil', '/etc/passwd'))
        exts = self.manifest_variant('badlink')
        out = self.ui(['ext-install demo/hello', 'wait-install', 'print-toast'], exts=exts)
        self.assertEqual(out[1], 'toast=Could not install demo/hello: the archive holds links or devices')

    def test_a_missing_release_says_so(self):
        self.env['RHUN_EXT_BASE'] = 'file://' + (self.work / 'nothing').as_posix()
        out = self.ui(['ext-install demo/hello', 'wait-install', 'print-toast'])
        self.assertEqual(out[1], 'toast=Could not install demo/hello: no release of demo/hello for ' + TARGET)

    def test_a_bad_name_is_refused_before_anything_runs(self):
        out = self.ui(['ext-install demo/../../etc', 'print-toast'])
        self.assertEqual(out[0], 'toast=Give the extension as owner/name, as on GitHub')


for _name in dir(host.Host):
    if _name.startswith('test_'):
        setattr(UI, _name, None)

if __name__ == '__main__':
    unittest.main()
