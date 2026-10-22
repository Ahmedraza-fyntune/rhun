#!/usr/bin/env python3
"""prepare-rename and partial-format (docs/extensions/v1.1.md): the placeholder and the range of
a prepared rename, a refusal that stops F2, formatting as you type with the document's options,
an on-type edit dropped once the document moved on, and formatting pasted text."""
import unittest

lang = __import__('langfeat-query')
host = lang.host


class Rename(lang.Lang):
    def spec(self, prepare, hello='hello 1 rename prepare-rename'):
        edit = '1\n{len:{path}} {version} 1\n{path}2 9 2 14 3\nsum'
        return {'hello': hello, 'answers': {'prepare-rename': prepare, 'rename': {'body': edit}}}

    def test_the_placeholder_and_range_fill_the_prompt(self):
        root = self.provider(self.spec({'body': '2 9 2 14 5\ntotal'}), 'rename = *.rs\n')
        out = self.run_lang(root, ['key ctrl+Home', 'key Down', 'key F2', 'wait 400', 'print-palette', 'print-state',
                                   'key ctrl+a', 'type sum', 'key Return', 'wait 400', 'print-doc'])
        self.assertIn('prompt=New name', out)
        self.assertIn('field=total', out)
        self.assertTrue(any(' line=2 col=14 sel=5' in l for l in out), out)
        self.assertIn('    let sum = 1;', out)
        self.assertTrue(any(' prepare-rename 1 0 2 1 invoked -' in l for l in self.lang_log()), self.lang_log())

    def test_a_refusal_shows_its_reason_and_renames_nothing(self):
        root = self.provider(self.spec({'error': 'refused You cannot rename a keyword'}), 'rename = *.rs\n')
        out = self.run_lang(root, ['key ctrl+Home', 'key F2', 'wait 400', 'print-palette', 'print-toast'])
        self.assertIn('You cannot rename a keyword', out[-1])
        self.assertIn('none', out)
        self.assertFalse(any(l.split()[1:2] == ['rename'] and l[:2] != '0 ' for l in self.lang_log()), self.lang_log())

    def test_a_provider_stopping_during_prepare_opens_the_prompt(self):
        spec = dict(self.spec({'silent': True}), run={'die': [['EXIT', '']]})
        root = self.provider(spec, 'rename = *.rs\n', extra='[commands]\ndie = Die\n')
        out = self.run_lang(root, ['key ctrl+Home', 'key Right', 'key F2', 'wait 200', 'cmd lang.die', 'wait 500',
                                   'print-palette'])
        self.assertIn('field=fn', out)          # as with no answer: the word at the cursor

    def test_an_empty_answer_uses_the_word_at_the_cursor(self):
        root = self.provider(self.spec({'body': ''}), 'rename = *.rs\n')
        out = self.run_lang(root, ['key ctrl+Home', 'key Right', 'key F2', 'wait 400', 'print-palette'])
        self.assertIn('field=fn', out)


class OnType(lang.Lang):
    EDIT = '1\n{len:{path}} {version} 1\n{path}3 1 3 1 2\n  '

    def spec(self, delay=0):
        return {'hello': 'hello 1 format partial-format', 'answers': {
            'type-format': {'body': self.EDIT, 'delay': delay},
            'range-format': {'body': '1\n{len:{path}} {version} 1\n{path}1 1 1 1 3\n// '}}}

    MANIFEST = 'format = *.rs\ntype_format = *.rs\ntype_format.triggers = ; newline\nrange_format = *.rs\n'

    def config(self, text):
        (self.work / 'config/rhun/config').write_text(host.CONFIG + '[editor]\n' + text)

    def test_a_trigger_asks_and_the_edit_is_its_own_undo_step(self):
        self.config('format_on_type = yes\n')
        root = self.provider(self.spec(), self.MANIFEST)
        out = self.run_lang(root, ['key ctrl+Home', 'key Down', 'key End', 'type ;', 'wait 400', 'print-doc',
                                   'key ctrl+z', 'print-doc', 'key Return', 'wait 300'])
        req = [l for l in self.lang_log() if ' type-format ' in l]
        self.assertEqual(req[0].split()[2:], ['1', '1', '2', '20', ';', '4', 'yes', 'no', 'yes'], req)
        self.assertEqual(req[1].split()[6], 'newline', req)
        self.assertIn('    let total = 1;;', out)
        self.assertIn('      total + 1', out[:out.index('<eod>')])
        second = out[out.index('<eod>') + 1:]
        self.assertIn('    total + 1', second)

    def test_off_by_default_and_without_a_trigger(self):
        root = self.provider(self.spec(), self.MANIFEST)
        self.run_lang(root, ['key ctrl+Home', 'key Down', 'key End', 'type ;', 'wait 300'])
        self.assertFalse(any(' type-format ' in l for l in self.lang_log()))
        self.config('format_on_type = yes\n')
        self.run_lang(root, ['key ctrl+Home', 'key Down', 'key End', 'type x', 'wait 300'])
        self.assertFalse(any(' type-format ' in l for l in self.lang_log()))

    def test_an_edit_for_an_older_version_is_dropped(self):
        self.config('format_on_type = yes\n')
        root = self.provider(self.spec(delay=0.3), self.MANIFEST)
        out = self.run_lang(root, ['key ctrl+Home', 'key Down', 'key End', 'type ;', 'type x', 'wait 600',
                                   'print-doc'])
        self.assertIn('    total + 1', out)
        self.assertEqual(len([l for l in self.lang_log() if ' type-format ' in l]), 1)

    def test_an_edit_for_another_language_is_dropped(self):
        self.config('format_on_type = yes\n')
        root = self.provider(self.spec(delay=0.3), self.MANIFEST)
        out = self.run_lang(root, ['key ctrl+Home', 'key Down', 'key End', 'type ;', 'cmd select_language',
                                   'type Python', 'key Return', 'wait 600', 'print-state', 'print-doc'])
        self.assertTrue(any(' lang=Python ' in l for l in out if l.startswith('tabs=')), out)
        self.assertIn('    total + 1', out)       # not indented by the Rust formatter's late edit

    def test_pasted_lines_are_range_formatted(self):
        self.config('format_on_paste = yes\n')
        root = self.provider(self.spec(), self.MANIFEST)
        out = self.run_lang(root, ['key ctrl+Home', 'key shift+End', 'cmd copy', 'key End', 'key Return',
                                   'cmd paste', 'wait 400', 'print-doc'])
        req = [l for l in self.lang_log() if ' range-format ' in l]
        self.assertEqual(req[0].split()[4:8], ['2', '1', '2', '16'], req)
        self.assertIn('// fn main() {', out)

    def test_a_late_paste_format_answer_is_dropped(self):
        self.config('format_on_paste = yes\n')
        spec = self.spec()
        spec['answers']['range-format']['delay'] = 0.8
        root = self.provider(spec, self.MANIFEST)
        out = self.run_lang(root, ['key ctrl+Home', 'key shift+End', 'cmd copy', 'key End', 'key Return',
                                   'cmd paste', 'wait 1200', 'print-doc'])
        self.assertNotIn('// fn main() {', out)
        rid = [l.split()[0] for l in self.lang_log() if ' range-format ' in l][0]
        self.assertIn('0 cancel ' + rid, self.lang_log())


if __name__ == '__main__':
    unittest.main()
