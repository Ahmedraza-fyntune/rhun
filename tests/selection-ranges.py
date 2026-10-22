#!/usr/bin/env python3
"""Expand and Shrink Selection (docs/extensions/v1.1.md, "selection-ranges"): the provider's
chains for every selection, a chain that breaks containment keeping its valid prefix, shrink going
back, and rhun's own chain without a provider."""
import unittest

lang = __import__('langfeat-query')

# a.rs: fn main() {\n    let total = 1;\n    total + 1\n}\n
CHAIN = '3\n2 9 2 14\n2 5 2 19\n1 1 4 2\n'


class SelectionRanges(lang.Lang):
    def sels(self, out):
        i = [k for k, l in enumerate(out) if l.startswith('sels=')]
        return [out[k + 1:k + 1 + int(out[k].split('=')[1])] for k in i]

    def at_total(self):
        return ['key ctrl+Home', 'key Down', 'key Home', 'key ctrl+Right', 'key Right', 'key Right']

    def provider_for(self, body):
        spec = {'hello': 'hello 1 selection-ranges', 'bodied': ['selection-ranges'],
                'answers': {'selection-ranges': {'body': body}}}
        return self.provider(spec, 'selection_ranges = *.rs\n')

    def test_expand_three_times_then_shrink(self):
        root = self.provider_for(CHAIN)
        out = self.run_lang(root, self.at_total() + ['key shift+alt+Right', 'wait 300', 'print-selections',
                                                     'key shift+alt+Right', 'print-selections', 'key shift+alt+Right',
                                                     'print-selections', 'key shift+alt+Left', 'print-selections'])
        s = self.sels(out)
        self.assertEqual([x[0] for x in s], ['2 9 2 14', '2 5 2 19', '1 1 4 2', '2 5 2 19'], out)
        log = self.lang_log()
        self.assertTrue(any(' selection-ranges 1 0 1 5' in l for l in log), log)
        self.assertIn('body 2 10\\n', log)
        self.assertEqual(sum(1 for l in log if ' selection-ranges ' in l), 1, log)   # one request for the chain

    def test_two_selections_and_a_broken_chain_prefix(self):
        body = '1\n3 5 3 10\n3\n2 9 2 14\n2 10 2 12\n1 1 4 2\n'      # the primary (the added caret) first
        root = self.provider_for(body)
        out = self.run_lang(root, self.at_total() + ['key ctrl+alt+Down', 'key shift+alt+Right', 'wait 300',
                                                     'print-selections', 'key shift+alt+Right', 'print-selections'])
        s = self.sels(out)
        self.assertEqual(s[0], ['3 5 3 10', '2 9 2 14'], out)
        self.assertEqual(s[1], ['3 5 3 10', '2 9 2 14'], out)     # nothing larger is valid
        self.assertIn('body 3 10\\n2 10\\n', self.lang_log())

    def test_an_edit_forgets_the_chain(self):
        root = self.provider_for(CHAIN)
        out = self.run_lang(root, self.at_total() + ['key shift+alt+Right', 'wait 300', 'key Right', 'key Left',
                                                     'key shift+alt+Right', 'wait 300', 'print-selections'])
        self.assertEqual(sum(1 for l in self.lang_log() if ' selection-ranges ' in l), 2, self.lang_log())

    def test_without_a_provider_word_line_text_line_document(self):
        root = self.provider({'hello': 'hello 1'}, 'definition = *.rs\n')
        steps = []
        for _ in range(4):
            steps += ['key shift+alt+Right', 'print-selections']
        out = self.run_lang(root, self.at_total() + steps)
        s = [x[0] for x in self.sels(out)]
        self.assertEqual(s, ['2 9 2 14', '2 5 2 19', '2 1 3 1', '1 1 5 1'], out)


if __name__ == '__main__':
    unittest.main()
