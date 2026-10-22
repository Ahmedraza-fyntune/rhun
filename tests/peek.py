#!/usr/bin/env python3
"""The peek view (docs/extensions/v1.1.md, "navigation"): Peek Definition and its siblings show
their locations in a read-only box under the cursor's line: one location, several (a file that
is not open is loaded without a tab), the keys, and a typed key closing it and reaching the
editor."""
import unittest

lang = __import__('langfeat-query')
loc = lang.loc

B_RS = 'fn helper() {\n    let total = 2;\n    total\n}\n'


class Peek(lang.Lang):
    def setUp(self):
        super().setUp()
        (self.proj / 'b.rs').write_text(B_RS, encoding='utf-8')

    def peeks(self, out):
        return [l for l in out if l.startswith('peek')]

    def nav(self, answers):
        spec = {'hello': 'hello 1 definition references navigation', 'answers': answers}
        return self.provider(spec, 'definition = *.rs\nreferences = *.rs\nimplementation = *.rs\n')

    def test_one_location_scrolls_and_escape_closes(self):
        root = self.nav({'definition': {'body': '1\n' + loc('{path}', 2, 9, 2, 14, 'let total = 1;')}})
        out = self.run_lang(root, ['key alt+F12', 'wait 300', 'print-peek', 'key Down', 'print-peek', 'key Escape',
                                   'print-peek', 'print-state'])
        p = self.peeks(out)
        self.assertEqual(p[0], 'peek open kind=definition file=a.rs first=1 sel=1/1', out)
        self.assertIn('* loc a.rs:2:9 let total = 1;', out)
        self.assertIn('first=2', p[1])          # one location: Down scrolls the code
        self.assertEqual(p[2], 'peek=closed')
        self.assertIn('line=1 col=1 sel=0', [l for l in out if l.startswith('tabs=')][0])   # the cursor stayed

    def test_several_locations_load_an_unopened_file_and_enter_opens_it(self):
        body = ('2\n' + loc('{path}', 3, 5, 3, 10, 'total + 1')
                + loc('{project}/b.rs', 2, 9, 2, 14, 'let total = 2;'))
        root = self.nav({'references': {'body': body}})
        out = self.run_lang(root, ['cmd peek_references', 'wait 300', 'print-peek', 'key Down', 'print-peek',
                                   'print-tabs', 'key Return', 'print-peek', 'print-state'])
        p = self.peeks(out)
        self.assertTrue(p[0].startswith('peek open kind=references file=a.rs'), out)
        self.assertIn('file=b.rs', p[1])
        self.assertIn('sel=2/2', p[1])
        self.assertIn('tabs=*a.rs', out)        # loaded without a tab
        self.assertEqual(p[2], 'peek=closed')
        state = [l for l in out if l.startswith('tabs=')][-1]
        self.assertIn('active=b.rs line=2 col=14 sel=5', state)

    def test_f4_cycles_and_a_typed_key_closes_and_types(self):
        body = ('2\n' + loc('{path}', 1, 4, 1, 8, 'fn main() {') + loc('{path}', 3, 5, 3, 10, 'total + 1'))
        root = self.nav({'implementation': {'body': body}})
        out = self.run_lang(root, ['cmd peek_implementation', 'wait 300', 'key F4', 'print-peek', 'key F4',
                                   'print-peek', 'key shift+F4', 'print-peek', 'type x', 'print-peek', 'echo ===',
                                   'print-doc'])
        p = self.peeks(out)
        self.assertIn('sel=2/2', p[0])
        self.assertIn('sel=1/2', p[1])
        self.assertIn('sel=2/2', p[2])
        self.assertEqual(p[3], 'peek=closed')
        doc = out[out.index('===') + 1]
        self.assertTrue(doc.startswith('x'), out)

    def test_nothing_found_says_so(self):
        root = self.nav({'definition': {'body': '0\n'}})
        out = self.run_lang(root, ['key alt+F12', 'wait 300', 'print-peek', 'print-toast'])
        self.assertIn('peek=closed', out)
        self.assertIn('No definition found', out[-1])


if __name__ == '__main__':
    unittest.main()
