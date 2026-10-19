#!/usr/bin/env python3
"""Removing an extension leaves nothing of it behind (docs/guide.md, "Managing extensions"): its
folder, its previous version, its state folder and log, its section of extensions.ini (settings,
pin, off), the provider choices naming it and its update state go; the user's [keys] stay. A
linked extension's own folder stays too (tests/ext-dev-install.py)."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
host = __import__('ext-host')
updates = __import__('ext-updates')


class RemoveClean(updates.Updates):
    def test_remove_leaves_nothing_of_it(self):
        self.rel.publish('demo', 'hello', updates.files('0.1.0'), 'v0.1.0')
        self.install('demo/hello@0.1.0')
        self.rel.publish('demo', 'hello', updates.files('0.1.1'), 'v0.1.1')
        self.install('demo/hello@0.1.1', ['ext-setting hello word hey', 'ext-set hello pinned 1',
                                          'provider-set format Go demo/hello', 'provider-set rename * demo/other'])
        self.ui(['wait-ext hello running', 'ext-rollback demo/hello', 'wait-ext hello running'])   # update state: skip
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text(encoding='utf-8') + '[keys]\nctrl+alt+7 = demo/hello.say\n',
                          encoding='utf-8')
        state = self.work / 'state/rhun/extensions'
        ini = self.work / 'config/rhun/extensions.ini'
        self.assertIn('[demo/hello]', ini.read_text(encoding='utf-8'))
        self.assertIn('format.Go = demo/hello', ini.read_text(encoding='utf-8'))
        self.assertIn('[demo/hello]', self.updates_state())
        self.assertTrue((state / 'demo--hello').is_dir())
        self.assertTrue((state / 'demo--hello.log').exists())
        self.assertTrue((self.exts / '.previous/demo/hello').is_dir())
        out = self.ui(['wait-ext hello running', 'ext-remove hello', 'print-dialog', 'dialog yes', 'print-toast',
                       'print-extensions', 'print-providers'])
        self.assertIn('dialog=Remove “Hello”?', out)
        self.assertIn('text=Its settings and the data it saved go too.', out)
        self.assertIn('toast=Removed Hello', out)
        self.assertFalse(any(l.startswith('demo/hello ') for l in out), out)
        self.assertFalse((self.exts / 'demo/hello').exists())
        self.assertFalse((self.exts / '.previous/demo/hello').exists())
        self.assertFalse((state / 'demo--hello').exists())
        self.assertFalse((state / 'demo--hello.log').exists())
        text = ini.read_text(encoding='utf-8') if ini.exists() else ''
        self.assertNotIn('demo/hello', text)
        self.assertIn('rename.* = demo/other', text)          # another extension's choice stays
        self.assertNotIn('demo/hello', self.updates_state())
        self.assertIn('ctrl+alt+7 = demo/hello.say', config.read_text(encoding='utf-8'))


for _name in dir(host.Host):
    if _name.startswith('test_'):
        setattr(RemoveClean, _name, None)
for _name in dir(updates.Updates):
    if _name.startswith('test_'):
        setattr(RemoveClean, _name, None)

if __name__ == '__main__':
    unittest.main()
