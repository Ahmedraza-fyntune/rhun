#!/usr/bin/env python3
"""Form views (feature view-form), driven headlessly with the viewfake extension: rows of fields by
weight, typing and the user's sequence, Tab between fields, number stepping, a check, a select's
options, a button, submit, messages, the ownership rule for values, records rhun refuses."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from viewsharness import ViewsBase  # noqa: E402

FORM = 4                # the form view's number: todo 1, items 2, logs 3


class Forms(ViewsBase):
    def setUp(self):
        super().setUp()
        self.env['VIEWFAKE_FORM'] = '1'

    def fields(self, out):
        return {l.split(' ')[1]: l for l in out if l.startswith('field ')}

    def xy(self, line):
        x, y = map(int, line.split(' at=')[1].split(' ')[0].split(','))
        w, h = map(int, line.split(' size=')[1].split(' ')[0].split('x'))
        return x + w // 2, y + h // 2

    def shown(self, *actions):
        return self.run_editor(['view-show setup', 'wait 300', *actions, 'print-form setup'])

    def test_fields_take_their_rows_by_weight(self):
        f = self.fields(self.shown())
        self.assertEqual(list(f), ['name', 'port', 'notes', 'tls', 'mode', 'go'])
        self.assertTrue(f['name'].endswith(' value=Ada'))
        self.assertTrue(f['port'].endswith(' value=8080'))
        self.assertIn(' on=1 ', f['tls'])
        self.assertTrue(f['mode'].endswith(' value=safe'))
        nx, ny = map(int, f['name'].split(' at=')[1].split(' ')[0].split(','))
        px, py = map(int, f['port'].split(' at=')[1].split(' ')[0].split(','))
        nw = int(f['name'].split(' size=')[1].split('x')[0])
        pw = int(f['port'].split(' size=')[1].split('x')[0])
        self.assertEqual(ny, py)                    # one row
        self.assertGreater(px, nx)
        self.assertAlmostEqual(nw, 2 * pw, delta=4) # weights 2 and 1
        self.assertIn('0 view 4 open form panel setup', self.fake_log())

    def test_typing_counts_the_users_edits(self):
        f = self.fields(self.shown())
        x, y = self.xy(f['name'])
        out = self.shown(f'click {x} {y}', 'key End', 'type yz', 'key Return')
        f = self.fields(out)
        self.assertTrue(f['name'].endswith(' value=Adayz'), f['name'])
        self.assertIn(' seq=2 ', f['name'])
        self.assertIn(' focus ', f['name'] + ' ')
        log = self.fake_log()
        i = log.index(f'0 view {FORM} change 1 name 2 5')
        self.assertEqual(log[i + 1], 'Adayz')
        self.assertIn(f'0 view {FORM} submit 1 name', log)

    def test_tab_steps_and_a_number_steps_within_its_range(self):
        f = self.fields(self.shown())
        x, y = self.xy(f['name'])
        f = self.fields(self.shown(f'click {x} {y}', 'key Tab', 'key Up', 'key Up', 'key Down'))
        self.assertTrue(f['port'].endswith(' value=8081'), f['port'])
        self.assertIn(' focus', f['port'])

    def test_a_check_a_select_and_a_button(self):
        f = self.fields(self.shown())
        x, y = self.xy(f['tls'])
        mx, my = self.xy(f['mode'])
        out = self.shown(f'click {x} {y}', f'click {mx} {my}', 'wait 50', 'menu-pick slow', 'wait 50',
                         'key Tab', 'key Return')
        f = self.fields(out)
        self.assertIn(' on=0 ', f['tls'])
        self.assertTrue(f['mode'].endswith(' value=slow'), f['mode'])
        self.assertIn(' focus ', f['go'])           # Tab from the select
        log = self.fake_log()
        i = log.index(f'0 view {FORM} change 1 tls 1 2')
        self.assertEqual(log[i + 1], 'no')
        self.assertIn(f'0 view {FORM} change 1 mode 1 4', log)
        self.assertIn(f'0 view {FORM} press 1 go', log)

    def test_the_wheel_scrolls_a_form_to_a_button_a_click_presses(self):
        scroll = ['move 600 450', 'scroll 400', 'wait 50']
        f = self.fields(self.shown(*scroll))
        gx, gy = self.xy(f['go'])
        self.assertLess(gy, 574)                    # in view now
        self.shown(*scroll, f'click {gx} {gy}')
        self.assertIn(f'0 view {FORM} press 1 go', self.fake_log())

    def test_a_value_applies_only_for_the_last_edit_it_saw(self):
        f = self.fields(self.shown())
        x, y = self.xy(f['name'])
        out = self.shown(f'click {x} {y}', 'key End', 'type q', 'wait 100', 'cmd viewfake.formold', 'wait 200',
                         'print-form setup', 'cmd viewfake.formnew', 'wait 200')
        firsts = [l for l in out if l.startswith('field name ')]
        self.assertTrue(firsts[0].endswith(' value=Adaq'), firsts[0])        # an old sequence: kept
        self.assertTrue(firsts[1].endswith(' value=NORMAL'), firsts[1])      # the last: applied

    def test_messages_and_a_form_that_drops_fields(self):
        f = self.fields(self.shown('cmd viewfake.formmsg', 'wait 200'))
        self.assertIn(' msg=error:taken ', f['name'])
        f = self.fields(self.shown('cmd viewfake.formless', 'wait 200'))
        self.assertEqual(list(f), ['go'])

    def test_a_bad_record_changes_nothing(self):
        self.shown('cmd viewfake.formbad', 'wait 200')
        self.assertTrue(any(l.startswith('error ') and ' syntax' in l for l in self.fake_log()))

    def test_paste_goes_into_the_field(self):
        (self.proj / 'note.txt').write_text('pasted', encoding='utf-8')
        f = self.fields(self.shown())
        x, y = self.xy(f['name'])
        out = self.shown(f'open {self.proj / "note.txt"}', 'key ctrl+a', 'key ctrl+c', 'view-show setup',
                         f'click {x} {y}', 'key End', 'key ctrl+v', 'wait 200')
        f = self.fields(out)
        self.assertTrue(f['name'].endswith(' value=Adapasted'), f['name'])


if __name__ == '__main__':
    unittest.main()
