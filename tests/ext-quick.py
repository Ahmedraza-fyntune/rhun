#!/usr/bin/env python3
"""Quick input (feature quick-input), driven headlessly with the viewfake extension: a pick with
separators, the title row, filtering and value events, the active item, accept and the next step,
an error message blocking Enter, multi-select, Back, title and item buttons, Escape and clicks
outside, quick-close, busy, and the bodies rhun refuses."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from viewsharness import ViewsBase  # noqa: E402


class Quick(ViewsBase):
    def setUp(self):
        super().setUp()
        self.env['VIEWFAKE_QUICK'] = '1'

    def quick(self, *actions, cmd='quick'):
        return self.run_editor([f'cmd viewfake.{cmd}', 'wait 300', *actions, 'wait 100', 'print-quick'])

    def head(self, out):
        return [l for l in out if l.startswith('quick ')][-1]

    def rows(self, out):
        return [l for l in out if l.startswith('row ')]

    def label(self, row):
        return row.split(' label=')[1].split(' ')[0]

    def events(self, what):
        log = self.fake_log()
        return [(l, log[i + 1] if i + 1 < len(log) else None) for i, l in enumerate(log)
                if l.startswith('0 quick ') and l.split(' ')[3] == what]

    def test_a_pick_with_separators_and_a_title_row(self):
        out = self.quick()
        head = self.head(out)
        self.assertIn(' title=Branch step=1/3 mode=pick ', head)
        self.assertIn(' focus=1 ', head)
        rows = self.rows(out)
        self.assertEqual([self.label(r) for r in rows], ['Local', 'main', 'dev', 'Remote', 'origin/main'])
        self.assertIn(' sep', rows[0])
        self.assertIn(' active', rows[1])
        self.assertTrue(any(l.startswith('button refresh at=') for l in out))
        self.assertTrue(any(l.startswith('back at=') for l in out))
        self.assertTrue([l for l in self.fake_log() if l.startswith('ok ')])

    def test_typing_filters_and_sends_the_value_once_a_frame(self):
        out = self.quick('type ori', 'wait 100')
        self.assertEqual([self.label(r) for r in self.rows(out)], ['Remote', 'origin/main'])
        self.assertIn(' active', self.rows(out)[1])
        self.assertIn(' seq=3 ', self.head(out))
        values = self.events('value')
        self.assertTrue(values)
        self.assertEqual(values[-1][0].split(' ')[4], '3')
        self.assertEqual(values[-1][1], 'ori')
        active = self.events('active')
        self.assertEqual(active[-1][1], 'origin/main')

    def test_arrows_move_the_active_item_and_enter_accepts_into_the_next_step(self):
        out = self.quick('key Down', 'wait 100', 'key Down', 'wait 100', 'key Return', 'wait 300')
        accepts = self.events('accept')
        self.assertEqual(len(accepts), 1)
        self.assertTrue(accepts[0][0].endswith(' accept 0 1 12'), accepts)   # "origin/main\n" + ""
        self.assertEqual(accepts[0][1], 'origin/main')
        head = self.head(out)
        self.assertIn(' title=Step two step=2/3 ', head)
        self.assertIn(' waiting=0 ', head)
        self.assertTrue(head.endswith(' field='))
        self.assertEqual([self.label(r) for r in self.rows(out)], ['Create', 'Create'])

    def test_an_error_for_the_text_blocks_enter_until_it_changes(self):
        out = self.quick('type bad', 'wait 100', 'key Return', 'wait 300', 'print-quick', 'key Return', 'wait 300')
        self.assertIn(' msg=error:not a branch', self.head(out))
        self.assertEqual(len(self.events('accept')), 1)
        before = len(self.events('accept'))
        out = self.quick('type bad', 'wait 100', 'key Return', 'wait 300', 'key BackSpace', 'type x', 'wait 100',
                         'key Return', 'wait 300')
        self.assertEqual(len(self.events('accept')) - before, 2)        # "bad", then "bax"
        self.assertNotIn(' msg=', self.head(out).split(' at=')[0])
        self.assertIn(' title=Step two ', self.head(out))

    def test_multi_select(self):
        out = self.quick('key Down', 'key space', 'wait 100', 'print-quick', 'key Return', 'wait 300',
                         cmd='quickmulti')
        rows = self.rows(out)
        self.assertIn(' checked', rows[0])
        self.assertIn(' checked', rows[1])
        self.assertNotIn(' checked', rows[2])
        accept = self.events('accept')[-1]
        self.assertTrue(accept[0].split(' ')[5] == '2', accept)
        log = self.fake_log()
        i = log.index(accept[0])
        self.assertEqual(log[i + 1:i + 3], ['a', 'b'])

    def test_escape_hides_and_gives_the_keyboard_back(self):
        out = self.quick('key Escape', 'wait 100')
        self.assertIn('quick none', out)
        self.assertEqual(len(self.events('hide')), 1)

    def test_a_click_outside_hides(self):
        out = self.quick('click 10 590', 'wait 100')
        self.assertIn('quick none', out)
        self.assertEqual(len(self.events('hide')), 1)

    def test_back_title_buttons_and_item_buttons(self):
        out = self.quick()
        bx, by = map(int, [l for l in out if l.startswith('button refresh at=')][0].split('at=')[1].split(','))
        kx, ky = map(int, [l for l in out if l.startswith('back at=')][0].split('at=')[1].split(','))
        head = self.head(out)
        x, y = map(int, head.split(' at=')[1].split(' ')[0].split(','))
        w = int(head.split(' size=')[1].split('x')[0])
        row = self.rows(out)[1]
        rx, ry = map(int, row.split(' at=')[1].split(','))
        self.quick('key alt+Left', 'wait 100', f'click {bx + 10} {by + 12}', 'wait 100',
                   f'move {x + w - 30} {ry + 10}', 'wait 50', f'click {x + w - 30} {ry + 10}', 'wait 100',
                   f'click {kx + 10} {ky + 14}', 'wait 100')
        backs = self.events('back')
        self.assertEqual(len(backs), 2, backs)
        buttons = self.events('button')
        self.assertTrue(buttons[0][0].endswith(' button 0 refresh 0'), buttons)
        self.assertTrue(buttons[1][0].endswith(' button 0 del 4'), buttons)
        self.assertEqual(buttons[1][1], 'main')
        self.assertFalse(self.events('accept'))         # a button is not the row's click

    def test_the_extension_sets_the_active_item(self):
        out = self.quick('cmd viewfake.quickactive', 'wait 300')
        self.assertIn(' active', [r for r in self.rows(out) if self.label(r) == 'origin/main'][0])
        self.assertFalse([e for e in self.events('active') if e[1] == 'origin/main'])

    def test_quick_close_and_busy(self):
        out = self.quick('cmd viewfake.quick', 'wait 300', 'cmd viewfake.quickclose', 'wait 300')
        self.assertIn('quick none', out)
        self.assertFalse(self.events('hide'))
        self.assertTrue(any(l.startswith('error ') and l.endswith('busy a prompt is open') for l in self.fake_log()))

    def test_input_mode_password_and_busy(self):
        out = self.quick(cmd='quickinput')
        head = self.head(out)
        self.assertIn(' mode=input ', head)
        self.assertIn(' prompt=Your token', head)
        self.assertTrue(head.endswith(' field=abc'))
        self.assertFalse(self.rows(out))

    def test_nofilter_keeps_every_item(self):
        out = self.quick('type zzz', 'wait 100', cmd='quicknofilter')
        self.assertEqual([self.label(r) for r in self.rows(out)], ['symbol', 'other'])

    def test_bodies_rhun_refuses(self):
        self.run_editor(['cmd viewfake.quickbad', 'cmd viewfake.quickbig', 'wait 600', 'print-quick'])
        log = self.fake_log()
        errs = [l for l in log if l.startswith('error ')]
        self.assertTrue(any(' syntax ' in l for l in errs), errs)
        self.assertTrue(any(' toobig ' in l for l in errs), errs)

    def test_without_the_feature_it_is_unknown(self):
        del self.env['VIEWFAKE_QUICK']
        out = self.quick()
        self.assertIn('quick none', out)
        self.assertTrue(any(l.startswith('error ') and ' unknown' in l for l in self.fake_log()))


if __name__ == '__main__':
    unittest.main()
