#!/usr/bin/env python3
"""Features reveal and diff (docs/extensions/v1.1.md), driven headlessly with the wsx fake
extension (tests/ext/wsx.py): reveal scrolls a document's view without moving its cursor,
show-locations lists locations in the palette as Find All References does, and diff opens a
read-only diff tab of two open documents that follows them and closes with them."""
import unittest

ws = __import__('wsedit')
PD = ws.PD


class Reveal(ws.Ws):
    def setUp(self):
        super().setUp()
        (self.proj / 'long.txt').write_text(''.join('line %d\n' % i for i in range(1, 201)))

    def scroll(self, out):
        return [int(l.split(' y=')[1].split()[0]) for l in out if l.startswith('x=')]

    def test_reveal_scrolls_without_moving_the_cursor(self):
        plans = {w: 'reveal {doc:long.txt} 150 1 %s' % w for w in ('top', 'center', 'nearest')}
        plans['cio'] = 'reveal {doc:long.txt} 5 1 center-if-outside'
        plans['bad'] = 'reveal {doc:long.txt} 999 1 top'
        plans['word'] = 'reveal {doc:long.txt} 5 1 middle'
        exts = self.ext(plans, features='reveal')
        out = self.run_ws(exts, ['cmd wsx.top', 'wait-ext wsx running', 'wait 300', 'print-scroll', 'print-state',
                                 'key ctrl+Home', 'cmd wsx.center', 'wait 300', 'print-scroll',
                                 'key ctrl+Home', 'cmd wsx.nearest', 'wait 300', 'print-scroll',
                                 'cmd wsx.cio', 'wait 300', 'print-scroll',
                                 'cmd wsx.bad', 'wait 200', 'cmd wsx.word', 'wait 200'], files=('long.txt',))
        y = self.scroll(out)
        self.assertEqual(y[0], 149 * 256, out)
        self.assertIn(' line=1 col=1 ', [l for l in out if l.startswith('tabs=')][0])   # the cursor stays
        shown = 149 - y[1] // 256                     # center: half the view above it
        self.assertTrue(10 <= shown <= 30, y)
        self.assertEqual(y[2] // 256 + (149 - y[2] // 256), 149)
        self.assertTrue(y[2] < 149 * 256 and y[2] > 100 * 256, y)   # nearest: at the bottom
        self.assertEqual(y[3], 0, y)                  # line 5 was outside: centred, clamped at the top
        r = self.replies()
        self.assertEqual(r[:4], ['ok 1', 'ok 2', 'ok 3', 'ok 4'])
        self.assertTrue(r[4].startswith('error 5 badpos'), r)
        self.assertTrue(r[5].startswith('error 6 syntax'), r)

    def test_reveal_needs_the_feature(self):
        exts = self.ext({'top': 'reveal {doc:long.txt} 150 1 top'}, features='')
        self.run_ws(exts, ['cmd wsx.top', 'wait-ext wsx running', 'wait 300'], files=('long.txt',))
        self.assertTrue(self.replies()[0].startswith('error 1 unknown'), self.replies())

    def test_show_locations_lists_them_in_the_palette(self):
        a = str(self.proj / 'a.txt')
        c = str(self.proj / 'c.txt')
        body = 'Implementations\n2\n1 1 1 6 %d 11\n%shello world2 1 2 7 %d 0\n%s' % (len(a), a, len(c), c)
        exts = self.ext({'go': 'show-locations LEN\n' + body}, features='reveal')
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 300', 'print-palette',
                                 'key Down', 'key Return', 'wait 200', 'print-state'], files=('a.txt',))
        self.assertIn('ok 1', self.replies())
        self.assertIn('choose=Implementations', out)
        self.assertTrue(any(l.startswith('> a.txt:1') for l in out), out)
        self.assertTrue(any(l.startswith('  c.txt:2') for l in out), out)
        self.assertIn(' active=c.txt ', [l for l in out if l.startswith('tabs=')][0])

    def test_diff_tab_follows_its_documents_and_closes_with_them(self):
        exts = self.ext({'go': 'diff {doc:a.txt} {doc:c.txt} show LEN\na against c',
                         'again': 'diff {doc:a.txt} {doc:c.txt} background LEN\na against c',
                         'x': 'toast LEN\nhi'},
                        features='diff')
        out = self.run_ws(exts, ['open ' + str(self.proj / 'c.txt'), 'cmd wsx.go', 'wait-ext wsx running',
                                 'wait 300', 'print-tabs', PD, 'key ctrl+Tab', 'key ctrl+Home', 'key End',
                                 'type X', 'wait 300', 'key ctrl+shift+Tab', PD, 'cmd wsx.again', 'wait 300',
                                 'print-tabs', 'key ctrl+shift+Tab', 'cmd close_tab', 'wait 300',
                                 'print-tabs'], files=('a.txt',))
        r = self.replies()
        self.assertTrue(r[0].startswith('ok 1 '), r)
        self.assertEqual(r[1], r[0].replace('ok 1 ', 'ok 2 '))      # the same tab again
        tabs = [l for l in out if l.startswith('tabs=')]
        self.assertEqual(tabs[0], 'tabs=a.txt | c.txt | *a against c', out)
        docs = self.docs(out)
        self.assertIn('@@ -1,2 +1,1 @@ c.txt', docs[0])
        self.assertIn('hello world', docs[0])
        self.assertIn('third file', docs[0])
        self.assertIn('hello worldX', docs[1])                      # followed a.txt's edit
        self.assertEqual(tabs[1], 'tabs=a.txt | c.txt | *a against c', out)
        self.assertNotIn('a against c', tabs[2])                    # closed with c.txt
        log = self.extlines()
        self.assertFalse(any(l.startswith('0 opened') and 'a against c' in l for l in log), log)


for name in dir(ws.Ws):
    if name.startswith('test_'):
        setattr(Reveal, name, None)

if __name__ == '__main__':
    unittest.main()
