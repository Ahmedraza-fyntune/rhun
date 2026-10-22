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

    def test_enter_and_tab_end_linking_before_they_insert(self):
        for key in ('Return', 'Tab'):
            with self.subTest(key=key):
                exts = self.ext({'linked': RANGES, 'x': 'toast LEN\nhi'}, features='linked-editing')
                out = self.run_html(exts, ['type x', 'key ' + key, 'wait 50', 'print-linked', PD])
                doc = self.docs(out)[0]
                self.assertTrue(doc.endswith('\n</divx>\n'), doc)          # not mirrored
                self.assertEqual(doc.count('</divx>'), 1, doc)
                self.assertTrue(doc.startswith('<divx'), doc)
                self.assertNotEqual(doc, '<divx>\n</divx>\n')              # it was inserted
                self.assertIn('linked=none', out)

    def test_each_document_keeps_its_own_session(self):
        (self.proj / 'q.html').write_text('<div>\n</div>\n')
        exts = self.ext({'linked': RANGES, 'x': 'toast LEN\nhi'}, features='linked-editing')
        rest = ['key ctrl+Home', 'key Right', 'key Right', 'key Right', 'key Right', 'wait 400']
        out = self.run_html(exts, ['type x', 'open ' + str(self.proj / 'q.html'), *rest, 'type y',
                                   'key ctrl+Tab', 'print-tabs', 'print-linked', 'key space', 'wait 50', PD,
                                   'print-linked', 'key ctrl+Tab', 'print-linked', PD])
        tabs = [l for l in out if l.startswith('tabs=')]
        self.assertIn('*p.html', tabs[0], out)
        linked = [l for l in out if l.startswith('linked=')]
        self.assertEqual(linked[0], 'linked=2', out)                   # p.html's, outlined again
        self.assertEqual(linked[1], 'linked=none', out)                # the space ended it
        self.assertEqual(linked[2], 'linked=2', out)                   # q.html's lives on
        docs = self.docs(out)
        self.assertEqual(docs[0], '<divx >\n</divx>\n')               # not mirrored into </divx>
        self.assertEqual(docs[1], '<divy>\n</divy>\n')


    def test_outlines_follow_inlays(self):
        # a 6-cell inlay ("count:") before the opening tag's name: the outline starts after it
        plans = {'linked': RANGES, 'x': 'toast LEN\nhi',
                 'dt': 'decoration-type arg LEN\nbefore inlay inlay_bg\n',
                 'dec': 'decorate {doc:p.html} {ver:p.html} arg 0 0 1 LEN\n1 2 1 2 6 0 0 0\ncount:'}
        exts = self.ext(plans, features='linked-editing decorations')
        on, off = self.work / 'on.ppm', self.work / 'off.ppm'
        out = self.run_ws(exts, ['cmd wsx.x', 'wait-ext wsx running', 'wait 200', 'cmd wsx.dt', 'wait 100',
                                 'cmd wsx.dec', 'wait 200', 'key ctrl+Home', 'key Right', 'key Right', 'key Right',
                                 'key Right', 'wait 400', 'print-linked', 'print-xy 1 3', 'print-xy 1 4',
                                 'shot ' + str(on), 'key Escape', 'wait 50', 'print-linked', 'shot ' + str(off)],
                          files=('p.html',))
        self.assertEqual([l for l in out if l.startswith('linked=')], ['linked=2', 'linked=none'], out)
        (x3, y), (x4, _) = (tuple(map(int, l.split())) for l in out if l[:1].isdigit() and len(l.split()) == 2)
        cw = x4 - x3
        start = x3 - cw                                    # where "div" begins, after the inlay
        a, b = on.read_bytes(), off.read_bytes()
        head = a.split(b'\n', 3)
        w = int(head[1].split()[0])
        body = len(a) - len(head[3])
        xs = [((i - body) // 3) % w for i in range(body, len(a), 3)
              if a[i:i + 3] != b[i:i + 3] and abs((i - body) // 3 // w - y) <= 8]   # line 1's row
        self.assertTrue(xs, 'the outline drew nothing')
        self.assertLessEqual(abs(min(xs) - start), 1, (min(xs), start, cw))   # not inside the inlay


for name in dir(ws.Ws):
    if name.startswith('test_'):
        setattr(Linked, name, None)

if __name__ == '__main__':
    unittest.main()
