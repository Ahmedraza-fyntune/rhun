#!/usr/bin/env python3
"""Document links and ctrl+click (docs/extensions/v1.1.md, "document-links"): links asked once per
document version, ctrl+click on a link opening its file at its line, ctrl+click elsewhere going to
the definition, and Open Link at the cursor."""
import unittest

lang = __import__('langfeat-query')
loc = lang.loc

B_RS = 'fn helper() {\n    let total = 2;\n}\n'


def link(l1, c1, l2, c2, target, tip=''):
    return f'{l1} {c1} {l2} {c2} {{len:{target}}} {len(tip.encode())}\n{target}{tip}'


class DocumentLinks(lang.Lang):
    def setUp(self):
        super().setUp()
        (self.proj / 'b.rs').write_text(B_RS, encoding='utf-8')

    def provider_for(self):
        spec = {'hello': 'hello 1 document-links definition', 'answers': {
            'document-links': {'body': '1\n' + link(1, 4, 1, 8, '{project}/b.rs:2:5', 'helper')},
            'definition': {'body': '1\n' + loc('{path}', 2, 9, 2, 14, 'total')}}}
        return self.provider(spec, 'document_links = *.rs\ndefinition = *.rs\n')

    def point(self, root, line, col):
        out = self.run_lang(root, [f'print-point {line} {col}'])
        x, y = [l for l in out if l.startswith('point ')][0].split()[1:]
        return x, y

    def test_open_link_at_the_cursor(self):
        root = self.provider_for()
        out = self.run_lang(root, ['key ctrl+Home', 'key Right', 'key Right', 'key Right', 'key Right',
                                   'cmd open_link', 'wait 300', 'print-doc-links', 'print-state'])
        self.assertIn('links doc=1 n=1', out)
        self.assertIn('1 4 1 8 ' + str(self.proj.resolve() / 'b.rs') + ':2:5', out)
        state = [l for l in out if l.startswith('tabs=')][-1]
        self.assertIn('active=b.rs line=2 col=5', state)
        self.assertEqual(sum(1 for l in self.lang_log() if ' document-links ' in l), 1)

    def test_ctrl_click_on_a_link_and_on_a_word(self):
        root = self.provider_for()
        x, y = self.point(root, 1, 5)
        x2, y2 = self.point(root, 2, 10)
        out = self.run_lang(root, [f'click {x} {y} ctrl', 'wait 300', 'print-state'])
        state = [l for l in out if l.startswith('tabs=')][-1]
        self.assertIn('active=b.rs line=2 col=5', state)
        out = self.run_lang(root, [f'click {x2} {y2} ctrl', 'wait 300', 'print-state'])
        log = self.lang_log()
        self.assertTrue(any(' definition 1 0 2 10 invoked -' in l for l in log), log)
        state = [l for l in out if l.startswith('tabs=')][-1]
        self.assertIn('active=a.rs line=2 col=14 sel=5', state)

    def test_no_link_at_the_cursor_says_so(self):
        root = self.provider_for()
        out = self.run_lang(root, ['key ctrl+End', 'cmd open_link', 'wait 300', 'print-toast'])
        self.assertIn('No link here', out[-1])


if __name__ == '__main__':
    unittest.main()
