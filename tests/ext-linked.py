#!/usr/bin/env python3
"""Feature linked-editing (docs/extensions/v1.1.md), driven headlessly with the wsx fake extension
(tests/ext/wsx.py) as the provider: after the cursor rests in a word rhun asks for the ranges that
change together; typing in one changes all of them (one undo step per edit), a character outside
the word set ends the session before it is typed, and an answer for another place is dropped."""
import unittest

ws = __import__('wsedit')
PD = ws.PD

RANGES = 'answer LEN\n2\n1 2 1 5\n2 3 2 6\n'


class Linked(ws.Ws):
    def setUp(self):
        super().setUp()
        (self.proj / 'p.html').write_text('<div>\n</div>\n')

    def run_html(self, exts, actions):
        return self.run_ws(exts, ['cmd wsx.x', 'wait-ext wsx running', 'wait 200', 'key ctrl+Home',
                                  'key Right', 'key Right', 'key Right', 'key Right', 'wait 400',
                                  *actions], files=('p.html',))

    def test_typing_in_the_opening_tag_renames_the_closing_one(self):
        exts = self.ext({'linked': RANGES, 'x': 'toast LEN\nhi'}, features='linked-editing')
        out = self.run_html(exts, ['print-linked', 'type x', 'type y', 'print-linked', PD, 'key space', 'wait 50',
                                   'print-linked', PD, 'key ctrl+z', PD, 'key ctrl+z', PD])
        log = self.extlines()
        self.assertTrue(any(l.split(' ')[1:2] == ['linked'] and l.endswith(' 1 5') for l in log), log)
        self.assertIn('linked=2', out)
        self.assertIn('1 2 1 5', out)
        self.assertIn('2 3 2 6', out)
        docs = self.docs(out)
        self.assertEqual(docs[0], '<divxy>\n</divxy>\n')
        self.assertEqual(docs[1], '<divxy >\n</divxy>\n')        # the space ended it first
        self.assertIn('linked=none', out)
        self.assertEqual(docs[2], '<divxy>\n</divxy>\n')
        self.assertEqual(docs[3], '<div>\n</div>\n')             # the typing and its mirrors: one step

    def test_no_session_for_a_stale_or_broken_answer(self):
        for name, plan in (('unequal', 'answer LEN\n2\n1 2 1 5\n2 3 2 5\n'),
                           ('outside', 'answer LEN\n2\n2 3 2 6\n1 2 1 3\n'),
                           ('one', 'answer LEN\n1\n1 2 1 5\n')):
            with self.subTest(name=name):
                exts = self.ext({'linked': plan, 'x': 'toast LEN\nhi'}, features='linked-editing')
                out = self.run_html(exts, ['print-linked', 'type x', PD])
                self.assertIn('linked=none', out)
                self.assertEqual(self.docs(out)[0], '<divx>\n</div>\n')

    def test_without_the_feature_rhun_does_not_ask(self):
        exts = self.ext({'linked': RANGES, 'x': 'toast LEN\nhi'}, features='')
        out = self.run_html(exts, ['print-linked'])
        self.assertIn('linked=none', out)
        self.assertFalse(any(' linked ' in l for l in self.extlines()), self.extlines())


for name in dir(ws.Ws):
    if name.startswith('test_'):
        setattr(Linked, name, None)

if __name__ == '__main__':
    unittest.main()
