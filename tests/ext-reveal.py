#!/usr/bin/env python3
"""Features reveal and diff (docs/extensions/v1.1.md), driven headlessly with the wsx fake
extension (tests/ext/wsx.py): reveal scrolls a document's view without moving its cursor,
show-locations lists locations in the palette as Find All References does, and diff opens a
read-only diff tab of two open documents that follows them and closes with them. With the
resources group's feature uris (fake extension tests/ext/res.py) a side may be a URI: a virtual
document the diff opens without a tab and lets go of when it closes, or a file: URI of an open
file; reveal takes the URI of an open document."""
import re
import unittest

ws = __import__('wsedit')
PD = ws.PD
vd = __import__('ext-vdoc')


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

A = 'res-gen:/x/a.txt'
B = 'res-gen:/x/b.txt'


class VdocDiff(vd.Vdoc):
    def test_diff_between_virtual_documents(self):
        self.ext('gen', features='uris diff')
        out = self.run_res('gen', [f'diff {A} {B} show {{LEN}}|a against b'], [
            'cmd rt/gen.request', 'wait-ext gen running', 'wait 600', 'print-tabs', 'print-vdocs',
            'print-doc', 'cmd close_tab', 'wait 300', 'print-tabs', 'print-vdocs'],
            features='uris diff')
        tabs = [l for l in out if l.startswith('tabs=')]
        self.assertEqual(tabs[0], 'tabs=a.txt | *a against b', out)         # no tabs for the sides
        v = self.vdocs(out)
        self.assertEqual(sorted(x['uri'] for x in v), [A, B], out)
        self.assertTrue(all(x['state'] == 'loaded' for x in v), out)
        text = '\n'.join(out)
        self.assertIn(f'@@ -1,2 +1,2 @@ b.txt\ncontent 1 of {A}\ncontent 1 of {B}\nsecond line\n', text)
        self.assertEqual(tabs[1], 'tabs=*a.txt', out)
        self.assertEqual(len(self.vdocs(out)), 2, out)                       # gone with the tab
        log = self.reslog('gen')
        self.assertTrue(any(re.fullmatch(r'ok 1 \d+', x) for x in log), log)
        self.assertIn(f'0 content-closed {A}', log)
        self.assertIn(f'0 content-closed {B}', log)
        self.assertFalse(any(x.startswith('0 opened') and 'res-gen' in x for x in log), log)

    def test_a_side_opened_meanwhile_stays_and_file_uris(self):
        self.ext('gen', features='uris diff')
        path = (self.proj / 'a.txt').as_posix()
        lines = [f'diff {A} file://{path} background {{LEN}}|gen against a', f'open 2 1 {A}',
                 f'diff {A} file:///nowhere/x.txt show {{LEN}}|nothing', f'diff 1x {A} show {{LEN}}|bad']
        out = self.run_res('gen', lines, [
            'cmd rt/gen.batch', 'wait-ext gen running', 'wait 600', 'print-tabs', 'key ctrl+Tab',
            'print-doc', 'cmd close_tab', 'wait 300', 'print-tabs', 'print-vdocs'], features='uris diff')
        tabs = [l for l in out if l.startswith('tabs=')]
        self.assertEqual(tabs[0], 'tabs=a.txt | *a.txt | gen against a', out)  # the URI's tab opened
        self.assertIn(f'content 1 of {A}\nhello world', '\n'.join(out))
        self.assertEqual(tabs[1], 'tabs=a.txt | *a.txt', out)
        self.assertEqual([x['uri'] for x in self.vdocs(out)][-1:], [A], out)   # still open
        log = self.reslog('gen')
        replies = [x for x in log if x.startswith(('ok ', 'error '))]
        self.assertTrue(re.fullmatch(r'ok 1 \d+', replies[0]), replies)
        self.assertTrue(re.fullmatch(r'ok 2 \d+', replies[1]), replies)
        self.assertEqual(replies[2], 'error 3 nodoc no such document')
        self.assertTrue(replies[3].startswith('error 4 syntax'), replies)
        self.assertNotIn(f'0 content-closed {A}', log)

    def test_the_provider_removed_closes_the_diff(self):
        self.ext('gen', features='uris')
        self.ext('dif', schemes='')
        self.env['RES_FEATURES_gen'] = 'uris'
        out = self.run_res('dif', [f'diff {A} {B} show {{LEN}}|a against b'], [
            'cmd rt/dif.request', 'wait-ext dif running', 'wait 1500', 'print-tabs', 'print-vdocs',
            'ext-remove gen', 'dialog yes', 'wait 500', 'print-tabs', 'print-vdocs'],
            features='uris diff')
        tabs = [l for l in out if l.startswith('tabs=')]
        self.assertEqual(tabs[0], 'tabs=a.txt | *a against b', out)
        self.assertEqual(tabs[1], 'tabs=*a.txt', out)
        vdocs = [l for l in out if l.startswith('vdoc ')]
        self.assertEqual(len(vdocs), 2, out)                                 # none after

    def test_reveal_a_uri(self):
        self.ext('gen', features='uris reveal')
        path = (self.proj / 'a.txt').as_posix()
        lines = [f'open 1 1 {A}', f'reveal {A} 2 1 top', f'reveal file://{path} 1 1 center',
                 f'reveal {B} 1 1 top']
        self.run_res('gen', lines, ['cmd rt/gen.request', 'wait-ext gen running', 'wait 600',
                                    'cmd rt/gen.batch', 'wait 300'], features='uris reveal')
        replies = [x for x in self.reslog('gen') if x.startswith(('ok ', 'error '))]
        self.assertTrue(re.fullmatch(r'ok 1 \d+', replies[0]), replies)
        self.assertEqual(replies[1:], ['ok 2', 'ok 3', 'error 4 nodoc no such document'])


for name in dir(vd.Vdoc):
    if name.startswith('test_'):
        setattr(VdocDiff, name, None)

if __name__ == '__main__':
    unittest.main()
