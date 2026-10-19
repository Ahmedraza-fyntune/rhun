#!/usr/bin/env python3
"""Log views (feature view-log) and retained views in editor tabs of their own (vtab, unview),
driven headlessly with the viewfake extension: lines with severities and SGR colors, the ring's
limits, following the end, find, line selection and copy, Clear; a tree in a tab that the user
or the extension closes."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from viewsharness import ViewsBase  # noqa: E402

SHOW = ['cmd toggle_side', 'wait 100']          # the logs view is the side column's tab


class Logs(ViewsBase):
    def log_lines(self, out):
        return [l for l in out if l.startswith('line ')]

    def test_lines_keep_their_text_and_severity(self):
        out = self.run_editor([*SHOW, 'cmd viewfake.log', 'wait 300', 'print-log logs', 'print-views'])
        self.assertIn('lines=6 dropped=0 follow=1 cur=-1 anchor=-1 match=-1 find=', out)
        self.assertEqual(self.log_lines(out), [
            'line 0 info starting',
            'line 1 warn yellow and plain',             # SGR kept for drawing, not in the text
            'line 2 error failed: red',
            'line 3 debug details after a tab',         # a tab: spaces to the next stop of 4
            'line 4 trace bell gone',                   # BEL and OSC dropped
            'line 5 - no severity'])
        self.assertTrue(any(l.startswith('view=3 kind=log place=side name=logs rev=1 state=ready') for l in out))

    def test_the_ring_drops_old_lines_and_follows_the_end(self):
        out = self.run_editor([*SHOW, 'cmd viewfake.logmany', 'wait 500', 'wait 300', 'print-log logs'])
        self.assertIn('lines=10000 dropped=2000 follow=1 cur=-1 anchor=-1 match=-1 find=', out)
        lines = self.log_lines(out)
        self.assertEqual(lines[-1], 'line 11999 info line 11999')     # following: the end in view

    def test_find_selects_the_next_line_holding_the_text(self):
        out = self.run_editor([*SHOW, 'cmd viewfake.log', 'wait 300', 'view-focus logs', 'key ctrl+f',
                               'type red', 'key Return', 'print-log logs', 'key Escape', 'key Up',
                               'key shift+Up', 'print-log logs'])
        heads = [l for l in out if l.startswith('lines=')]
        self.assertEqual(heads[0], 'lines=6 dropped=0 follow=1 cur=2 anchor=-1 match=2 find=red')
        self.assertEqual(heads[1], 'lines=6 dropped=0 follow=1 cur=0 anchor=1 match=2 find=')

    def test_copy_takes_the_selected_lines_without_colors(self):
        (self.proj / 'note.txt').write_text('', encoding='utf-8')
        out = self.run_editor([*SHOW, 'cmd viewfake.log', 'wait 300', 'view-focus logs', 'key End',
                               'key Up', 'key Up', 'key Up', 'key Up', 'key shift+Down', 'key ctrl+c',
                               f'open {self.proj / "note.txt"}', 'key ctrl+v', 'wait 100', 'print-doc'])
        self.assertIn('yellow and plain', out)
        self.assertIn('failed: red', out)

    def test_clear_from_the_header_says_so(self):
        out = self.run_editor([*SHOW, 'cmd viewfake.log', 'wait 300', 'print-side-tabs'])
        line = [l for l in out if l.startswith('rhun-tests/viewfake.logs ')][0]
        x0 = int(line.split(' at=')[1].split(',')[0])
        w = int(line.split(' size=')[1].split('x')[0])
        right = x0 + w - 8
        # the strip's buttons, right to left: Find, Clear, Follow, each MI_24 wide
        out = self.run_editor([*SHOW, 'cmd viewfake.log', 'wait 300', f'click {right - 24 - 12} 54', 'wait 100',
                               'print-log logs'])
        self.assertIn('lines=0 dropped=0 follow=1 cur=-1 anchor=-1 match=-1 find=', out)
        self.assertIn('0 view 3 clear', self.fake_log())

    def test_an_extension_without_view_log_shows_it_unsupported(self):
        self.env['VIEWFAKE_NOLOG'] = '1'
        out = self.run_editor([*SHOW, 'print-views'])
        self.assertFalse(any(' kind=log ' in l for l in out))


class Tabs(ViewsBase):
    def test_vtab_opens_a_tree_in_a_tab_and_ctrl_w_closes_it(self):
        out = self.run_editor(['cmd viewfake.tab', 'wait 300', 'wait 200', 'print-tabs', 'print-views',
                               'print-view 4', 'key ctrl+w', 'wait 100', 'print-tabs', 'print-views'])
        self.assertIn('tabs=*Commit 3fa2c1', out)
        self.assertIn('view=4 kind=tree place=tab name=- rev=1 state=ready busy=0 title=Commit 3fa2c1 badge=0 '
                      'visible=1 nodes=3', out)
        rows = self.rows(out)
        self.assertEqual([r.split(' id=')[1].split(' ')[0] for r in rows], ['m', 'm1', 'r'])
        self.assertIn('tabs=', out)
        self.assertEqual(sum(1 for l in out if l.startswith('view=4 ')), 1)
        log = self.fake_log()
        self.assertIn('0 view 4 open tree tab -', log)
        self.assertIn('0 view 4 closed', log)

    def test_unview_closes_the_tab_without_a_closed_event(self):
        out = self.run_editor(['cmd viewfake.tab', 'wait 300', 'cmd viewfake.untab', 'wait 300', 'print-tabs'])
        self.assertIn('tabs=', out)
        log = self.fake_log()
        self.assertNotIn('0 view 4 closed', log)
        self.assertIn('ok 5', ' '.join(log))

    def test_a_tab_takes_the_keyboard_when_clicked(self):
        out = self.run_editor(['cmd viewfake.tab', 'wait 300', 'print-view 4'])
        x, y = self.row_xy(self.rows(out), 'r')
        out = self.run_editor(['cmd viewfake.tab', 'wait 300', f'click {x} {y}', 'key Up', 'key Up',
                               'print-view 4', 'print-state'])
        rows = self.rows(out)
        self.assertIn(' cur ', rows[0])
        self.assertIn('focus=10', [l for l in out if l.startswith('tabs=')][0])


if __name__ == '__main__':
    unittest.main()
