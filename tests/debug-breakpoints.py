#!/usr/bin/env python3
"""Breakpoints (src/app/bp.s): toggling, conditions, hit counts, logpoints, disabling, function
breakpoints, exception filters, what the adapter verifies, conditions an adapter cannot take,
changes while paused, breakpoints moving with edits, and the per-project state file that keeps
them across restarts. The adapter is tests/dap/fakedap.py."""
import unittest
import debughost


class Breakpoints(debughost.DebugHost):
    def stops(self, actions, mode=None, n=4):
        """start, then (wait for a stop, print vars, continue) up to n times"""
        self.launch_ini()
        script = [*actions, *self.start()]
        for _ in range(n):
            script += ['wait-debug paused 3000', 'print-debug', 'print-vars', 'debug-continue']
        script += ['wait-debug ended', 'print-debug', 'print-console', 'print-bps']
        return self.run_editor(script, mode=mode)

    def paused_at(self, out):
        return [self.field(l, 'at').rsplit(':', 1)[1] for l in self.debug_lines(out)
                if self.field(l, 'state') == 'paused']

    def b_values(self, out):
        return [l.strip() for l in out if l.strip().startswith('b = ') and '~stale' not in l]

    def test_toggle(self):
        a = self.src
        out = self.run_editor(['bp-toggle %s 3' % a, 'bp-toggle %s 7' % a, 'print-bps', 'bp-toggle %s 3' % a,
                               'print-bps'])
        self.assertEqual(out, ['%s 3 enabled=1 cond= hits= log= verified=- line=0 msg=' % a,
                               '%s 7 enabled=1 cond= hits= log= verified=- line=0 msg=' % a,
                               '%s 7 enabled=1 cond= hits= log= verified=- line=0 msg=' % a])

    def test_plain_breakpoint_stops_each_time(self):
        out = self.stops(['bp %s 3' % self.src])
        self.assertEqual(self.paused_at(out), ['3', '3', '3'])
        self.assertEqual(self.b_values(out), ['b = 0 : int', 'b = 1 : int', 'b = 2 : int'])
        self.assertIn('verified=- line=0', out[-1])         # the session is over: nothing reported

    def test_condition(self):
        out = self.stops(['bp %s 3 cond=b == 2' % self.src])
        self.assertEqual(self.b_values(out), ['b = 2 : int'])
        self.assertIn('cond=b == 2 hits= log=', out[-1])
        self.assertIn('"condition": "b == 2"', ' '.join(self.requests()))

    def test_hit_count(self):
        out = self.stops(['bp %s 3 hits=>= 2' % self.src])
        self.assertEqual(self.b_values(out), ['b = 1 : int', 'b = 2 : int'])

    def test_logpoint(self):
        out = self.stops(['bp %s 3 log=b is {b}' % self.src])
        self.assertEqual(self.paused_at(out), [])
        self.assertEqual([l for l in out if l.startswith('console b is')],
                         ['console b is 0', 'console b is 1', 'console b is 2'])

    def test_all_three_options(self):
        out = self.run_editor(['bp %s 3 cond=b == 1 hits=2 log=x {b}' % self.src, 'print-bps'])
        self.assertIn('cond=b == 1 hits=2 log=x {b} ', out[0])

    def test_disabled(self):
        out = self.stops(['bp %s 3' % self.src, 'bp-enable %s 3 0' % self.src])
        self.assertEqual(self.paused_at(out), [])
        self.assertIn(' 3 enabled=0 ', out[-1])

    def test_function_breakpoint(self):
        out = self.stops(['bp-function add'])
        self.assertEqual(self.paused_at(out), ['2', '2', '2'])
        self.assertIn('function add enabled=1 cond=', out)
        self.assertIn('setFunctionBreakpoints {"breakpoints": [{"name": "add"}]}', self.requests())

    def test_unverified_line(self):
        out = self.stops(['bp %s 5' % self.src], n=1)
        self.assertEqual(self.paused_at(out), [])
        self.assertIn('%s 5 enabled=1 cond= hits= log= verified=- line=0 msg=' % self.src, out)
        # while the session lived the adapter said so: check the log of what it answered
        self.assertTrue(any('setBreakpoints' in r and '"line": 5' in r for r in self.requests()))

    def test_unverified_state_while_running(self):
        self.launch_ini()
        out = self.run_editor(['bp %s 5' % self.src, 'bp %s 3' % self.src, *self.start(), 'wait-debug paused',
                               'print-bps'])
        self.assertIn('%s 5 enabled=1 cond= hits= log= verified=0 line=5 msg=no code at this line' % self.src, out)
        self.assertIn('%s 3 enabled=1 cond= hits= log= verified=1 line=3 msg=' % self.src, out)

    def test_condition_the_adapter_cannot_take(self):
        self.launch_ini()
        out = self.run_editor(['bp %s 3 cond=b == 1' % self.src, 'bp %s 9' % self.src, *self.start(),
                               'wait-debug paused', 'print-debug', 'print-bps'], mode='no-cond-caps')
        self.assertTrue(self.field(self.debug_lines(out)[0], 'at').endswith(':9'), out)
        self.assertIn('%s 3 enabled=1 cond=b == 1 hits= log= verified=x line=0 '
                      'msg=this debugger does not support conditions' % self.src, out)

    def test_added_while_paused(self):
        self.launch_ini()
        out = self.run_editor(['bp %s 2' % self.src, *self.start(), 'wait-debug paused', 'bp-clear',
                               'bp %s 9' % self.src, 'debug-continue', 'wait-debug paused', 'print-debug'])
        self.assertTrue(self.field(self.debug_lines(out)[0], 'at').endswith(':9'), out)

    def test_exception_filters(self):
        steps = self.steps()
        steps[5]['raise'] = 'ValueError'
        self.scenario(steps)
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\n')
        out = self.run_editor([*self.start(), 'wait-debug paused', 'print-debug', 'print-console'],
                              mode='exceptions')
        session = self.debug_lines(out)[0]
        self.assertEqual(self.field(session, 'reason'), 'exception', out)
        self.assertIn('error ValueError: raised at line 2', out)
        self.assertIn('setExceptionBreakpoints {"filters": ["uncaught"]}', self.requests())
        # turned off by the user: no stop
        self.log.unlink()
        out = self.run_editor(['exc-filter fake uncaught 0', *self.start(), 'wait-debug ended', 'print-debug'],
                              mode='exceptions')
        self.assertEqual(self.field(self.debug_lines(out)[0], 'exit'), '3', out)
        self.assertIn('setExceptionBreakpoints {"filters": []}', self.requests())

    def test_moving_with_edits(self):
        a = self.src
        out = self.run_editor(['bp %s 3' % a, 'bp %s 8' % a,
                               'key ctrl+Home', 'key Return', 'print-bps',      # a line above: both move down
                               'key ctrl+Home', 'key Delete', 'print-bps',      # and back
                               'key ctrl+Home', 'key Down', 'key Down', 'key End', 'key shift+Down', 'key Delete',
                               'print-bps'])                                    # line 3 joins into line 2...
        self.assertEqual(out[0:2], ['%s 4 enabled=1 cond= hits= log= verified=- line=0 msg=' % a,
                                    '%s 9 enabled=1 cond= hits= log= verified=- line=0 msg=' % a])
        self.assertEqual(out[2:4], ['%s 3 enabled=1 cond= hits= log= verified=- line=0 msg=' % a,
                                    '%s 8 enabled=1 cond= hits= log= verified=- line=0 msg=' % a])
        # end of line 3 to end of line 4 removed: line 4's text joins line 3; line 8 moves to 7
        self.assertEqual(out[4:6], ['%s 3 enabled=1 cond= hits= log= verified=- line=0 msg=' % a,
                                    '%s 7 enabled=1 cond= hits= log= verified=- line=0 msg=' % a])

    def test_deleted_line_merges(self):
        a = self.src
        out = self.run_editor(['bp %s 3' % a, 'bp %s 4' % a, 'key ctrl+Home', 'key Down', 'key Down',
                               'key End', 'key shift+Down', 'key Delete', 'print-bps'])
        # line 4 joined line 3: its breakpoint merges into line 3's
        self.assertEqual(out, ['%s 3 enabled=1 cond= hits= log= verified=- line=0 msg=' % a])

    def test_kept_across_restarts(self):
        a = self.src
        self.run_editor(['bp %s 3 cond=b == 1' % a, 'bp %s 8' % a, 'bp-enable %s 8 0' % a, 'bp-function add',
                         'debug-watch add total', 'exc-filter fake raised 1'])
        state = list((self.work / 'state/rhun').glob('*.debug'))
        self.assertEqual(len(state), 1)
        text = state[0].read_text()
        self.assertIn('b\ta.c\t3\t1\tb == 1\t\t\n', text)       # inside the project: relative
        out = self.run_editor(['print-bps'])
        self.assertEqual(out, ['%s 3 enabled=1 cond=b == 1 hits= log= verified=- line=0 msg=' % a,
                               '%s 8 enabled=0 cond= hits= log= verified=- line=0 msg=' % a,
                               'function add enabled=1 cond='])
        self.assertIn('w\ttotal\n', text)
        self.assertIn('x\tfake\traised\t1\n', text)
        # every breakpoint gone: the file goes too
        self.run_editor(['bp-clear', 'debug-watch remove total', 'exc-filter fake raised 0'])
        self.assertIn('x\tfake\traised\t0', state[0].read_text())

    def test_state_stays_with_its_project_when_the_folder_changes(self):
        # review P1: a breakpoint of project A was written into B's file after a folder switch
        b = self.work / 'projb'
        b.mkdir()
        (b / 'b.c').write_text('int main(void) { return 0; }\n')
        self.run_editor(['bp %s 3' % self.src, 'debug-watch add total', 'open ' + b.as_posix(), 'wait 300',
                         'bp %s 1' % (b / 'b.c')])
        files = {f.name: f.read_text() for f in (self.work / 'state/rhun').glob('*.debug')}
        mine = [t for n, t in files.items() if n.endswith('%proj.debug')]
        other = [t for n, t in files.items() if 'projb' in n]
        self.assertEqual(len(mine), 1, files)
        self.assertEqual(len(other), 1, files)
        self.assertIn('b\ta.c\t3', mine[0])
        self.assertIn('w\ttotal', mine[0])
        self.assertNotIn('a.c', other[0])
        self.assertNotIn('total', other[0])
        self.assertIn('b\tb.c\t1', other[0])


if __name__ == '__main__':
    unittest.main()
