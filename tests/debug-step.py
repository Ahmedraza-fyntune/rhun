#!/usr/bin/env python3
"""Stops and stepping (src/app/dap.s): stop on entry, step over, into and out, Pause, the stopped
file revealed (or not, with preserveFocusHint), variables loaded lazily and opened again after the
next stop, references never used past their stop, watches, and the console's evaluation. The
adapter is tests/dap/fakedap.py."""
import unittest
import debughost


class Step(debughost.DebugHost):
    def at(self, out):
        return [self.field(l, 'at').rsplit(':', 1)[-1] for l in self.debug_lines(out)]

    def test_entry_and_steps(self):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')
        out = self.run_editor([*self.start(), 'wait-debug paused', 'print-debug',
                               'debug-step over', 'wait-debug paused', 'print-debug',
                               'debug-step into', 'wait-debug paused', 'print-debug', 'print-stack',
                               'debug-step out', 'wait-debug paused', 'print-debug', 'print-vars'])
        sessions = self.debug_lines(out)
        self.assertEqual([self.field(l, 'reason') for l in sessions], ['entry', 'step', 'step', 'step'])
        self.assertEqual(self.at(out), ['6', '8', '2', '8'])
        a = self.src.as_posix()
        self.assertIn('  frame 0 add %s:2 *' % a, out)
        self.assertIn('  frame 1 main %s:8' % a, out)
        self.assertIn('  i = 1 : int', out)                     # back in main, one round later
        reqs = [r.split(' ')[0] for r in self.requests()]
        self.assertEqual([r for r in reqs if r in ('next', 'stepIn', 'stepOut')], ['next', 'stepIn', 'stepOut'])

    def test_pause(self):
        steps = self.steps()
        steps[4]['block'] = True
        self.scenario(steps)
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\n')
        out = self.run_editor([*self.start(), 'wait 300', 'print-debug', 'debug-pause', 'wait-debug paused',
                               'print-debug', 'debug-continue', 'wait-debug ended', 'print-debug'])
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'running')
        self.assertEqual(self.field(sessions[1], 'reason'), 'pause')
        self.assertEqual(self.field(sessions[2], 'exit'), '3')
        self.assertIn('pause {"threadId": 1}', self.requests())

    def test_stop_reveals_the_file(self):
        (self.proj / 'b.txt').write_text('other\n')
        self.launch_ini()
        out = self.run_editor(['bp %s 3' % self.src, *self.start(), 'wait-debug paused', 'print-tabs',
                               'print-cursor'], files=('b.txt',))
        tabs = [l for l in out if l.startswith('tabs=')][0]
        self.assertIn('*a.c', tabs, out)
        self.assertNotIn('*b.txt', tabs)

    def test_preserve_focus(self):
        (self.proj / 'b.txt').write_text('other\n')
        self.launch_ini()
        out = self.run_editor(['bp %s 3' % self.src, *self.start(), 'wait-debug paused', 'print-tabs'],
                              files=('b.txt',), mode='preserve-focus')
        tabs = [l for l in out if l.startswith('tabs=')][0]
        self.assertEqual(tabs, 'tabs=*b.txt', out)

    def variables_scenario(self):
        a = self.src.as_posix()
        p1 = {'x': 1, 'y': [10, 20], 'name': 'pt'}
        p2 = {'x': 2, 'y': [10, 20, 30], 'name': 'pt'}
        steps = [{'file': a, 'line': 6, 'function': 'main', 'locals': {'total': 0, 'p': p1}},
                 {'file': a, 'line': 7, 'function': 'main', 'locals': {'total': 1, 'p': p2}},
                 {'file': a, 'line': 9, 'function': 'main', 'locals': {'total': 2, 'q': 5}}]
        self.scenario(steps)
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')

    def test_variables_open_again_after_a_stop(self):
        self.variables_scenario()
        out = self.run_editor([*self.start(), 'wait-debug paused', 'debug-expand Locals/p', 'wait 200',
                               'debug-expand Locals/p/y', 'wait 200', 'print-vars', 'echo --',
                               'debug-step over', 'wait-debug paused', 'wait 200', 'print-vars', 'echo --',
                               'debug-collapse Locals/p', 'debug-step over', 'wait-debug paused', 'print-vars'],
                              mode='strict-refs')
        first = out[out.index('debug=paused') + 1:out.index('--')]
        self.assertEqual(first, ['Locals', '  total = 0 : int', '  p = {...} : dict', '    x = 1 : int',
                                 '    y = [2] : list', '      [0] = 10 : int', '      [1] = 20 : int',
                                 '    name = "pt" : str', 'Globals'])
        second = out[out.index('--') + 2:out.index('--', out.index('--') + 1)]
        self.assertIn('      [2] = 30 : int', second)              # opened again, with the new values
        self.assertIn('    x = 2 : int', second)
        third = out[out.index('--', out.index('--') + 1) + 2:]
        self.assertEqual(third, ['Locals', '  total = 2 : int', '  q = 5 : int', 'Globals'])
        self.assertFalse([l for l in self.dap_log() if l.startswith('STALE')], self.dap_log())

    def test_old_references_are_never_sent(self):
        self.variables_scenario()
        # expanding right after a resume: the node belongs to the old stop and must not be asked for
        out = self.run_editor([*self.start(), 'wait-debug paused', 'debug-step over', 'debug-expand Locals/p',
                               'wait-debug paused', 'wait 200', 'print-vars'], mode='strict-refs')
        self.assertFalse([l for l in self.dap_log() if l.startswith('STALE')], self.dap_log())
        self.assertIn('  p = {...} : dict', out)

    def test_expensive_scope_stays_closed(self):
        self.variables_scenario()
        out = self.run_editor([*self.start(), 'wait-debug paused', 'print-vars', 'debug-expand Globals',
                               'wait 200', 'print-vars'])
        self.assertEqual(out.count('Globals'), 2)
        self.assertIn('  G = 1 : int', out)
        self.assertEqual(out.index('  G = 1 : int'), len(out) - 1)

    def test_watches(self):
        self.variables_scenario()
        out = self.run_editor(['debug-watch add total', 'debug-watch add p.x', 'debug-watch add nosuch',
                               *self.start(), 'wait-debug paused', 'wait 200', 'print-watch', 'echo --',
                               'debug-watch remove p.x', 'debug-step over', 'wait-debug paused', 'wait 200',
                               'print-watch'])
        first = out[out.index('debug=paused') + 1:out.index('--')]
        self.assertEqual(first, ['total = 0 : int', 'p.x = 1 : int', "nosuch = name 'nosuch' is not defined !error"])
        second = out[out.index('--') + 2:]
        self.assertEqual(second, ['total = 1 : int', "nosuch = name 'nosuch' is not defined !error"])

    def test_console_evaluation(self):
        self.variables_scenario()
        out = self.run_editor([*self.start(), 'wait-debug paused', 'debug-eval total', 'debug-eval p.name',
                               'debug-eval nope', 'wait 300', 'print-console'])
        self.assertIn('input total', out)
        self.assertIn('result 0', out)
        self.assertIn('result "pt"', out)
        self.assertIn("error name 'nope' is not defined", out)
        self.assertIn('repl', ' '.join(self.requests()))

    def test_watch_edits_while_answers_are_on_their_way(self):
        # review: answers to an earlier round landed under the wrong expressions
        self.variables_scenario()
        out = self.run_editor([*self.start(), 'wait-debug paused', 'debug-watch add total', 'debug-watch add p.x',
                               'debug-watch remove total', 'wait 300', 'print-watch'], mode='slow=50')
        self.assertEqual(out[out.index('debug=paused') + 1:], ['p.x = 1 : int'])

    def test_refused_step_leaves_the_program_paused(self):
        # review: a failed next/stepIn/stepOut left the session "running"
        self.variables_scenario()
        out = self.run_editor([*self.start(), 'wait-debug paused', 'debug-step over', 'wait-debug paused',
                               'print-debug', 'print-vars', 'print-console', 'debug-continue', 'wait-debug paused',
                               'print-debug'], mode='fail-step')
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'paused', out)
        self.assertTrue(self.field(sessions[0], 'at').endswith(':6'), out)
        self.assertIn('  total = 0 : int', out)             # its variables were asked for again
        self.assertIn('error cannot step here', out)
        self.assertEqual(self.field(sessions[1], 'state'), 'ended', out)    # continue still works: to the end
        self.assertEqual(self.field(sessions[1], 'exit'), '3', out)


if __name__ == '__main__':
    unittest.main()
