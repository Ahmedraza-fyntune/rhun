#!/usr/bin/env python3
"""The test explorer (feature "tests", docs/extensions/v1.1.md) driven headlessly with the fake
controller tests/ext/testsfake.py: items and lazy resolution, runs and results, caps, cancel,
test-exec processes and back-pressure, coverage. Each run gets its own HOME and config; TESTS_MODE
and TESTS_LOG reach the fake through the environment."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
EXTS = ROOT / 'tests/ext/testing'
CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
SOURCE = ('package pkg\n\nfunc TestA(t *testing.T) {\n\tt.Run("sub", nil)\n}\n\n'
          'func TestB(t *testing.T) {\n\tcheck()\n}\n\nfunc TestC(t *testing.T) {\n\tt.Skip()\n}\n')
PKG = 'go:example/pkg'
EXPAND = ['cmd testing', 'wait-test-items 2', 'test-expand testsfake ' + PKG, 'wait-test-items 6', 'wait 150',
          'test-expand testsfake go:example/pkg#a_test.go']


class Testing(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-tests-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        (self.proj / 'a_test.go').write_text(SOURCE, encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.log = self.work / 'state/rhun/extensions/rhun-tests--testsfake/log.txt'
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(),
                        TESTS_LOG=self.log.as_posix())
        self.env.pop('TESTS_MODE', None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions, mode=None, files=('a_test.go',), timeout=90):
        env = dict(self.env)
        if mode:
            env['TESTS_MODE'] = mode
        opens = ['open ' + (self.proj / name).as_posix() for name in files]
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', *opens, *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', '1000x600', '--scale', '1',
                                 '--extensions', str(EXTS), '--script', script.as_posix()],
                                env=env, capture_output=True, timeout=timeout)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8', errors='replace').splitlines()

    def fake_log(self):
        return self.log.read_text(encoding='utf-8', errors='replace').splitlines() if self.log.exists() else []

    def logged(self, prefix):
        return [line for line in self.fake_log() if line.startswith(prefix)]

    def line(self, out, ident):
        hits = [l.strip() for l in out if (' id=' + ident + ' ') in l]
        self.assertTrue(hits, (ident, out))
        return hits[-1]

    # --- items ---

    def test_roots_come_with_tests_and_lazy_items_resolve_when_expanded(self):
        out = self.run_editor(['cmd testing', 'wait-test-items 2', 'print-tests',
                               'test-expand testsfake ' + PKG, 'wait-test-items 6', 'wait 150', 'print-tests all',
                               'test-expand testsfake go:example/other', 'wait 300', 'print-tests'])
        self.assertIn('notrun Fake Tests id=rhun-tests/testsfake kind=controller ms=-', out)
        self.assertIn('  notrun pkg id=go:example/pkg kind=group ms=- lazy', out)
        self.assertIn('      notrun TestA id=go:example/pkg.TestA kind=test ms=- range=3:1-5:2 desc=fast', out)
        self.assertIn('      notrun TestC id=go:example/pkg.TestC kind=test ms=- range=11:1-13:2 nodebug', out)
        # a refused tests-resolve shows its reason on the row; the item stays lazy
        self.assertIn('  notrun other id=go:example/other kind=group ms=- lazy error=refused cannot list other', out)
        self.assertEqual(self.logged('recv 1 tests-resolve 0'), ['recv 1 tests-resolve 0'])
        self.assertIn("recv 2 tests-resolve 14 b'go:example/pkg'", self.fake_log())
        self.assertIn('file-items ok 1', self.fake_log())
        # collapsed items still count
        self.assertEqual(out[-1], 'passed=0 failed=0 errored=0 skipped=0 notrun=3')

    def test_an_unanswered_resolve_gives_up_after_30_s(self):
        out = self.run_editor(['cmd testing', 'wait 31500', 'print-tests'], mode='resolveslow', timeout=120)
        self.assertIn('notrun Fake Tests id=rhun-tests/testsfake kind=controller ms=- error=no answer in time', out)
        self.assertIn('recv 0 cancel 1', self.fake_log())

    def test_bad_bodies_are_refused_and_change_nothing(self):
        out = self.run_editor(['cmd testing', 'wait-test-items 2', 'wait 800', 'print-tests all'], mode='remove')
        log = self.fake_log()
        self.assertTrue(any(l.startswith('unknown-parent error ') and l.endswith('refused unknown parent') for l in log), log)
        self.assertTrue(any(l.startswith('cycle error ') and 'cannot move below itself' in l for l in log), log)
        self.assertTrue(any(l.startswith('bad-range error ') and ' badpos ' in l for l in log), log)
        self.assertTrue(any(l.startswith('relative error ') and 'absolute path' in l for l in log), log)
        self.assertTrue([l for l in log if l.startswith('remove ok ')], log)
        self.assertFalse([l for l in out if 'go:example/other' in l], out)
        self.assertFalse([l for l in out if ' id=x ' in l or ' id=r ' in l], out)

    def test_item_caps(self):
        self.run_editor(['cmd testing', 'wait-test-items 50000', 'wait 500'], mode='flood')
        log = self.fake_log()
        self.assertTrue(any(l.startswith('flood-body error ') and 'toobig 10000 items' in l for l in log), log)
        self.assertTrue(any(l.startswith('flood-ok ok') for l in log), log)
        self.assertTrue(any(l.startswith('flood-add step 3: error ') and 'toobig 50000 items per extension' in l
                            for l in log), log)

    def test_replace_keeps_the_results_of_kept_ids(self):
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait-tests', 'wait 300', 'print-tests all'],
                              mode='replaceafter')
        self.assertIn('replace ok 11', self.fake_log())
        self.assertEqual(self.line(out, 'go:example/pkg.TestA'),
                         'passed TestA renamed id=go:example/pkg.TestA kind=test ms=12 range=3:1-5:2')
        self.assertIn('notrun TestD id=go:example/pkg.TestD kind=test ms=- range=15:1-16:2',
                      [l.strip() for l in out])
        self.assertFalse([l for l in out if 'TestB' in l or 'TestC' in l], out)
        # TestA kept its id, so its children (the subtest added during the run) stay with it
        self.assertIn('passed sub id=go:example/pkg.TestA/sub kind=test ms=1 range=4:2-4:9', [l.strip() for l in out])
        self.assertEqual(out[-1], 'passed=1 failed=0 errored=0 skipped=0 notrun=1')

    # --- runs ---

    def test_run_all_reports_states_results_and_counts(self):
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait-tests', 'print-tests all', 'print-test-runs',
                               'print-test-result testsfake go:example/pkg.TestB'])
        self.assertIn('run 1 run 0 ', self.fake_log())
        self.assertEqual(self.line(out, 'rhun-tests/testsfake'), 'failed Fake Tests id=rhun-tests/testsfake kind=controller ms=-')
        self.assertEqual(self.line(out, 'go:example/pkg.TestA/sub'), 'passed sub id=go:example/pkg.TestA/sub kind=test ms=1 range=4:2-4:9')
        self.assertEqual(self.line(out, 'go:example/pkg.TestC'), 'skipped TestC id=go:example/pkg.TestC kind=test ms=0 range=11:1-13:2 nodebug')
        self.assertIn('passed=1 failed=1 errored=0 skipped=1 notrun=0', out)
        runs = [l for l in out if l.startswith('run=')]
        self.assertEqual(len(runs), 1, out)
        self.assertTrue(runs[0].startswith('run=1 ext=rhun-tests/testsfake profile=run state=ended passed=2 failed=1 '
                                           'errored=0 skipped=1 notrun=0 dropped=0 procs=0'), runs)
        at = out.index('state=failed ms=30 run=1 first=Greet mismatch')
        f = (self.proj / 'a_test.go').as_posix()
        self.assertEqual(out[at + 1], 'message=Greet mismatch\\nsecond line at=' + f + ':8:2 '
                         'expected=Hello, rhun!\\nWelcome. actual=Hello, rhun')
        self.assertEqual(out[at + 2], 'output==== RUN TestB\\nfail\\n')

    def test_rerun_failed_runs_only_failed_leaves_and_rerun_last_repeats(self):
        self.run_editor([*EXPAND, 'cmd test_run_all', 'wait-tests', 'cmd test_rerun_failed', 'wait-tests',
                         'cmd test_rerun_last', 'wait-tests'])
        runs = self.logged('run ')
        self.assertEqual(runs, ['run 1 run 0 ', 'run 2 run 1 go:example/pkg.TestB', 'run 3 run 1 go:example/pkg.TestB'])

    def test_selected_item_cursor_and_file_runs(self):
        self.run_editor([*EXPAND, 'test-select testsfake go:example/pkg.TestA', 'test-action run', 'wait-tests',
                         'test-select testsfake', 'test-action run', 'wait-tests',
                         'cmd goto_line', 'type 8', 'key Return', 'cmd test_run_cursor', 'wait-tests',
                         'cmd goto_line', 'type 2', 'key Return', 'cmd test_run_cursor', 'wait-tests',
                         'cmd test_run_file', 'wait-tests'])
        self.assertEqual(self.logged('run '), ['run 1 run 1 go:example/pkg.TestA', 'run 2 run 0 ',
                                               'run 3 run 1 go:example/pkg.TestB',
                                               'run 4 run 1 go:example/pkg#a_test.go',
                                               'run 5 run 1 go:example/pkg#a_test.go'])

    def test_a_kind_the_controller_does_not_offer_is_not_sent(self):
        out = self.run_editor([*EXPAND, 'test-select testsfake go:example/pkg.TestA', 'test-action debug',
                               'print-toast', 'wait 200', 'print-test-runs'])
        self.assertFalse(self.logged('run '))
        self.assertTrue(any('does not offer' in l for l in out), out)

    def test_concurrent_runs_with_the_same_items(self):
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'cmd test_run_all', 'wait-tests', 'print-test-runs',
                               'print-tests all'])
        runs = [l for l in out if l.startswith('run=')]
        self.assertEqual(len(runs), 2, out)
        self.assertTrue(all(' state=ended passed=2 failed=1 ' in r for r in runs), runs)
        self.assertIn('passed=1 failed=1 errored=0 skipped=1 notrun=0', out)

    def test_cancel_tells_the_controller_and_states_go_back(self):
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait 400', 'print-tests all', 'cmd test_cancel',
                               'wait-tests', 'print-tests all', 'print-test-runs'], mode='slow')
        self.assertIn('recv 0 test-cancel 1', self.fake_log())
        first = out.index('running Fake Tests id=rhun-tests/testsfake kind=controller ms=-')
        self.assertEqual(self.line(out[first:first + 8], 'go:example/pkg.TestB'), 'running TestB id=go:example/pkg.TestB kind=test ms=- range=7:1-9:2')
        self.assertEqual(self.line(out, 'go:example/pkg.TestB'), 'notrun TestB id=go:example/pkg.TestB kind=test ms=- range=7:1-9:2')
        self.assertTrue([l for l in out if l.startswith('run=1 ') and ' state=ended ' in l and ' notrun=3 ' in l], out)

    def test_a_controller_that_ignores_cancel_has_its_run_ended_after_5_s(self):
        t0 = time.time()
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait 300', 'cmd test_cancel', 'wait-tests',
                               'print-test-runs', 'print-tests all'], mode='stubborn')
        self.assertGreater(time.time() - t0, 5)
        self.assertTrue([l for l in out if l.startswith('run=1 ') and ' state=ended ' in l], out)
        self.assertIn('passed=0 failed=0 errored=0 skipped=0 notrun=3', out)

    def test_a_controller_that_stops_ends_its_run_errored(self):
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait-tests', 'wait 300', 'print-test-runs',
                               'print-extensions'], mode='crash')
        self.assertTrue([l for l in out if l.startswith('run=1 ') and ' state=ended errored-run ' in l], out)

    def test_late_updates_are_stale_and_unknown_items_counted(self):
        self.run_editor([*EXPAND, 'cmd test_run_all', 'wait-tests', 'wait 300'], mode='late')
        self.assertTrue([l for l in self.fake_log() if l.startswith('late error ') and l.endswith('stale run over')],
                        self.fake_log())
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait-tests', 'print-test-runs'], mode='unknown')
        self.assertTrue([l for l in out if l.startswith('run=1 ') and ' dropped=1 ' in l and ' passed=1 ' in l], out)

    def test_a_refused_run_ends_errored_and_says_why(self):
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait-tests', 'print-test-runs', 'print-toast'],
                              mode='refuse')
        self.assertTrue([l for l in out if l.startswith('run=1 ') and ' state=ended errored-run ' in l], out)
        self.assertTrue([l for l in out if 'the build is running' in l], out)

    def test_item_output_is_cut_at_256_kib(self):
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait-tests',
                               'print-test-result testsfake go:example/pkg.TestA'], mode='bigout')
        self.assertTrue(self.logged('big ok'), self.fake_log())
        output = [l for l in out if l.startswith('output=')][0]
        self.assertTrue(output.endswith('\\n[output cut]\\n'), output[-80:])
        self.assertEqual(output.count('y'), 262144 - len('ok A\n'))

    def test_expected_and_actual_open_as_a_diff_and_output_as_a_tab(self):
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait-tests',
                               'test-select testsfake go:example/pkg.TestB', 'test-action diff', 'print-tabs',
                               'print-doc', 'test-action output', 'print-doc', 'test-action failure', 'print-state',
                               'test-select testsfake go:example/pkg.TestC', 'test-action goto', 'print-state'])
        at = out.index('@@ -1,2 +1,1 @@')
        self.assertEqual(out[at:at + 5], ['@@ -1,2 +1,1 @@', 'Hello, rhun!', 'Welcome.', 'Hello, rhun', '<eod>'])
        self.assertIn('tabs=a_test.go | *Expected \u2194 Actual: TestB', out)
        at = out.index('=== RUN TestB')
        self.assertEqual(out[at:at + 4], ['=== RUN TestB', 'fail', '', '<eod>'])
        states = [l for l in out if l.startswith('tabs=3 ')]
        self.assertIn(' line=8 col=5 ', states[0])       # 8:2, after a tab four columns wide
        self.assertIn(' line=11 col=1 ', states[1])

    def test_coverage_run(self):
        f = (self.proj / 'a_test.go').as_posix()
        out = self.run_editor([*EXPAND, 'cmd test_coverage_all', 'wait-tests', 'print-test-runs',
                               'print-coverage ' + f])
        self.assertIn('run 1 coverage 0 ', self.fake_log())
        self.assertTrue(self.logged('coverage ok'), self.fake_log())
        self.assertIn('covered=3 partial=1 missed=0 lines=3:C,5:C,6:P,7:C', out)

    # --- the Testing section ---

    def section(self, out):
        return [l for l in out if l.startswith('row ')]

    def test_the_testing_section_mirrors_the_tree_and_its_buttons_run(self):
        # at 1000x600 the sidebar holds the explorer and Testing; Testing's header is above y=335,
        # its buttons right to left from x=212: Cancel, Re-run Failed, Coverage, Run All
        out = self.run_editor([*EXPAND, 'print-testing', 'move 150 321', 'click 150 321', 'wait-tests',
                               'test-select testsfake go:example/pkg.TestB', 'print-testing', 'print-sidebar',
                               'key r', 'wait-tests'])
        rows = self.section(out)
        self.assertTrue(rows[0].startswith('row 0 '), rows)
        self.assertIn(' open id=00 label=Fake Tests ', rows[0])
        self.assertIn(' leaf id=00go:example/pkg.TestB label=TestB icon=', rows[4])
        self.assertIn('testing title=Testing at=0,335 size=240x239 badge=0 visible focus', out)
        self.assertEqual(self.logged('run '), ['run 1 run 0 ', 'run 2 run 1 go:example/pkg.TestB'])
        after = rows[len(rows) // 2:]
        self.assertTrue([r for r in after if 'id=00go:example/pkg.TestB ' in r and ' cur ' in r and 'desc=30 ms' in r],
                        after)

    def test_a_lazy_item_expanded_in_the_section_is_resolved(self):
        out = self.run_editor(['cmd testing', 'wait-test-items 2', 'print-testing', 'key Down', 'key Down',
                               'key Right', 'wait 300', 'print-testing', 'print-tests'])
        rows = self.section(out)
        self.assertIn(' closed id=00go:example/pkg label=pkg ', rows[1])
        self.assertTrue([r for r in rows if 'id=00go:example/pkg#a_test.go' in r], rows)
        self.assertIn("recv 2 tests-resolve 14 b'go:example/pkg'", self.fake_log())

    # --- test-exec ---

    def test_exec_runs_a_program_as_the_user_and_passes_its_output(self):
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait 500', 'print-dialog', 'dialog yes', 'wait-tests',
                               'print-test-runs', 'print-test-result testsfake go:example/pkg.TestA',
                               'cmd test_run_all', 'wait-tests', 'print-dialog'], mode='exec')
        # the first program in the project asks once, showing the command; the second run does not
        self.assertIn('dialog=Let Fake Tests run programs in proj?', out)
        self.assertTrue([l for l in out if l.startswith("text=python3 -c 'import sys print(")], out)
        self.assertEqual(out[-1], 'dialog=none')
        log = self.fake_log()
        self.assertTrue([l for l in log if l.startswith('exec ok ') and l.endswith(' 1')], log)
        self.assertIn("exec-result exit=3 out=b'out-line\\n' err=b'err-line\\n'", log)
        self.assertIn('output=out-line\\nerr-line\\n', out)
        self.assertTrue([l for l in out if l.startswith('run=1 ') and ' procs=0' in l], out)

    def test_exec_refusals(self):
        self.run_editor([*EXPAND, 'cmd test_run_all', 'wait 500', 'dialog yes', 'wait-tests', 'wait 4000'], mode='execbad')
        log = self.fake_log()
        def reply(prefix):
            hit = [l for l in log if l.startswith(prefix + ' ')]
            self.assertTrue(hit, (prefix, log))
            return hit[0][len(prefix) + 1:]
        self.assertTrue(reply('bad-prog').endswith(' needs tests=ls'))
        self.assertTrue(reply('bad-name').endswith(' refused the program must be a bare name'))
        self.assertTrue(reply('bad-cwd').endswith(' refused the folder is not inside the project'))
        self.assertIn(' syntax a variable is NAME=VALUE', reply('bad-env'))
        self.assertTrue(reply('missing').endswith(' refused the folder is not inside the project'))
        self.assertIn(' busy ', reply('fifth'))
        self.assertTrue(reply('over').endswith(' stale run over'))
        # the four that started were stopped when the run ended
        self.assertEqual(len([l for l in log if l.startswith('recv 0 test-exit ') and l.endswith(' killed')]), 4, log)

    def test_a_declined_approval_answers_cancelled_and_asks_again(self):
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait 500', 'dialog no', 'wait-tests',
                               'cmd test_run_all', 'wait 500', 'print-dialog', 'dialog no', 'wait-tests'], mode='exec')
        self.assertEqual(len([l for l in self.fake_log() if l.startswith('exec error ') and l.endswith(' cancelled')]), 2,
                         self.fake_log())
        self.assertEqual(len([l for l in out if l.startswith('dialog=Let Fake Tests')]), 1, out)

    def test_cancel_stops_processes_after_2_s(self):
        self.run_editor([*EXPAND, 'cmd test_run_all', 'wait 500', 'dialog yes', 'wait 800', 'cmd test_cancel',
                         'wait-tests', 'wait 3000'], mode='slowexec')
        log = self.fake_log()
        self.assertTrue([l for l in log if l.startswith('recv 0 test-out ') and 'sleeping' in l], log)
        self.assertIn('exit killed', log)

    def test_back_pressure_keeps_a_chatty_process_waiting(self):
        self.env['TESTS_CHATTY'] = str(8 << 20)
        out = self.run_editor([*EXPAND, 'cmd test_run_all', 'wait 500', 'dialog yes', 'wait-tests', 'print-extensions'],
                              mode='chatty', timeout=180)
        self.assertIn('chatty exit=0 bytes=%d' % (8 << 20), self.fake_log())
        self.assertTrue([l for l in out if l.startswith('rhun-tests/testsfake state=running')], out)


if __name__ == '__main__':
    unittest.main()
