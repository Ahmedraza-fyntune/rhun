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

    def test_a_version_rolled_back_to_never_rolls_back_by_itself(self):
        broken = lambda version: {'extension.ini': HELLO.format(version=version, needs='', extra_settings='')
                                  .replace('runtime = python3', 'runtime = no-such-runtime'), 'main.py': MAIN}
        self.rel.publish('demo', 'hello', broken('0.1.0'), 'v0.1.0')
        self.rel.publish('demo', 'hello', broken('0.1.1'), 'v0.1.1')
        out = self.ui(['ext-install demo/hello@0.1.0', 'wait-install', 'dialog yes', 'wait 200',
                       'ext-install demo/hello@0.1.1', 'wait-install', 'dialog yes', 'wait 500', 'print-toast',
                       'print-ext-versions demo/hello', 'ext-rollback demo/hello', 'wait 500', 'print-toast',
                       'print-ext-versions demo/hello'])
        self.assertIn('toast=Hello 0.1.1 did not start (runtime not found on PATH); back to 0.1.0', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=0.1.1 link=no fresh=0', out)
        self.assertIn('toast=Rolled back Hello to 0.1.1', out)
        self.assertIn('version=0.1.1 source=github tag=v0.1.1 previous=0.1.0 link=no fresh=0', out)
        self.assertEqual(self.record().get('kept'), 'yes')

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


    # --- update checks through GitHub's redirect (extensions the index does not list) ---

    def serve(self):
        srv = extrel.Server(self.rel)
        srv.__enter__()
        self.addCleanup(srv.__exit__)
        self.env['RHUN_EXT_BASE'] = srv.url
        return srv

    def test_a_check_offers_the_latest_release_and_update_asks_because_nobody_reviewed_it(self):
        self.serve()
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello')
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        out = self.ui(['wait-ext hello running', 'ext-check-updates', 'wait-ext-updates', 'print-ext-updates',
                       'print-toast', 'ext-page hello', 'print-ext-page', 'ext-page list', 'print-ext-page'])
        self.assertIn('demo/hello installed=0.1.0 latest=0.1.1 state=available from=github', out)
        self.assertIn('toast=1 extension update available', out)
        self.assertIn('versions update=0.1.1 previous=-', out)
        self.assertIn('updates=1', out)
        self.assertIn('latest = v0.1.1', self.updates_state())
        out = self.ui(['wait-ext hello running', 'ext-update demo/hello', 'wait-ext-updates', 'print-dialog',
                       'dialog yes', 'wait-ext-updates', 'wait-ext hello running', 'print-toast',
                       'print-ext-versions demo/hello', 'print-ext-updates'])
        self.assertIn('updates=asking', out)
        self.assertIn('dialog=Update “Hello” to 0.1.1?', out)
        self.assertIn('text=Not in the rhun extensions index: nobody has reviewed this version.', out)
        self.assertIn('toast=Updated Hello to 0.1.1', out)
        self.assertIn('version=0.1.1 source=github tag=v0.1.1 previous=0.1.0 link=no fresh=0', out)
        self.assertIn('demo/hello installed=0.1.1 latest=0.1.1 state=current from=github', out)

    def test_an_update_that_asks_for_more_says_what_and_cancel_keeps_it_waiting(self):
        self.serve()
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello')
        self.rel.publish('demo', 'hello', files('0.2.0', needs='network = yes\nrun = cargo'), 'v0.2.0')
        out = self.ui(['wait-ext hello running', 'ext-check-updates', 'wait-ext-updates', 'ext-update demo/hello',
                       'wait-ext-updates', 'print-dialog', 'dialog no', 'wait-ext-updates', 'print-ext-updates',
                       'print-ext-versions demo/hello'])
        self.assertIn('dialog=Update “Hello” to 0.2.0?', out)
        self.assertIn('text=Not in the rhun extensions index: nobody has reviewed this version.', out)
        self.assertIn('It now also asks to: use the internet, run cargo.', out)
        self.assertIn('demo/hello installed=0.1.0 latest=0.2.0 state=asks from=github', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=- link=no fresh=0', out)
        self.assertFalse(any(p.name.startswith('.install') for p in self.exts.iterdir()))

    def test_a_version_rolled_back_from_is_skipped_until_a_newer_one(self):
        self.serve()
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello')
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        self.install('demo/hello@0.1.1')
        out = self.ui(['wait-ext hello running', 'ext-rollback demo/hello', 'wait-ext hello running',
                       'ext-check-updates', 'wait-ext-updates', 'print-ext-updates'])
        self.assertIn('demo/hello installed=0.1.0 latest=0.1.1 state=skipped from=github', out)
        self.rel.publish('demo', 'hello', files('0.1.2'), 'v0.1.2')
        out = self.ui(['ext-check-updates', 'wait-ext-updates', 'print-ext-updates'])
        self.assertIn('demo/hello installed=0.1.0 latest=0.1.2 state=available from=github', out)

    def test_update_all_updates_each_one_after_another(self):
        self.serve()
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        other = {k: v.replace('name = hello', 'name = other').replace('title = Hello', 'title = Other')
                 .replace('say = Say Hello', 'say = Say Other') for k, v in files('1.0.0').items()}
        self.rel.publish('demo', 'other', other, 'v1.0.0')
        self.install('demo/hello')
        self.ui(['ext-install demo/other', 'wait-install', 'dialog yes', 'wait-ext other running'])
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        other = {k: v.replace('1.0.0', '1.1.0') for k, v in other.items()}
        self.rel.publish('demo', 'other', other, 'v1.1.0')
        out = self.ui(['ext-check-updates', 'wait-ext-updates', 'print-ext-page', 'ext-update-all', 'wait-ext-updates',
                       'print-dialog', 'dialog yes', 'wait-ext-updates', 'print-dialog', 'dialog yes',
                       'wait-ext-updates', 'wait 300', 'print-ext-updates'])
        self.assertIn('updates=2', out)
        self.assertIn('dialog=Update “Hello” to 0.1.1?', out)
        self.assertIn('dialog=Update “Other” to 1.1.0?', out)
        self.assertIn('demo/hello installed=0.1.1 latest=0.1.1 state=current from=github', out)
        self.assertIn('demo/other installed=1.1.0 latest=1.1.0 state=current from=github', out)

    def test_moved_repositories_and_ones_without_releases_say_why(self):
        self.serve()
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello')
        self.rel.moved['demo/hello'] = 'demo/hi'
        out = self.ui(['ext-check-updates', 'wait-ext-updates', 'print-ext-updates', 'print-toast'])
        self.assertIn('demo/hello installed=0.1.0 latest=- state=error moved to demo/hi', out)
        del self.rel.moved['demo/hello']
        del self.rel.latest['demo/hello']
        out = self.ui(['ext-check-updates', 'wait-ext-updates', 'print-ext-updates'])
        self.assertIn('demo/hello installed=0.1.0 latest=- state=error no release', out)

    def test_local_installs_are_never_checked_and_the_check_runs_by_itself_when_due(self):
        self.serve()
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello')
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        self.env['RHUN_EXT_UPDATE_EVERY'] = '400'
        out = self.ui(['wait 1500', 'wait-ext-updates', 'print-ext-updates', 'print-ext-versions demo/hello'])
        self.assertIn('checked=1 busy=0', out)
        self.assertIn('demo/hello installed=0.1.0 latest=0.1.1 state=available from=github', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=- link=no fresh=0', out)   # never by itself

    # --- review round 2 ---

    def test_long_section_names_in_the_update_state_are_read_safely(self):
        state = self.work / 'state/rhun/extension-updates'
        state.parent.mkdir(parents=True, exist_ok=True)
        owner = 'o' * 40
        state.write_text('checked = 1\n[%s/%s]\nlatest = v9.9.9\n[%s/%s]\nlatest = v1.0.0\n'
                         % (owner, 'n' * 59, owner, 'x' * 300), encoding='utf-8')
        out = self.ui(['print-ext-updates'])
        self.assertEqual(out[0], 'checked=1 busy=0')

    def test_updating_one_extension_more_than_128_times_reuses_its_record(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0', latest=False)
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        steps = ['ext-install demo/hello@0.1.0', 'wait-install', 'dialog yes',
                 'ext-install demo/hello@0.1.1', 'wait-install', 'dialog yes']
        steps += ['ext-rollback demo/hello'] * 131
        steps += ['ext-install demo/hello@0.1.0', 'wait-install', 'dialog yes', 'wait-ext hello running',
                  'print-toast', 'print-ext-slots', 'print-extensions', 'print-ext-versions demo/hello']
        out = self.ui(steps)
        self.assertIn('toast=Added Hello. Its commands are in the command palette.', out)
        self.assertIn('slots=1', out)
        hellos = [l for l in out if l.startswith('demo/hello ')]
        self.assertEqual(len(hellos), 1, hellos)
        self.assertIn('state=running', hellos[0])
        self.assertIn(' cmds=hello.say ', hellos[0])
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=0.1.0 link=no fresh=0', out)

    def test_an_update_found_for_github_is_not_installed_over_a_linked_folder(self):
        self.serve()
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text(encoding='utf-8').replace(
            '[updates]\ncheck = false\n', '[updates]\ncheck = false\nextensions = check\n'), encoding='utf-8')
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello')
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        out = self.ui(['ext-check-updates', 'wait-ext-updates', 'print-ext-updates'])
        self.assertIn('demo/hello installed=0.1.0 latest=0.1.1 state=available from=github', out)
        dev = self.work / 'dev'
        dev.mkdir()
        for name, text in files('0.2.0').items():
            (dev / name).write_text(text, encoding='utf-8')
        config.write_text(config.read_text(encoding='utf-8').replace('extensions = check\n', ''), encoding='utf-8')
        out = self.ui(['ext-install-folder %s link' % dev.as_posix(), 'wait-install', 'dialog yes',
                       'wait-ext hello running', 'print-ext-updates', 'ext-check-updates', 'wait-ext-updates',
                       'wait 300', 'print-ext-versions demo/hello', 'ext-update demo/hello', 'print-toast'])
        self.assertIn('demo/hello installed=0.2.0 latest=- state=current', out)
        self.assertIn('version=0.2.0 source=folder tag=- previous=0.1.0 link=yes fresh=0', out)
        self.assertIn('toast=No update is known for it; check for updates first', out)


for _name in dir(host.Host):
    if _name.startswith('test_'):
        setattr(Updates, _name, None)

if __name__ == '__main__':
    unittest.main()
