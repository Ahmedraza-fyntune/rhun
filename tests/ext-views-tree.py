#!/usr/bin/env python3
"""Places and retained tree views (docs/extensions/v1.1.md "Retained views"), driven headlessly with
the viewfake extension (tests/ext/viewfake.py, tests/ext/views): declared views take the sidebar,
panel and side places, showing one starts its extension, patches apply whole or not at all, user
state follows node ids, and the events say what the user did. The built-in demo (places-demo)
drives the same places and tree widget through the API built-in code uses."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
EXTS = ROOT / 'tests/ext/views'

CONFIG = ('[ui]\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')


class Views(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-views-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        (self.proj / 'src').mkdir(parents=True)
        (self.proj / 'src/main.rs').write_text('fn main() {\n    // TODO: parse\n}\n', encoding='utf-8')
        (self.proj / 'src/lib.rs').write_text('// TODO: lib\n', encoding='utf-8')
        (self.proj / 'README.md').write_text('# TODO\n', encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.log = self.work / 'state/rhun/extensions/rhun-tests--viewfake/vf.log'
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(),
                        VIEWFAKE_LOG=self.log.as_posix(), VIEWFAKE_ROOT=self.proj.as_posix())
        self.env.pop('VIEWFAKE_MODE', None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions, mode=None, exts=EXTS, start=True):
        env = dict(self.env)
        if mode:
            env['VIEWFAKE_MODE'] = mode
        pre = ['wait 100', 'wait-ext viewfake running', 'wait 200', 'wait 100'] if start else ['wait 100']
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join([*pre, *actions, 'quit']) + '\n', encoding='utf-8')
        args = [str(EXE), self.proj.as_posix(), '--headless', '1000x600', '--scale', '1']
        if exts:
            args += ['--extensions', str(exts)]
        result = subprocess.run(args + ['--script', script.as_posix()], env=env, capture_output=True,
                                timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return [l for l in result.stdout.decode('utf-8', errors='replace').splitlines()
                if not l.startswith('ext=')]

    def fake_log(self):
        return self.log.read_bytes().decode('utf-8', 'replace').splitlines() if self.log.exists() else []

    def rows(self, out, view='todo'):
        """The row lines of a print-view in out (after its at= line)."""
        rows, on = [], False
        for line in out:
            if line.startswith('at='):
                on = True
                self.view_x = int(line[3:].split(',')[0])
                continue
            if on and line.startswith('row '):
                rows.append(line)
            elif on:
                break
        return rows

    def row_xy(self, rows, ident):
        for r in rows:
            if f' id={ident} ' in r + ' ':
                y = int(r.split(' y=')[1].split(' ')[0])
                return getattr(self, 'view_x', 0) + 120, y + 10
        self.fail(f'no row {ident} in {rows}')

    # --- places ---

    def test_the_explorer_alone_fills_the_sidebar(self):
        out = self.run_editor(['print-sidebar', 'print-panel-tabs', 'print-side-tabs'], exts=None, start=False)
        self.assertEqual(out[0], 'explorer title=Explorer at=0,40 size=240x534 badge=0 visible')
        self.assertEqual(out[1], 'terminals=0 chosen open=0')
        self.assertEqual(len(out), 2)

    def test_declared_views_take_their_places(self):
        out = self.run_editor(['print-sidebar', 'print-panel-tabs', 'print-side-tabs'])
        self.assertIn('rhun-tests/viewfake.todo title=TODO at=0,335 size=240x239 badge=4 visible', out)
        self.assertIn('rhun-tests/viewfake.items title=Items at=0,0 size=0x0 badge=0', out)
        self.assertIn('rhun-tests/viewfake.logs title=Logs at=0,0 size=0x0 badge=0', out)
        joined = '\n'.join(out)
        for bad in ('notitle', 'badplace', 'badkind'):
            self.assertNotIn(bad, joined)

    def test_showing_a_view_starts_its_extension_and_it_fills_it(self):
        out = self.run_editor(['print-views', 'print-view todo'])
        self.assertIn('view=1 kind=tree place=sidebar name=todo rev=1 state=ready busy=0 title=TODO badge=4 '
                      'visible=1 nodes=7', out)
        self.assertIn('view=2 kind=tree place=panel name=items rev=1 state=ready busy=0 title=Items badge=0 '
                      'visible=0 nodes=3', out)
        rows = self.rows(out)
        self.assertEqual(len(rows), 7)
        self.assertEqual(rows[0], 'row 0 y=335 d=0 open id=f:main.rs label=main.rs desc=src badge=2 icon=116')
        self.assertTrue(rows[1].startswith('row 1 y=363 d=1 leaf id=t:main.rs:1 label=TODO: item 1 of main.rs (2)'))
        self.assertTrue(rows[1].endswith('hl=0-4'))
        log = self.fake_log()
        self.assertEqual(log[:2], ['0 features view-tree', log[1]])
        i = log.index('0 view 1 open tree sidebar todo')
        self.assertEqual(log[i + 1], '0 view 1 visible 1')
        self.assertEqual(log[i + 2], '0 view 2 open tree panel items')
        self.assertEqual(log[i + 3], '0 view 2 visible 0')

    def test_a_click_on_a_leaf_with_an_open_record_opens_the_file(self):
        out = self.run_editor(['print-view todo'])
        x, y = self.row_xy(self.rows(out), 't:main.rs:2')
        out = self.run_editor([f'click {x} {y}', 'wait 50', 'print-state', 'print-view todo'])
        state = [l for l in out if l.startswith('tabs=')][0]
        self.assertIn('tabs=1', state)
        self.assertIn('line=2', state)
        self.assertIn('focus=0', state)          # the editor has the keyboard after an open
        rows = self.rows(out)
        self.assertIn(' cur ', [r for r in rows if 'id=t:main.rs:2 ' in r][0])
        log = self.fake_log()
        self.assertIn('0 view 1 select 1 1 12', log)
        self.assertIn('t:main.rs:2', log)
        self.assertFalse(any(' activate ' in l for l in log))     # rhun opened it itself

    def test_expansion_is_kept_across_a_patch_of_the_same_ids(self):
        out = self.run_editor(['print-view todo'])
        x, y = self.row_xy(self.rows(out), 'f:main.rs')
        out = self.run_editor([f'click {x} {y}', 'cmd viewfake.rescan', 'wait 200', 'print-view todo', 'print-views'])
        rows = self.rows(out)
        self.assertTrue(rows[0].startswith('row 0 y=335 d=0 closed cur id=f:main.rs'), rows)
        self.assertEqual(len(rows), 5)          # main.rs's two TODOs stay hidden
        self.assertTrue(rows[2].startswith('row 2 y=391 d=1 leaf id=t:lib.rs:1 label=TODO: item 1 of lib.rs (3)'))
        self.assertTrue(any(l.startswith('view=1 ') and ' rev=2 ' in l for l in out))
        log = self.fake_log()
        i = log.index('0 view 1 collapse 1 9')
        self.assertEqual(log[i + 1], 'f:main.rs')

    def test_new_ids_are_new_nodes(self):
        out = self.run_editor(['cmd viewfake.renamed', 'wait 200', 'print-view todo'])
        rows = self.rows(out)
        self.assertEqual(len(rows), 7)
        self.assertTrue(all(' id=n' in r for r in rows), rows)

    def test_a_bad_patch_changes_nothing(self):
        out = self.run_editor(['cmd viewfake.badpatch', 'wait 200', 'print-views', 'print-view todo', 'print-sidebar'])
        self.assertIn('view=1 kind=tree place=sidebar name=todo rev=1 state=ready busy=0 title=TODO badge=4 '
                      'visible=1 nodes=7', out)
        self.assertEqual(len(self.rows(out)), 7)
        self.assertIn('rhun-tests/viewfake.todo title=TODO at=0,335 size=240x239 badge=4 visible', out)
        self.assertIn('error 3 badpos kids missing-parent', self.fake_log())

    def test_too_many_nodes_is_refused_whole(self):
        out = self.run_editor(['cmd viewfake.big', 'wait 500', 'print-views'])
        self.assertTrue(any(l.startswith('view=1 ') and ' nodes=7' in l and ' rev=1 ' in l for l in out), out)
        self.assertIn('error 3 toobig nodes', self.fake_log())

    def test_a_removed_selected_node_moves_the_selection(self):
        out = self.run_editor(['print-view todo'])
        x, y = self.row_xy(self.rows(out), 'f:lib.rs')
        out = self.run_editor([f'click {x} {y}', 'wait 50', 'cmd viewfake.vanish', 'wait 200', 'print-view todo'])
        rows = self.rows(out)
        self.assertFalse(any('id=f:lib.rs ' in r for r in rows))
        self.assertIn(' cur ', [r for r in rows if 'id=f:README.md ' in r][0])
        log = self.fake_log()
        i = len(log) - 1 - log[::-1].index('0 view 1 select 2 1 12')
        self.assertEqual(log[i + 1], 'f:README.md')

    def test_keys_move_expand_and_open(self):
        out = self.run_editor(['view-focus todo', 'key Down', 'key Down', 'print-view todo', 'key Left',
                               'print-view todo', 'key Down', 'key Return', 'wait 50', 'print-state'])
        first = self.rows(out[:out.index(next(l for l in out if l.startswith('at='))) + 9])
        self.assertIn(' cur ', first[1])        # Down from no cursor lands on row 0, then row 1
        state = [l for l in out if l.startswith('tabs=')][0]
        self.assertIn('tabs=1', state)
        log = self.fake_log()
        self.assertIn('0 view 1 focus 1', log)

    def test_vshow_opens_the_panel_on_its_tab_with_the_keyboard(self):
        out = self.run_editor(['cmd viewfake.show', 'wait 200', 'print-panel-tabs', 'print-view items'])
        self.assertIn('terminals=0 open=1', out)
        self.assertTrue(any(l.startswith('rhun-tests/viewfake.items ') and l.endswith(' visible chosen focus')
                            for l in out), out)
        self.assertEqual(len(self.rows(out)), 9)    # with three pages of more
        log = self.fake_log()
        self.assertIn('ok 3 2', log)
        self.assertIn('0 view 2 visible 1', log)
        self.assertIn('0 view 2 focus 1', log)

    def test_toggle_panel_starts_no_shell_for_a_view_tab(self):
        out = self.run_editor(['view-show items', 'key ctrl+j', 'print-panel-tabs', 'key ctrl+j', 'print-panel-tabs',
                               'print-state'])
        self.assertIn('terminals=0 open=0', out)
        self.assertIn('terminals=0 open=1', out)
        self.assertIn('focus=10', [l for l in out if l.startswith('tabs=')][0])

    def test_patch_ops_message_state_busy_expand(self):
        out = self.run_editor(['cmd viewfake.msg', 'cmd viewfake.busy', 'cmd viewfake.expand', 'wait 300',
                               'print-views', 'print-view todo', 'print-sidebar'])
        line = [l for l in out if l.startswith('view=1 ')][0]
        self.assertIn(' busy=1 ', line)
        self.assertTrue(line.endswith(' message=Scanned 3 files'), line)
        rows = self.rows(out)
        self.assertTrue(rows[0].startswith('row 0 y=359 d=0 closed id=f:main.rs'), rows)   # under the message
        out = self.run_editor(['cmd viewfake.empty', 'wait 200', 'print-views'])
        self.assertIn(' state=empty ', [l for l in out if l.startswith('view=1 ')][0])

    def test_an_extension_without_the_feature_gets_no_instances(self):
        out = self.run_editor(['print-views', 'print-sidebar'], mode='nofeature')
        self.assertFalse(any(l.startswith('view=') for l in out))
        self.assertIn('rhun-tests/viewfake.todo title=TODO at=0,335 size=240x239 badge=0 visible', out)

    def test_a_stopped_extension_keeps_its_section(self):
        out = self.run_editor(['ext-set viewfake stop', 'wait-ext viewfake stopped', 'wait 100', 'print-views',
                               'print-sidebar'])
        self.assertFalse(any(l.startswith('view=') for l in out))
        self.assertIn('rhun-tests/viewfake.todo title=TODO at=0,335 size=240x239 badge=4 visible', out)

    # --- lazy children, paging, checkboxes, actions, menus, reveal, multi-select ---

    def run_lazy(self, actions, lazy='answer'):
        self.env['VIEWFAKE_LAZY'] = lazy
        return self.run_editor(['view-show items', 'wait 200', 'wait 200', *actions])

    def test_lazy_children_are_asked_for_when_expanded(self):
        out = self.run_lazy(['print-view items'])
        x, y = self.row_xy(self.rows(out), 'a')
        out = self.run_lazy([f'click {x} {y}', 'wait 200', 'wait 100', 'print-view items', 'print-views'])
        rows = self.rows(out)
        self.assertTrue(rows[0].startswith('row 0 y=344 d=0 open cur id=a'), rows)
        self.assertTrue(rows[1].startswith('row 1 y=372 d=1 leaf id=a1 label=A one'), rows)
        log = self.fake_log()
        i = log.index('0 view 2 expand 4 1')             # after three pages: REV 4
        self.assertTrue(any(l.startswith('4 vkids 2 4 ') and l.endswith(' 1') for l in log[i:]), log)
        line = [l for l in out if l.startswith('view=2 ')][0]
        self.assertIn(' rev=5 ', line)          # three vmore pages and the vkids answer

    def test_a_failed_request_shows_an_error_row_and_retry_asks_again(self):
        out = self.run_lazy(['print-view items'], lazy='error')
        x, y = self.row_xy(self.rows(out), 'a')
        out = self.run_lazy([f'click {x} {y}', 'wait 200', 'wait 100', 'print-view items'], lazy='error')
        rows = self.rows(out)
        self.assertTrue(rows[1].startswith('row 1 y=372 d=1 error'), rows)
        out = self.run_lazy([f'click {x} {y}', 'wait 200', 'wait 100', f'click {x} {y + 28}', 'wait 200',
                             'wait 100', 'print-view items'], lazy='error')
        log = self.fake_log()
        last = len(log) - 1 - log[::-1].index('0 features view-tree')
        vkids = [l for l in log[last:] if ' vkids ' in l]
        self.assertEqual(len(vkids), 2)         # Retry asked again

    def test_a_collapse_cancels_the_wait_and_drops_the_late_answer(self):
        out = self.run_lazy(['print-view items'], lazy='late')
        x, y = self.row_xy(self.rows(out), 'a')
        out = self.run_lazy([f'click {x} {y}', 'wait 600', f'click {x} {y}', 'wait 600', 'wait 600',
                             'wait 200', 'print-view items'], lazy='late')
        rows = self.rows(out)
        self.assertTrue(rows[0].startswith('row 0 y=344 d=0 closed cur id=a'), rows)
        log = self.fake_log()
        rid = [l for l in log if ' vkids ' in l][0].split(' ')[0]
        self.assertIn(f'0 cancel {rid}', log)
        out = self.run_lazy([f'click {x} {y}', 'wait 600', f'click {x} {y}', 'wait 600', 'wait 600',
                             f'click {x} {y}', 'wait 600', 'wait 600', 'wait 200', 'print-view items'], lazy='late')
        self.assertTrue(any('id=a1 ' in r for r in self.rows(out)))     # asked again, answered

    def test_load_more_pages_while_its_row_is_in_view(self):
        out = self.run_lazy(['print-view items'])
        ids = [r.split(' id=')[1].split(' ')[0] for r in self.rows(out)]
        self.assertEqual(ids, ['a', 'b', 'c', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'])
        vmore = [l for l in self.fake_log() if ' vmore ' in l]
        self.assertEqual([l.split(' ')[4] for l in vmore], ['3', '5', '7'])   # HAVE

    def test_a_checkbox_toggles_and_says_so(self):
        out = self.run_lazy(['print-view items'])
        x, y = self.row_xy(self.rows(out), 'c')
        out = self.run_lazy([f'click {241 + 8 + 16 + 4} {y}', 'wait 100', 'print-view items'])
        self.assertIn(' check=1 ', [r for r in self.rows(out) if 'id=c ' in r][0])
        log = self.fake_log()
        i = log.index('0 view 2 check 4 1 1')
        self.assertEqual(log[i + 1], 'c')

    def test_title_and_inline_actions(self):
        out = self.run_editor(['print-view todo'])
        x, y = self.row_xy(self.rows(out), 't:lib.rs:1')
        # a hovered row shows its inline button at the right; the header's button shows on hover
        out = self.run_editor([f'move {x} {y}', 'wait 50', f'click {240 - 16 - 2 - 12} {y}', 'wait 100',
                               'move 100 320', 'wait 50', f'click {240 - 4 - 12} 321', 'wait 100'])
        log = self.fake_log()
        i = log.index('0 view 1 action 1 pin 10')
        self.assertEqual(log[i + 1], 't:lib.rs:1')
        self.assertIn('0 view 1 action 1 rescan 0', log)

    def test_a_context_menu_runs_an_action_or_discards_it(self):
        out = self.run_editor(['print-view todo'])
        x, y = self.row_xy(self.rows(out), 't:main.rs:1')
        out = self.run_editor([f'click {x} {y} right', 'print-menu', 'menu-pick Hide'])
        self.assertIn('Pin', out)
        self.assertIn('Hide', out)
        log = self.fake_log()
        i = log.index('0 view 1 action 1 hide 11')
        self.assertEqual(log[i + 1], 't:main.rs:1')
        out = self.run_editor([f'click {x} {y} right', 'cmd viewfake.renamed', 'wait 200', 'menu-pick Pin'])
        log = self.fake_log()
        i = log.index('0 view 1 discarded 1 action 11')
        self.assertEqual(log[i + 1], 't:main.rs:1')

    def test_vreveal_expands_selects_and_focuses(self):
        out = self.run_editor(['cmd viewfake.reveal', 'wait 300', 'print-view todo', 'print-sidebar'])
        rows = self.rows(out)
        self.assertIn(' cur ', [r for r in rows if 'id=t:lib.rs:1 ' in r][0])
        self.assertTrue([r for r in rows if 'id=f:lib.rs ' in r][0].split(' ')[4] == 'open')
        self.assertTrue(any(l.startswith('rhun-tests/viewfake.todo ') and l.endswith(' focus') for l in out))
        self.assertIn('ok 4', ' '.join(self.fake_log()))

    def test_multi_select_with_ctrl_and_shift(self):
        out = self.run_lazy(['print-view items'])
        rows = self.rows(out)
        xa, ya = self.row_xy(rows, 'b')
        xc, yc = self.row_xy(rows, 'p4')
        out = self.run_lazy(['cmd viewfake.multi', 'wait 100', f'click {xa} {ya}', f'click {xc} {yc} shift',
                             'wait 100'])
        log = self.fake_log()
        sel = [i for i, l in enumerate(log) if l.startswith('0 view 2 select ')]
        last = log[sel[-1]]
        self.assertEqual(last.split(' ')[5], '4')       # b, c, p3, p4
        self.assertEqual(log[sel[-1] + 1:sel[-1] + 5], ['b', 'c', 'p3', 'p4'])

    def test_removing_an_action_takes_its_buttons(self):
        out = self.run_editor(['cmd viewfake.delpin', 'wait 200', 'print-views'])
        self.assertTrue(any(l.startswith('view=1 ') and ' rev=2 ' in l for l in out))

    # --- the built-in API ---

    def test_built_in_code_fills_a_section_and_a_panel_tab(self):
        out = self.run_editor(['places-demo', 'print-sidebar', 'view-show demo-panel', 'print-panel-tabs',
                               'print-view demo', 'key Down', 'key Down', 'key Down', 'key Down', 'key Right',
                               'print-view demo', 'key Down', 'key Return', 'print-toast'],
                              exts=None, start=False)
        self.assertIn('demo title=Demo at=0,335 size=240x239 badge=0 visible', out)
        self.assertIn('demo-panel title=Demo at=241,344 size=759x230 badge=2 visible chosen focus', out)
        views = [i for i, l in enumerate(out) if l.startswith('at=')]
        first = out[views[0] + 1:views[1]]
        self.assertEqual([r.split(' id=')[1].split(' ')[0] for r in first], ['fruit', 'apple', 'banana', 'veg'])
        second = out[views[1] + 1:views[1] + 6]
        self.assertTrue(second[3].startswith('row 3 y=428 d=0 open cur id=veg'), second)
        self.assertTrue(second[4].startswith('row 4 y=456 d=1 leaf id=carrot'), second)  # asked for lazily
        self.assertIn('toast=activated Carrot', out)


if __name__ == '__main__':
    unittest.main()
