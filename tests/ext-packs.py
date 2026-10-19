#!/usr/bin/env python3
"""Extension packs (docs/guide.md, "Packs"): a manifest's pack = OWNER/NAME … installs those
extensions with it. Installing a pack fetches it and every member not installed in one batch and
asks once, a line per member with what it can do and a line per member that could not be had; Add
installs all that downloaded. A pack has no program and never starts. Its page lists its members
with their state; removing it keeps them. An update of a pack that lists a new member asks."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
host = __import__('ext-host')
updates = __import__('ext-updates')
import extrel  # noqa: E402

PACK = '''name = essentials
owner = demo
title = Essentials
version = {version}
description = The demo extensions together.
protocol = 1
# a pack: other extensions installed with this one
pack = {members}
'''


def member(name, version='0.1.0', needs=''):
    files = updates.files(version, needs=needs)
    files['extension.ini'] = (files['extension.ini'].replace('name = hello', 'name = ' + name)
                              .replace('title = Hello', 'title = ' + name.capitalize())
                              .replace('[commands]\nsay = Say Hello', '[commands]\nsay = Say ' + name))
    return files


class Packs(updates.Updates):
    def pack(self, version='0.1.0', members='demo/one demo/two demo/three', latest=True):
        self.rel.publish('demo', 'essentials', {'extension.ini': PACK.format(version=version, members=members)},
                         'v' + version, latest=latest)

    def test_one_dialog_for_the_pack_and_its_members(self):
        self.rel.publish('demo', 'one', member('one'), 'v0.1.0')
        self.rel.publish('demo', 'two', member('two', needs='network = yes'), 'v0.1.0')
        self.pack()
        out = self.ui(['ext-install demo/one', 'wait-install', 'dialog yes', 'wait-ext one running',
                       'ext-install demo/essentials', 'wait-install', 'print-dialog', 'dialog yes', 'wait 300',
                       'print-toast', 'print-extensions', 'ext-page essentials', 'print-ext-page'])
        self.assertIn('dialog=Add “Essentials” and 1 extension?', out)
        self.assertIn('text=Version 0.1.0 from github.com/demo/essentials. It can only use its own commands and '
                      'settings.', out)
        self.assertIn('Two 0.1.0: read and change the files you have open, use the internet', out)
        self.assertIn('Could not get demo/three: no release of demo/three for %s' % extrel.TARGET, out)
        self.assertIn('toast=Added Essentials and 1 extension', out)
        states = [l for l in out if l.startswith(('demo/one ', 'demo/two ', 'demo/essentials '))]
        self.assertTrue(any(l.startswith('demo/essentials state=idle') for l in states), states)
        self.assertTrue(any(l.startswith('demo/two state=running') for l in states), states)
        self.assertIn('pack demo/one=installed demo/two=installed demo/three=missing', out)
        # removing the pack keeps its members
        out = self.ui(['ext-remove essentials', 'dialog yes', 'print-extensions'])
        self.assertFalse(any(l.startswith('demo/essentials ') for l in out))
        self.assertTrue(any(l.startswith('demo/one ') for l in out), out)
        self.assertTrue(any(l.startswith('demo/two ') for l in out), out)
        self.assertTrue((self.exts / 'demo/one/extension.ini').exists())

    def test_cancel_adds_nothing(self):
        self.rel.publish('demo', 'one', member('one'), 'v0.1.0')
        self.pack(members='demo/one')
        out = self.ui(['ext-install demo/essentials', 'wait-install', 'print-dialog', 'dialog no', 'print-extensions'])
        self.assertIn('dialog=Add “Essentials” and 1 extension?', out)
        self.assertFalse(any(l.startswith('demo/') for l in out if not l.startswith('dialog')), out)
        self.assertFalse(any(p.name.startswith('.install') for p in self.exts.iterdir()))

    def test_a_pack_list_naming_itself_or_not_owner_name_fails(self):
        self.pack(members='demo/essentials demo/one')
        out = self.ui(['ext-install demo/essentials', 'wait-install', 'dialog yes', 'print-extensions'])
        self.assertTrue(any(l.startswith('demo/essentials state=failed reason=pack in extension.ini must list')
                            for l in out), out)

    def test_an_update_listing_a_new_member_asks_for_it(self):
        self.rel.publish('demo', 'one', member('one'), 'v0.1.0')
        self.rel.publish('demo', 'two', member('two'), 'v0.1.0')
        self.pack(members='demo/one')
        self.ui(['ext-install demo/essentials', 'wait-install', 'dialog yes', 'wait 200'])
        self.pack(version='0.2.0', members='demo/one demo/two')
        with extrel.Server(self.rel) as srv:
            self.env['RHUN_EXT_BASE'] = srv.url
            out = self.ui(['ext-check-updates', 'wait-ext-updates', 'print-ext-updates', 'ext-update demo/essentials',
                           'wait-ext-updates', 'print-dialog', 'dialog yes', 'wait-ext-updates', 'wait 300',
                           'print-extensions'])
        self.assertIn('demo/essentials installed=0.1.0 latest=0.2.0 state=available from=github', out)
        self.assertIn('dialog=Update “Essentials” to 0.2.0?', out)
        self.assertIn('Two 0.1.0: read and change the files you have open', out)
        self.assertTrue(any(l.startswith('demo/two state=running') for l in out), out)
        self.assertTrue(any(l.startswith('demo/essentials state=idle') for l in out), out)


for _name in dir(host.Host):
    if _name.startswith('test_'):
        setattr(Packs, _name, None)
for _name in dir(updates.Updates):
    if _name.startswith('test_'):
        setattr(Packs, _name, None)

if __name__ == '__main__':
    unittest.main()
