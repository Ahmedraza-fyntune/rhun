#!/usr/bin/env python3
"""When clauses and context keys (docs/extensions/v1.1.md): the shared vectors
(tests/data/when-vectors.txt) evaluated in a headless editor, extension keys set with
set-context (feature context-keys) and [context] defaults, aliases and their ambiguity,
published built-in keys and the errors with their byte offsets."""
from pathlib import Path
import unittest

contribhost = __import__('contribhost')
VECTORS = Path(__file__).resolve().parent / 'data/when-vectors.txt'


def vectors():
    for line in VECTORS.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        result, _, clause = line.partition('\t')
        yield result, clause


class When(contribhost.Contrib):
    def setUp(self):
        super().setUp()
        (self.proj / 'main.rs').write_text('fn main() {}\n', encoding='utf-8')

    def exts(self, owners=('alice',), hello='hello 1 context-keys', actions=None):
        root = self.work / 'exts'
        default = {
            'setcount': ['set-context count 12'],
            'setmode': ['set-context mode insert mode'],
            'unset': ['set-context mode -'],
            'many': ['set-context k%d v' % i for i in range(64)],
            'badname': ['set-context Mode x', 'set-context 9x y', 'set-context mode fine', 'set-context mode'],
            'long': ['set-context mode ' + 'x' * 257, 'set-context mode ' + 'x' * 256],
        }
        for owner in owners:
            self.make_ext(root, owner=owner, hello=hello, actions=actions or default,
                          commands=[k + ' = ' + k for k in default],
                          extra='[context]\nmode = normal\n[settings]\ncolour.default = blue\n')
        return root

    def clause_lines(self, out):
        return [l for l in out if l.startswith('when')]

    def test_vectors(self):
        cases = list(vectors())
        actions = ['ctx-set view files', 'ctx-set viewItem file.ts', 'cmd demo.setcount',
                   'wait-ext demo running', 'wait 300']
        actions += ['when ' + clause for _, clause in cases]
        out = self.clause_lines(self.run_editor(exts=self.exts(), files=('main.rs',),
                                                drop_waits=True, actions=actions))
        self.assertEqual(len(out), len(cases), out)
        for (want, clause), got in zip(cases, out):
            with self.subTest(clause=clause):
                if want.startswith('error'):
                    self.assertTrue(got.startswith('when error at ' + want.split()[1] + ':'), got)
                else:
                    self.assertEqual(got, 'when=' + want)

    def test_error_texts(self):
        out = self.run_editor(exts=self.exts(), files=('main.rs',), drop_waits=True, actions=[
            'when resourceExtt', 'when editorFocus ==', 'when ' + 'x' * 513,
            'when ' + ' || '.join(['true'] * 33)])
        self.assertEqual(out, ['when error at 0: unknown key resourceExtt',
                               'when error at 14: expected a value',
                               'when error at 512: too long (512 bytes at most)',
                               'when error at 260: too many operations (64 at most)'])

    def test_context_default_before_start_and_after_stop(self):
        out = self.run_editor(exts=self.exts(), files=('main.rs',), drop_waits=True, actions=[
            'when demo.mode == normal',
            'cmd demo.setmode', 'wait-ext demo running', 'wait 300',
            'when demo.mode == "insert mode"', 'print-context demo.mode',
            'cmd demo.unset', 'wait 300', 'when demo.mode == normal',
            'cmd demo.setmode', 'wait 300', 'ext-set demo stop', 'wait-ext demo stopped',
            'when demo.mode == normal'])
        self.assertEqual(out, ['when=1', 'when=1', 'demo.mode=insert mode', 'when=1', 'when=1'])

    def test_limits_and_syntax(self):
        self.run_editor(exts=self.exts(), files=('main.rs',), drop_waits=True, actions=[
            'cmd demo.many', 'wait-ext demo running', 'wait 500',
            'cmd demo.badname', 'wait 300', 'cmd demo.long', 'wait 300'])
        log = self.contrib_log()
        oks = [l for l in log if l.startswith('ok ')]
        # mode (a default) and 63 new keys make 64; the 64th new key is refused
        self.assertEqual(len([l for l in log[:log.index('0 run demo.badname 1')] if l.startswith('ok ')]), 63)
        self.assertIn('error 64 toobig 64 keys', log)
        # two syntax errors, then a good request (three in a row would end the program)
        self.assertIn('error 65 syntax cannot parse the line', log)
        self.assertIn('error 66 syntax cannot parse the line', log)
        self.assertIn('ok 67', log)
        self.assertIn('error 68 syntax cannot parse the line', log)
        self.assertIn('error 69 toobig 256 bytes', log)
        self.assertIn('ok 70', log)
        self.assertTrue(oks)

    def test_unagreed_feature_is_unknown(self):
        out = self.run_editor(exts=self.exts(hello='hello 1'), files=('main.rs',), drop_waits=True,
                              actions=['cmd demo.setcount', 'wait-ext demo running', 'wait 300',
                                       'when demo.count'])
        self.assertIn('error 1 unknown no such request', self.contrib_log())
        self.assertEqual(out, ['when=0'])

    def test_ambiguous_alias(self):
        out = self.run_editor(exts=self.exts(owners=('alice', 'bob')), files=('main.rs',),
                              drop_waits=True, actions=[
                                  'when demo.mode == normal', 'when alice/demo.mode == normal',
                                  'when bob/demo.setting.colour == blue'])
        self.assertEqual(out, ['when error at 0: ambiguous extension name demo', 'when=1', 'when=1'])

    def test_published_keys(self):
        out = self.run_editor(exts=self.exts(), files=('main.rs',), drop_waits=True, actions=[
            'when debugState == inactive', 'ctx-set debugState running', 'when debugState == running',
            'ctx-set debugState -', 'print-context debugState', 'ctx-set viewItem ' + 'y' * 300,
            'when viewItem =~ "y*"', 'ctx-set editorFocus false', 'when editorFocus'])
        self.assertEqual(out, ['when=1', 'when=1', 'debugState=inactive', 'when=1', 'when=1'])

    def test_large_numbers_and_tab_kinds(self):
        out = self.run_editor(exts=self.exts(), files=('main.rs',), drop_waits=True, actions=[
            'ctx-set viewItem 1000000000000000000', 'when viewItem > 0',
            'ctx-set viewItem 0000000000000000005', 'when viewItem == 0000000000000000005 && viewItem > 4',
            'ctx-set viewItem 9223372036854775807', 'when viewItem > 9223372036854775806',
            'ctx-set viewItem 9223372036854775808', 'when viewItem > 0 || viewItem < 1',
            'ctx-set viewItem -9223372036854775808', 'when viewItem < -9223372036854775807',
            'cmd settings', 'when activeTab == settings && activeTab != image'])
        self.assertEqual(out, ['when=1', 'when=1', 'when=1', 'when=0', 'when=1', 'when=1'])

    def test_review_fixes(self):
        images = contribhost.ROOT / 'tests/data/images'
        png = next(p for p in sorted(images.iterdir()) if p.suffix == '.png')
        exts = self.exts(owners=('alice', 'bob'))
        manifest = exts / 'alice/demo/extension.ini'      # a quoted value that is not UTF-8
        manifest.write_bytes(manifest.read_bytes() + b"[command-options]\nsetcount.when = resourceLang == 'caf\xc3'\n")
        out = self.run_editor(exts=exts, files=('main.rs',), drop_waits=True,
                              actions=['ctx-set debugState running', 'ctx-set debugState -',
                                       'print-context debugState', 'print-context demo.mode',
                                       'print-contrib-problems alice/demo', 'open ' + png.as_posix(),
                                       'when activeTab == image && !editorFocus'])
        self.assertEqual(out[0], 'debugState=inactive')
        self.assertEqual(out[1], 'error at 0: ambiguous extension name demo')
        self.assertEqual(out[2], 'problem=[command-options] setcount.when: when: a quoted value that is not '
                                 'UTF-8 at byte 16')
        self.assertEqual(out[3], 'when=1')

    def test_long_setting_names(self):
        root = self.work / 'exts'
        key = 'k' * 64
        self.make_ext(root, hello='hello 1', extra=f'[settings]\n{key}.default = deep\n')
        out = self.run_editor(exts=root, files=('main.rs',), drop_waits=True, actions=[
            f'when demo.setting.{key} == deep', 'when demo.setting.' + 'k' * 65 + ' == deep'])
        self.assertEqual(out[0], 'when=1')
        self.assertTrue(out[1].startswith('when error at 0: unknown key'), out)

    def test_focus_and_panels(self):
        out = self.run_editor(exts=self.exts(), files=('main.rs',), drop_waits=True, actions=[
            'cmd command_palette', 'when paletteFocus && textInputFocus && !editorFocus',
            'key Escape', 'cmd find', 'when findFocus && findVisible', 'key Escape',
            'cmd toggle_terminal', 'wait 300', 'when terminalVisible && terminalFocus',
            'cmd toggle_sidebar', 'when sidebarVisible', 'cmd toggle_vim', 'cmd focus_explorer',
            'when vimMode == normal && explorerFocus'])
        self.assertEqual(out, ['when=1'] * 5)


if __name__ == '__main__':
    unittest.main()
