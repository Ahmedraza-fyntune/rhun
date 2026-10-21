#!/usr/bin/env python3
"""The rhun extensions index and Browse (docs/guide.md, "Browse"): index.ini fetched from
rhun-editor/extensions' latest release (its checksum checked) and cached, the Browse list's search
and order, each card's button (Install, Installed, Update to X, Not for this system, Needs rhun X),
installs from a card at the pinned tag with the index's digest checked (a changed archive is
refused), an index in a newer format, the cached copy when the index cannot be fetched, and
updates from the index: the only ones installed by themselves, never one that asks for more."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
host = __import__('ext-host')
updates = __import__('ext-updates')
import extrel  # noqa: E402

files = updates.files


class Browse(updates.Updates):
    def index(self, **more):
        """showcase (featured), hello at 0.2.0, one for another system, one for a newer rhun."""
        self.rel.publish('rhun-editor', 'showcase', files('0.1.2').copy() | {
            'extension.ini': files('0.1.2')['extension.ini'].replace('name = hello', 'name = showcase')
            .replace('owner = demo', 'owner = rhun-editor').replace('title = Hello', 'title = Showcase')}, 'v0.1.2')
        self.rel.publish('demo', 'hello', files('0.2.0'), 'v0.2.0')
        entries = {
            'rhun-editor/showcase': self.rel.entry('rhun-editor', 'showcase', 'v0.1.2', 'Showcase', featured='yes',
                                                   description='A tour of everything an extension can do.',
                                                   keywords='demo tour example', needs='documents=write'),
            'demo/hello': self.rel.entry('demo', 'hello', 'v0.2.0', 'Hello', needs='documents=write'),
            'demo/elsewhere': {'title': 'Elsewhere', 'version': '1.0.0', 'tag': 'v1.0.0',
                               'sha256.plan9-mips': '0' * 64},
            'demo/future': {'title': 'Future', 'version': '1.0.0', 'tag': 'v1.0.0', 'rhun': '99.0.0',
                            'sha256.' + extrel.TARGET: '0' * 64},
            'demo/broken': {'title': 'No version'},
        }
        entries.update(more)
        return self.rel.index(entries)

    def browse(self, extra=()):
        return self.ui(['ext-browse', 'wait-index', 'print-ext-browse', *extra])

    def test_browse_lists_the_index_with_a_button_for_each_state(self):
        self.index()
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0', latest=False)
        self.install('demo/hello@0.1.0')
        out = self.browse()
        self.assertEqual(out[0], 'index=4 format=1 fetching=0')     # the entry without a version is left out
        self.assertEqual(out[1:5], ['rhun-editor/showcase 0.1.2 button=install',
                                    'demo/elsewhere 1.0.0 button=unavailable',
                                    'demo/future 1.0.0 button=newer',
                                    'demo/hello 0.2.0 button=update'])
        self.assertTrue((self.work / 'state/rhun/extension-index.ini').exists())

    def test_search_words_start_words_of_the_title_name_description_or_keywords(self):
        self.index()
        out = self.browse(['ext-search tour', 'print-ext-browse', 'ext-search HELLO', 'print-ext-browse',
                           'ext-search ex tou', 'print-ext-browse', 'ext-search our', 'print-ext-browse'])
        lists = [i for i, l in enumerate(out) if l.startswith('index=')]
        self.assertEqual(out[lists[1] + 1:lists[2]], ['rhun-editor/showcase 0.1.2 button=install'])
        self.assertEqual(out[lists[2] + 1:lists[3]], ['demo/hello 0.2.0 button=install'])
        self.assertEqual(out[lists[3] + 1:lists[4]], ['rhun-editor/showcase 0.1.2 button=install'])
        self.assertEqual(out[lists[4] + 1:], [])

    def test_install_from_a_card_is_the_pinned_reviewed_version(self):
        self.index()
        self.rel.publish('demo', 'hello', files('0.3.0'), 'v0.3.0')   # newer on GitHub, not reviewed yet
        out = self.browse(['ext-browse-install demo/hello', 'wait-install', 'print-dialog', 'dialog yes',
                           'wait-ext hello running', 'print-ext-versions demo/hello', 'print-ext-browse'])
        self.assertIn('dialog=Add “Hello”?', out)
        self.assertIn('text=Version 0.2.0 from github.com/demo/hello. It can read and change the files you have open.',
                      out)
        self.assertIn('Reviewed for the rhun extensions index.', out)
        self.assertIn('version=0.2.0 source=github tag=v0.2.0 previous=- link=no fresh=0', out)
        self.assertIn('demo/hello 0.2.0 button=installed', out)
        self.assertEqual(self.record()['reviewed'], 'yes')
        # Install from GitHub with the name alone installs the pinned version too
        out = self.ui(['ext-install demo/hello', 'wait-install', 'print-dialog', 'dialog no'])
        self.assertTrue(any(l.startswith('text=Version 0.2.0 ') for l in out), out)

    def test_an_archive_changed_after_review_is_refused(self):
        self.index()
        self.rel.tamper('demo', 'hello', 'v0.2.0')
        out = self.browse(['ext-browse-install demo/hello', 'wait-install', 'print-toast'])
        self.assertIn('toast=Could not install demo/hello: the download is not the version the rhun extensions '
                      'index reviewed', out)
        self.assertFalse((self.exts / 'demo/hello').exists())

    def test_an_index_in_a_newer_format_is_not_used(self):
        self.rel.publish('demo', 'hello', files('0.2.0'), 'v0.2.0')
        self.rel.index({'demo/hello': self.rel.entry('demo', 'hello', 'v0.2.0', 'Hello')}, fmt=2)
        out = self.browse(['ext-install demo/hello', 'wait-install', 'print-dialog', 'dialog no'])
        self.assertEqual(out[0], 'index=1 format=2 fetching=0')
        self.assertIn('Not in the rhun extensions index: nobody has reviewed it.', out)

    def test_the_cached_index_serves_when_it_cannot_be_fetched(self):
        self.index()
        self.browse()
        self.env['RHUN_EXT_BASE'] = (self.work / 'nowhere').as_uri()
        out = self.ui(['ext-browse', 'ext-index-refresh', 'wait-index', 'print-ext-browse'])
        self.assertEqual(out[0], 'index=4 format=1 fetching=0 error=the index could not be downloaded')
        self.assertIn('rhun-editor/showcase 0.1.2 button=install', out)

    def test_an_index_that_does_not_match_its_checksum_is_refused(self):
        self.rel.index({'demo/x': {'title': 'X', 'version': '1.0.0', 'tag': 'v1.0.0'}}, sums_ok=False)
        out = self.browse()
        self.assertEqual(out[0], 'index=0 format=0 fetching=0 error=the index does not match its checksum')

    # --- updates from the index ---

    def config(self, mode):
        p = self.work / 'config/rhun/config'
        p.write_text(p.read_text(encoding='utf-8').replace('[updates]\ncheck = false\n',
                                                          '[updates]\ncheck = false\nextensions = %s\n' % mode),
                     encoding='utf-8')

    def test_reviewed_updates_install_by_themselves_and_unreviewed_newer_ones_wait_for_review(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello')
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        self.rel.publish('demo', 'hello', files('0.1.5'), 'v0.1.5')     # GitHub's latest: not reviewed
        self.rel.index({'demo/hello': self.rel.entry('demo', 'hello', 'v0.1.1', 'Hello')})
        out = self.ui(['wait-ext hello running', 'ext-check-updates', 'wait-ext-updates', 'wait-ext hello running',
                       'print-ext-updates', 'print-ext-versions demo/hello', 'print-toast'])
        self.assertIn('demo/hello installed=0.1.1 latest=0.1.1 state=current from=index', out)
        self.assertIn('version=0.1.1 source=github tag=v0.1.1 previous=0.1.0 link=no fresh=0', out)
        self.assertIn('toast=Updated Hello to 0.1.1', out)
        self.assertEqual(self.record()['reviewed'], 'yes')

    def test_check_mode_only_shows_reviewed_updates(self):
        self.config('check')
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello')
        self.rel.publish('demo', 'hello', files('0.1.1'), 'v0.1.1')
        self.rel.index({'demo/hello': self.rel.entry('demo', 'hello', 'v0.1.1', 'Hello')})
        out = self.ui(['wait-ext hello running', 'ext-check-updates', 'wait-ext-updates', 'print-ext-updates',
                       'print-ext-versions demo/hello', 'ext-update demo/hello', 'wait-ext-updates', 'print-dialog',
                       'wait-ext hello running', 'print-ext-versions demo/hello'])
        self.assertIn('demo/hello installed=0.1.0 latest=0.1.1 state=available from=index', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=- link=no fresh=0', out)
        self.assertIn('dialog=none', out)                                 # reviewed, no more access: no dialog
        self.assertIn('version=0.1.1 source=github tag=v0.1.1 previous=0.1.0 link=no fresh=0', out)

    def test_a_reviewed_update_that_asks_for_more_waits_and_a_skipped_one_stays_skipped(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello')
        self.rel.publish('demo', 'hello', files('0.2.0', needs='network = yes'), 'v0.2.0')
        self.rel.index({'demo/hello': self.rel.entry('demo', 'hello', 'v0.2.0', 'Hello')})
        out = self.ui(['wait-ext hello running', 'ext-check-updates', 'wait-ext-updates', 'print-ext-updates',
                       'print-ext-versions demo/hello'])
        self.assertIn('demo/hello installed=0.1.0 latest=0.2.0 state=asks from=index', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=- link=no fresh=0', out)
        self.assertIn('asks = v0.2.0', self.updates_state())
        out = self.ui(['wait-ext hello running', 'ext-update demo/hello', 'wait-ext-updates', 'print-dialog',
                       'dialog yes', 'wait-ext-updates', 'wait-ext hello running', 'print-ext-versions demo/hello'])
        self.assertIn('dialog=Update “Hello” to 0.2.0?', out)
        self.assertIn('text=It now also asks to: use the internet.', out)
        self.assertIn('version=0.2.0 source=github tag=v0.2.0 previous=0.1.0 link=no fresh=0', out)
        out = self.ui(['wait-ext hello running', 'ext-rollback demo/hello', 'wait-ext hello running',
                       'ext-check-updates', 'wait-ext-updates', 'print-ext-updates', 'print-ext-versions demo/hello'])
        self.assertIn('demo/hello installed=0.1.0 latest=0.2.0 state=skipped from=index', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=0.2.0 link=no fresh=0', out)

    # --- review round 2 ---

    def reviewed_update_asks(self, needs):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello')
        self.rel.publish('demo', 'hello', files('0.2.0', needs=needs), 'v0.2.0')
        self.rel.index({'demo/hello': self.rel.entry('demo', 'hello', 'v0.2.0', 'Hello')})
        out = self.ui(['wait-ext hello running', 'ext-check-updates', 'wait-ext-updates', 'print-ext-updates',
                       'print-ext-versions demo/hello', 'ext-update demo/hello', 'wait-ext-updates', 'print-dialog',
                       'dialog no'])
        self.assertIn('demo/hello installed=0.1.0 latest=0.2.0 state=asks from=index', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=- link=no fresh=0', out)
        self.assertIn('dialog=Update “Hello” to 0.2.0?', out)
        return [l for l in out if l.startswith('text=')]

    def test_a_reviewed_update_that_adds_git_access_asks(self):
        self.assertEqual(self.reviewed_update_asks('git = read'),
                         ["text=It now also asks to: read the project's Git history."])

    def test_a_reviewed_update_that_adds_debug_adapters_asks(self):
        self.assertEqual(self.reviewed_update_asks('debug = yes'),
                         ['text=It now also asks to: start debug adapters that run as you.'])

    def test_a_reviewed_update_that_adds_a_long_program_path_asks(self):
        tool = '/opt/' + 'very-long-folder-name/' * 8 + 'tool'
        self.assertEqual(self.reviewed_update_asks('run = gofmt ' + tool),
                         ['text=It now also asks to: run gofmt ' + tool + '.'])

    def test_a_reviewed_version_that_needs_a_newer_rhun_is_not_installed(self):
        self.rel.publish('demo', 'hello', files('0.1.0'), 'v0.1.0')
        self.install('demo/hello')
        self.rel.publish('demo', 'hello', files('0.2.0'), 'v0.2.0')
        self.rel.index({'demo/hello': self.rel.entry('demo', 'hello', 'v0.2.0', 'Hello', rhun='99.0.0')})
        out = self.ui(['wait-ext hello running', 'ext-check-updates', 'wait-ext-updates', 'wait 300',
                       'print-ext-updates', 'print-ext-versions demo/hello', 'ext-install demo/hello', 'wait-install',
                       'print-toast', 'ext-browse', 'print-ext-browse'])
        self.assertIn('demo/hello installed=0.1.0 latest=- state=error the reviewed version needs rhun 99.0.0 '
                      'from=index', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=- link=no fresh=0', out)
        self.assertIn('toast=Could not install demo/hello: the reviewed version needs rhun 99.0.0', out)
        self.assertIn('demo/hello 0.2.0 button=newer', out)

    def test_oversized_or_malformed_index_values_are_left_out(self):
        self.rel.publish('demo', 'hello', files('0.2.0'), 'v0.2.0')
        out = self.rel.index({
            'demo/hello': self.rel.entry('demo', 'hello', 'v0.2.0', 'Hello'),
            'demo/longtag': {'title': 'Long tag', 'version': '1.0.0', 'tag': 'v' + '1' * 500,
                             'sha256.' + extrel.TARGET: '0' * 64},
            'demo/baddigest': {'title': 'Bad digest', 'version': '1.0.0', 'tag': 'v1.0.0',
                               'sha256.' + extrel.TARGET: 'not-a-digest'},
            'demo/badversion': {'title': 'Bad version', 'version': 'one', 'tag': 'v1.0.0',
                                'sha256.' + extrel.TARGET: '0' * 64},
            ('o' * 150) + '/longowner': {'title': 'Long owner', 'version': '1.0.0', 'tag': 'v1.0.0'},
        })
        out = self.ui(['ext-browse', 'wait-index', 'print-ext-browse', 'ext-install demo/longtag', 'wait-install',
                       'print-toast'])
        self.assertEqual(out[0], 'index=2 format=1 fetching=0')
        self.assertIn('demo/baddigest 1.0.0 button=unavailable', out)
        self.assertIn('demo/hello 0.2.0 button=install', out)
        self.assertIn('install=failed', out)        # not pinned: no release of it, and no crash


for _name in dir(host.Host):
    if _name.startswith('test_'):
        setattr(Browse, _name, None)
for _name in dir(updates.Updates):
    if _name.startswith('test_'):
        setattr(Browse, _name, None)

if __name__ == '__main__':
    unittest.main()
