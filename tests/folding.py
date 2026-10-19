#!/usr/bin/env python3
"""Folding (editor presentation stage 5): indentation ranges, the fold commands and keys, the fold
lane and the pill, caret motion over folds, folds that open when the caret lands inside, edits that
remove folds, line commands on folded headers, sessions and closed tabs, vim, and the view that
scrolls by rows."""
from pathlib import Path
import unittest

pres = __import__('presentation')
host = pres.host

NESTED = '''fn a() {
    if x {
        one();
        two();
    }

    three();
}

fn b() {
    four();
}
'''


class Folding(pres.Base):
    def setUp(self):
        super().setUp()
        (self.proj / 'n.rs').write_text(NESTED, encoding='utf-8')

    def run_f(self, actions, files=('n.rs',), **kw):
        return self.run_p(actions, files=files, **kw)

    def folds(self, out):
        return [l for l in out if l.startswith('fold ')]

    def state(self, out, i=0):
        return [l for l in out if l.startswith('tabs=')][i]

    def test_fold_and_unfold_by_indentation(self):
        out = self.run_f(['key ctrl+Home', 'cmd fold', 'print-present folds', 'print-viewport',
                          'key Down', 'key Down', 'cmd fold', 'print-present folds',
                          'cmd unfold', 'print-present folds'])
        # "fn a() {" folds through "three();" (the closing brace stays); the blank line inside counts
        self.assertEqual(self.folds(out)[0], 'fold 1-7')
        self.assertIn('hidden 6', out)
        self.assertTrue(any(l.startswith('view mode=rows top=1 ') for l in out), out)
        # Down twice from line 1: line 8 ("}"), then 9 (blank): nothing to fold or open there
        self.assertEqual(self.folds(out)[1:], ['fold 1-7', 'fold 1-7'])

    def test_innermost_range_holding_the_caret(self):
        out = self.run_f(['key ctrl+Home', 'key Down', 'key Down', 'cmd fold', 'print-present folds',
                          'print-state', 'cmd fold', 'print-present folds'])
        f = self.folds(out)
        self.assertEqual(f[0], 'fold 2-4')          # "if x {" holds line 3
        self.assertIn('line=2 col=', self.state(out))
        self.assertEqual(f[1:], ['fold 1-7', 'fold 2-4'])

    def test_fold_all_levels_and_unfold_all(self):
        out = self.run_f(['cmd fold_all', 'print-present folds', 'cmd unfold_all', 'print-present folds',
                          'cmd fold_level_2', 'print-present folds'])
        self.assertEqual(self.folds(out)[:3], ['fold 1-7', 'fold 2-4', 'fold 10-11'])
        self.assertEqual(self.folds(out)[3:], ['fold 2-4'])

    def test_caret_steps_over_folds(self):
        out = self.run_f(['key ctrl+Home', 'cmd fold', 'key Down', 'print-state', 'key Up', 'print-state',
                          'key End', 'key Right', 'print-state', 'key Left', 'print-state',
                          'print-present folds'])
        self.assertIn('line=8 col=1 ', self.state(out, 0))
        self.assertIn('line=1 col=1 ', self.state(out, 1))
        self.assertIn('line=8 col=1 ', self.state(out, 2))
        self.assertIn('line=1 col=9 ', self.state(out, 3))
        self.assertEqual(self.folds(out), ['fold 1-7'])

    def test_caret_landing_inside_opens_the_fold(self):
        out = self.run_f(['key ctrl+Home', 'cmd fold', 'cmd goto_line', 'type 4', 'key Return',
                          'print-state', 'print-present folds'])
        self.assertIn('line=4 ', self.state(out))
        self.assertEqual(self.folds(out), [])

    def test_edits_keep_or_remove_folds(self):
        out = self.run_f(['key ctrl+Home', 'cmd fold', 'key End', 'type  ', 'print-present folds',
                          'key ctrl+Home', 'key Return', 'print-present folds',
                          'key End', 'key Delete', 'print-present folds'])
        f = self.folds(out)
        self.assertEqual(f[0], 'fold 1-7')          # typed at the header's end
        self.assertEqual(f[1], 'fold 2-8')          # a line above: it moves down
        self.assertEqual(f[2:], [])                 # the header's line feed deleted

    def test_line_commands_take_the_hidden_lines(self):
        out = self.run_f(['key ctrl+Home', 'cmd fold', 'cmd duplicate_line', 'print-doc'])
        doc = '\n'.join(out)
        self.assertEqual(doc.count('three();'), 2)
        out = self.run_f(['key ctrl+Home', 'cmd fold', 'cmd delete_line', 'print-doc'])
        doc = '\n'.join(out)
        self.assertNotIn('three();', doc)
        self.assertIn('four();', doc)

    def test_lane_chevrons_and_pill(self):
        out = self.run_f(['print-xy 1 1'] + [f'print-hit {x} 86' for x in range(0, 60, 2)])
        lane = [int(l.split()[1]) for l in out if l.startswith('fold-lane ')]
        xs = [x for x, l in zip(range(0, 60, 2), out[1:]) if l.startswith('fold-lane ')]
        self.assertTrue(xs, out)
        y = int(out[0].split()[1])
        out = self.run_f([f'click {xs[0] + 2} {y}', 'print-present folds', 'print-xy 1 9'])
        self.assertEqual(self.folds(out), ['fold 1-7'])
        x9, _ = map(int, out[-1].split())
        # the pill after "fn a() {" unfolds
        out = self.run_f([f'click {xs[0] + 2} {y}', f'print-hit {x9 + 12} {y}', f'click {x9 + 12} {y}',
                          'print-present folds'])
        self.assertIn('inlay fold 1 9', out)
        self.assertEqual(self.folds(out), [])
        path = self.work / 'lane.ppm'
        self.run_f(['cmd fold_all', f'move 4 {y}', f'shot {path}'])
        self.assertTrue(path.exists())

    def test_folds_survive_sessions_and_closed_tabs(self):
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text().replace('restore_session = false', 'restore_session = true'))
        self.run_f(['key ctrl+Home', 'cmd fold', 'key ctrl+End', 'cmd fold_level_1'])
        out = self.run_p(['wait 200', 'print-present folds'], files=())
        self.assertEqual(self.folds(out), ['fold 1-7', 'fold 10-11'])
        out = self.run_f(['cmd close_tab', 'cmd reopen_closed_tab', 'print-present folds'])
        self.assertEqual(self.folds(out), ['fold 1-7', 'fold 10-11'])

    def test_vim_fold_commands(self):
        out = self.run_f(['cmd toggle_vim', 'key ctrl+Home', 'type zc', 'print-present folds', 'type j',
                          'print-state', 'type k', 'type zo', 'print-present folds', 'type zM',
                          'print-present folds', 'type zR', 'print-present folds', 'type za',
                          'print-present folds', 'cmd toggle_vim'])
        f = self.folds(out)
        self.assertEqual(f[0], 'fold 1-7')
        self.assertIn('line=8 ', self.state(out))
        self.assertEqual(f[1:4], ['fold 1-7', 'fold 2-4', 'fold 10-11'])
        self.assertEqual(f[4:], ['fold 1-7'])

    def test_folding_off(self):
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[editor]\nfolding = false\n')
        out = self.run_f(['key ctrl+Home', 'cmd fold', 'print-present folds'] +
                         [f'print-hit {x} 86' for x in range(0, 60, 2)])
        self.assertEqual(self.folds(out), [])
        self.assertFalse(any(l.startswith('fold-lane') for l in out))

    def test_scroll_by_rows_over_folds(self):
        (self.proj / 'big.rs').write_text(''.join(
            f'fn f{i}() {{\n' + ''.join(f'    x{j}();\n' for j in range(20)) + '}\n' for i in range(50)),
            encoding='utf-8')
        out = self.run_p(['print-viewport', 'cmd fold_all', 'print-viewport', 'move 500 300', 'scroll 105',
                          'print-viewport', 'print-scroll'], files=('big.rs',))
        views = [l for l in out if l.startswith('view ')]
        before = int(views[0].split('content=')[1])
        after = int(views[1].split('content=')[1])
        self.assertLess(after, before // 5)          # 50 folds of 20 lines: 101 rows left of 1101
        top = int(views[2].split('top=')[1].split()[0])
        self.assertIn((top - 1) % 22, (0, 21))       # a header or a closing brace: no folded line
        self.assertGreater(top, 22)


if __name__ == '__main__':
    unittest.main()
