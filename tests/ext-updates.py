#!/usr/bin/env python3
"""Extension versions and updates (docs/guide.md, "Managing extensions"): exact tags and @version,
the install record, keeping one previous version and Roll back (by hand, and by itself when a new
version fails its first start), rhun://extension links, the expansion limit, the latest release
resolved through GitHub's /releases/latest redirect, update checks, automatic updates of reviewed
versions, the "asks for more" rule, skip after a roll back. Releases come from tests/extrel.py: a
file:// tree, or a local server that answers as github.com does."""
import os
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
host = __import__('ext-host')
import extrel  # noqa: E402

HELLO = '''name = hello
owner = demo
title = Hello
version = {version}
description = Says hello.
protocol = 1
runtime = python3
run = main.py

[commands]
say = Say Hello

[settings]
word.type = string
word.default = hi
{extra_settings}
[needs]
documents = write
{needs}
'''
MAIN = r'''import sys
out = sys.stdout
out.write('hello 1\n'); out.flush()
for line in sys.stdin:
    if line.startswith('0 bye'):
        break
'''
DIES = 'import sys\nsys.exit(3)\n'


def files(version, needs='', main=MAIN, extra_settings=''):
    return {'extension.ini': HELLO.format(version=version, needs=needs, extra_settings=extra_settings),
            'main.py': main}


