#!/usr/bin/env python3
"""Table views (feature view-table), driven headlessly with the viewfake extension: columns and
cells, a header click sorting (numbers by value, the other way on a second click, per parent, kept
across patches), the owner sorting when rows are paged, the owner's arrow, dividers resizing, a cut
cell's tooltip, and the records rhun refuses."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from viewsharness import ViewsBase  # noqa: E402


class Tables(ViewsBase):
    def setUp(self):
        super().setUp()
        self.env['VIEWFAKE_TABLE'] = '1'

    def shown(self, *actions):
        return self.run_editor(['view-show files', 'wait 300', *actions, 'print-view files'])

    def columns(self, out):
        line = [l for l in out if l.startswith('columns=')][0]
        cols, sorted_ = line[len('columns='):].split(' sorted=')
        parsed = []
        for c in cols.split('|'):
            title, align, width, sort, x, w = c.split(':')
            parsed.append((title, align, int(width), sort, int(x), int(w)))
        return parsed, sorted_

    def rows(self, out):
        return [(l.split(' label=')[1].split(' ')[0], l.split(' cells=')[1] if ' cells=' in l else '')
                for l in out if l.startswith('row ') and ' label=' in l]

    def place(self, out):
        line = [l for l in out if l.startswith('at=')][0]
        x, y = map(int, line[3:].split(' ')[0].split(','))
        rowh = int(line.split(' rowh=')[1].split(' ')[0])
        return x, y, rowh

    def header(self, out, i):
        cols, _ = self.columns(out)
        _, y, rowh = self.place(out)
        _, _, _, _, x, w = cols[i]
        return x + w // 2, y - rowh // 2

    def test_columns_and_cells(self):
        out = self.shown()
        cols, sorted_ = self.columns(out)
        self.assertEqual([c[:4] for c in cols], [('Name', 'left', 0, 'sort'), ('Size', 'right', 6, 'sort'),
                                                 ('Kind', 'left', 8, '-')])
        self.assertEqual(sorted_, '0')
        # laid out side by side; the share column takes what the fixed ones leave
        self.assertEqual(cols[0][4] + cols[0][5], cols[1][4])
        self.assertEqual(cols[1][4] + cols[1][5], cols[2][4])
        self.assertGreater(cols[0][5], cols[1][5])
        rows = self.rows(out)
        self.assertEqual(rows[:3], [('b.txt', '120|file'), ('a.txt', '9|file'), ('dir', '-|folder')])
        self.assertEqual(rows[3:5], [('z.rs', '2|file'), ('y.rs', '10|file')])
        self.assertIn('0 view 4 open table panel files', self.fake_log())

    def test_a_header_click_sorts_numbers_by_value_and_again_the_other_way(self):
        out = self.shown()
        x, y = self.header(out, 1)
        out = self.shown(f'click {x} {y}', 'wait 100')
        self.assertEqual(self.columns(out)[1], '2 asc')
        names = [r[0] for r in self.rows(out)]
        # "-" is not a number: it goes by text, before the digits; children sorted under their parent
        self.assertEqual(names, ['dir', 'z.rs', 'y.rs', 'wide.txt', 'a.txt', 'b.txt'])
        out = self.shown(f'click {x} {y}', 'wait 100', f'click {x} {y}', 'wait 100')
        self.assertEqual(self.columns(out)[1], '2 desc')
        self.assertEqual([r[0] for r in self.rows(out)], ['b.txt', 'a.txt', 'wide.txt', 'dir', 'y.rs', 'z.rs'])
        self.assertFalse([l for l in self.fake_log() if ' sort ' in l])     # nothing paged: rhun sorted

    def test_the_order_stays_across_patches(self):
        out = self.shown()
        x, y = self.header(out, 0)
        out = self.shown(f'click {x} {y}', 'wait 100', 'cmd viewfake.tbadd', 'wait 300')
        self.assertEqual(self.columns(out)[1], '1 asc')
        self.assertEqual([r[0] for r in self.rows(out)], ['a.txt', 'b.txt', 'c.txt', 'dir', 'y.rs', 'z.rs',
                                                          'wide.txt'])

    def test_a_paged_table_asks_its_owner(self):
        out = self.shown()
        x, y = self.header(out, 1)
        out = self.shown('cmd viewfake.tbmore', 'wait 300', f'click {x} {y}', 'wait 200')
        self.assertEqual(self.columns(out)[1], '2 asc owner')
        self.assertEqual([r[0] for r in self.rows(out)][:4], ['b.txt', 'a.txt', 'dir', 'z.rs'])
        sorts = [l for l in self.fake_log() if l.startswith('0 view 4 sort ')]
        self.assertEqual(len(sorts), 1, sorts)
        self.assertTrue(sorts[0].endswith(' 2 asc'), sorts)

    def test_the_owners_arrow(self):
        out = self.shown('cmd viewfake.tbsorted', 'wait 200')
        self.assertEqual(self.columns(out)[1], '2 desc owner')
        self.assertEqual([r[0] for r in self.rows(out)][:3], ['b.txt', 'a.txt', 'dir'])     # its order

    def test_a_divider_drags_the_width(self):
        out = self.shown()
        cols, _ = self.columns(out)
        _, y, rowh = self.place(out)
        edge = cols[0][4] + cols[0][5]
        out = self.shown(f'move {edge} {y - rowh // 2}', 'down', f'move {edge + 40} {y - rowh // 2}', 'up',
                         'wait 50')
        after, _ = self.columns(out)
        self.assertEqual(after[0][5], cols[0][5] + 40)
        self.assertEqual(after[1][4], cols[1][4] + 40)
        self.assertEqual(self.columns(out)[1], '0')     # dragging is not sorting

    def test_a_cut_cell_shows_its_whole_text_as_a_tooltip(self):
        out = self.shown()
        cols, _ = self.columns(out)
        _, y, rowh = self.place(out)
        i = [r[0] for r in self.rows(out)].index('wide.txt')
        x = cols[2][4] + cols[2][5] // 2
        out = self.shown(f'move {x} {y + i * rowh + rowh // 2}', 'wait 700', 'wait 300', 'print-tip')
        self.assertIn('tip=a kind of file whose name is long enough to be cut', out)
        x = cols[1][4] + cols[1][5] // 2        # a cell that fits: the row's own tooltip (none)
        out = self.shown(f'move {x} {y + i * rowh + rowh // 2}', 'wait 700', 'wait 300', 'print-tip')
        self.assertFalse([l for l in out if l.startswith('tip=a kind')])

    def test_bad_columns_and_columns_on_a_tree(self):
        self.run_editor(['view-show files', 'wait 300', 'cmd viewfake.tbbad', 'cmd viewfake.tbtree', 'wait 400'])
        log = self.fake_log()
        errs = [l for l in log if l.startswith('error ')]
        self.assertTrue(any(l.endswith(' syntax op 1') for l in errs), errs)
        self.assertTrue(any(' noview ' in l for l in errs), errs)

    def test_without_the_feature_the_table_is_not_supported(self):
        del self.env['VIEWFAKE_TABLE']
        out = self.run_editor(['view-show files', 'wait 300', 'print-views'])
        self.assertFalse(any(' kind=table ' in l for l in out), out)
        self.assertFalse(any('open table' in l for l in self.fake_log()))

if __name__ == '__main__':
    unittest.main()
