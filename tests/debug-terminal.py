#!/usr/bin/env python3
"""The adapter's runInTerminal request (docs/guide.md "Debugging"): the program runs in a terminal
tab of its own (the tasks group's term_run) with the adapter's arguments, folder and environment
(null unsets a name), the keyboard goes there, and the answer carries the program's pid. The
adapter is tests/dap/fakedap.py; `console = integratedTerminal` makes it ask."""
import json
import unittest
import debughost


class Terminal(debughost.DebugHost):
    def ini(self, extra=''):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n'
                        'console = integratedTerminal\n' + extra)

    def responses(self):
        return [l.split(' ', 3)[1:] for l in self.dap_log() if l.startswith('RESPONSE runInTerminal ')]

    def test_program_runs_in_a_terminal_tab(self):
        self.ini()
        self.env['FAKEDAP_GONE'] = 'still here'
        # the stop on entry shows the editor at the stop; Ctrl+` goes back to the program's tab
        out = self.run_editor([*self.start(), 'wait-debug paused', 'wait-term in the terminal',
                               'cmd toggle_terminal', 'type hello',
                               'key Return', 'wait-term typed hello', 'print-terminals', 'print-term',
                               'debug-stop', 'wait-debug ended', 'print-debug'])
        terms = [l for l in out if l.lstrip('*').startswith('term=')]
        self.assertEqual(len(terms), 1, out)
        self.assertIn('kind=terminal', terms[0])
        self.assertTrue(terms[0].endswith('title=Fake program'), terms[0])
        # the adapter's environment: FAKEDAP_TERM set, FAKEDAP_GONE (null) unset
        self.assertTrue(any('in the terminal yes None' in l for l in out), out)
        self.assertTrue(any('typed hello' in l for l in out), out)
        (success, body), = [(r[1], r[2]) for r in self.responses()]
        self.assertEqual(success, 'True')
        pid = json.loads(body.rsplit(' ', 1)[0])['processId']
        self.assertGreater(pid, 0)
        self.assertIn('pid=%d ' % pid, terms[0])

    def test_folder_and_title(self):
        (self.proj / 'sub').mkdir()
        self.ini('cwd = ${project}/sub\ntermTitle = My program\ntermArgs.0 = python3\ntermArgs.1 = -c\n'
                 'termArgs.2 = import os; print("cwd", os.getcwd())\n')
        out = self.run_editor([*self.start(), 'wait-debug paused', 'wait-term cwd', 'print-terminals',
                               'print-term'])
        screen = ''.join(out)       # lines wrap at the terminal's width
        self.assertIn('cwd %s' % (self.proj / 'sub').as_posix(), screen)
        self.assertTrue(any(l.endswith('title=My program') for l in out), out)

    def test_program_that_cannot_start(self):
        self.ini('termArgs.0 = no-such-program-for-rhun\n')
        out = self.run_editor([*self.start(), 'wait-debug paused', 'wait 800', 'print-terminals'])
        (success, rest), = [(r[1], r[2]) for r in self.responses()]
        self.assertEqual(success, 'False', out)
        self.assertTrue(rest.endswith('the program could not be started in the terminal'), rest)

    def test_arguments_that_are_not_strings(self):
        self.ini('termArgs = numbers\n')       # the fake adapter sends [1, 2]
        out = self.run_editor([*self.start(), 'wait-debug paused', 'wait 300', 'print-terminals'])
        (success, rest), = [(r[1], r[2]) for r in self.responses()]
        self.assertEqual(success, 'False', out)
        self.assertTrue(rest.endswith('runInTerminal needs args, a list of strings'), rest)
        self.assertFalse([l for l in out if 'kind=terminal' in l], out)


if __name__ == '__main__':
    unittest.main()