class Updates(host.Host):
    def setUp(self):
        super().setUp()
        self.rel = extrel.Releases(self.work / 'releases')
        self.exts = self.work / 'exts'
        self.exts.mkdir()
        self.env['RHUN_EXT_BASE'] = self.rel.root.as_uri()
        for k in ('http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY', 'all_proxy', 'ALL_PROXY'):
            self.env.pop(k, None)

    def ui(self, actions, **kw):
        return self.run_editor(actions, drop_waits=True, exts=self.exts, **kw)

    def versions(self, out):
        return [l for l in out if l.startswith('version=')]

    def updates_state(self):
        p = self.work / 'state/rhun/extension-updates'
        return p.read_text(encoding='utf-8') if p.exists() else ''

    def record(self):
        p = self.exts / 'demo/hello/.rhun-install'
        return dict(re.findall(r'^(\w+) = (.*)$', p.read_text(encoding='utf-8'), re.M)) if p.exists() else {}

    def install(self, spec, extra=()):
        return self.ui(['ext-install ' + spec, 'wait-install', 'print-dialog', 'dialog yes', 'wait-ext hello running',
                        'print-ext-versions demo/hello', *extra])

    # --- exact tags, the record, the previous version ---

    def test_an_exact_tag_installs_that_release_and_records_it(self):
        digest = self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0', latest=False)
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        out = self.install('demo/hello@0.1.0')
        self.assertEqual(out[0], 'install=asking')
        self.assertEqual(out[1], 'dialog=Add “Hello”?')
        self.assertEqual(out[2], 'text=Version 0.1.0 from github.com/demo/hello. It can read and change the files you '
                                 'have open.')
        self.assertEqual(out[3], 'Not in the rhun extensions index: nobody has reviewed it.')
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=- link=no fresh=0', out)
        rec = self.record()
        self.assertEqual(rec['repository'], 'demo/hello')
        self.assertEqual(rec['sha256'], digest)
        self.assertEqual(rec['reviewed'], 'no')
        self.assertRegex(rec['installed'], r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$')

    def test_a_tag_that_does_not_exist_says_so(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        out = self.ui(['ext-install demo/hello@v9.9.9', 'wait-install', 'print-toast'])
        self.assertEqual(out[0], 'install=failed')
        self.assertEqual(out[1], 'toast=Could not install demo/hello: no release v9.9.9 of demo/hello for %s'
                         % extrel.TARGET)

    def test_a_new_version_keeps_the_old_one_and_roll_back_swaps_them(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello@0.1.0')
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        out = self.install('demo/hello@0.1.1', ['wait 300', 'print-ext-versions demo/hello'])
        self.assertIn('version=0.1.1 source=github tag=v0.1.1 previous=0.1.0 link=no fresh=0', out)   # it said hello
        self.assertEqual(self.record().get('started'), 'yes')
        self.assertTrue((self.exts / '.previous/demo/hello/extension.ini').exists())
        out = self.ui(['wait-ext hello running', 'ext-rollback demo/hello', 'wait-ext hello running', 'print-toast',
                       'print-ext-versions demo/hello', 'print-extensions'])
        self.assertIn('toast=Rolled back Hello to 0.1.0', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=0.1.1 link=no fresh=0', out)
        self.assertIn('skip = v0.1.1', self.updates_state())
        out = self.ui(['wait-ext hello running', 'ext-rollback demo/hello', 'wait-ext hello running',
                       'print-ext-versions demo/hello'])
        self.assertIn('version=0.1.1 source=github tag=v0.1.1 previous=0.1.0 link=no fresh=0', out)
        self.assertFalse(any(p.name.startswith('.swap') for p in (self.exts / '.previous/demo').iterdir()))

    def test_roll_back_without_a_previous_version_says_so(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        out = self.install('demo/hello', ['ext-rollback demo/hello', 'print-toast'])
        self.assertIn('toast=There is no previous version to go back to', out)

    def test_a_version_that_exits_before_hello_rolls_back_by_itself(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello@0.1.0')
        self.rel.publish('demo', 'hello', files('0.1.1', main=DIES), 'v0.1.1')
        out = self.ui(['ext-install demo/hello@0.1.1', 'wait-install', 'dialog yes', 'wait 1500', 'wait-ext hello running',
                       'print-toast', 'print-ext-versions demo/hello'])
        self.assertIn('toast=Hello 0.1.1 did not start (exited with status 3); back to 0.1.0', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=0.1.1 link=no fresh=0', out)
        self.assertIn('skip = v0.1.1', self.updates_state())

    def test_rolling_back_to_a_version_that_may_do_more_asks(self):
        self.rel.publish('demo', 'hello', files('0.1.0', needs='network = yes'), 'v0.1.0')
        self.install('demo/hello@0.1.0')
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        self.install('demo/hello@0.1.1')
        out = self.ui(['wait-ext hello running', 'ext-rollback demo/hello', 'print-dialog', 'dialog no',
                       'print-ext-versions demo/hello', 'ext-rollback demo/hello', 'dialog yes',
                       'wait-ext hello running', 'print-ext-versions demo/hello'])
        self.assertIn('dialog=Roll back “Hello” to 0.1.0?', out)
        self.assertIn('text=It then also asks to: use the internet.', out)
        self.assertIn('version=0.1.1 source=github tag=v0.1.1 previous=0.1.0 link=no fresh=0', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=0.1.1 link=no fresh=0', out)

    def test_settings_survive_roll_back_and_forward(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello@0.1.0')
        extra = 'tone.type = string\ntone.default = calm\n'
        self.rel.publish('demo', 'hello', files('0.1.1', extra_settings=extra), 'v0.1.1')
        self.install('demo/hello@0.1.1', ['ext-setting hello tone loud', 'ext-setting hello word hey'])
        out = self.ui(['wait-ext hello running', 'ext-rollback demo/hello', 'wait-ext hello running',
                       'ext-rollback demo/hello', 'wait-ext hello running', 'ext-page hello', 'print-ext-page'])
        self.assertIn('setting word=hey', out)
        self.assertIn('setting tone=loud', out)

    # --- links and limits ---

    def test_a_rhun_extension_link_asks_to_add(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0', latest=False)
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        out = self.ui(['open rhun://extension/demo/hello%400.1.0', 'wait-install', 'print-dialog', 'dialog no',
                       'open RHUN://Extension/demo/hello', 'wait-install', 'print-dialog', 'dialog no'])
        self.assertEqual(out[0], 'install=asking')
        self.assertEqual(out[1], 'dialog=Add “Hello”?')
        self.assertTrue(out[2].startswith('text=Version 0.1.0 from github.com/demo/hello.'), out)
        self.assertTrue(out[7].startswith('text=Version 0.1.1 from github.com/demo/hello.'), out)
        self.assertFalse((self.exts / 'demo').exists() and any((self.exts / 'demo').iterdir()))

    def test_an_archive_that_unpacks_past_64_mb_is_refused(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0', big=65 * 1024 * 1024)
        out = self.ui(['ext-install demo/hello', 'wait-install', 'print-toast'])
        self.assertEqual(out[0], 'install=failed')
        self.assertEqual(out[1], 'toast=Could not install demo/hello: the archive unpacks to more than 64 MB')
        self.assertFalse(any(p.name.startswith('.install') for p in self.exts.iterdir()))

    # --- GitHub's latest release, through its redirect ---

    def test_the_latest_release_is_resolved_to_its_exact_tag(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.rel.publish('demo', 'hello', files('0.1.2'), 'v0.1.2')
        with extrel.Server(self.rel) as srv:
            self.env['RHUN_EXT_BASE'] = srv.url
            out = self.install('demo/hello')
        self.assertIn('version=0.1.2 source=github tag=v0.1.2 previous=- link=no fresh=0', out)

    def test_a_repository_without_releases_says_so(self):
        with extrel.Server(self.rel) as srv:
            self.env['RHUN_EXT_BASE'] = srv.url
            out = self.ui(['ext-install demo/nothing', 'wait-install', 'print-toast'])
        self.assertEqual(out[1], 'toast=Could not install demo/nothing: demo/nothing has no release')


for _name in dir(host.Host):
    if _name.startswith('test_'):
        setattr(Updates, _name, None)

if __name__ == '__main__':
    unittest.main()
