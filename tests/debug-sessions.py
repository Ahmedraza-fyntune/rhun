#!/usr/bin/env python3
"""Several sessions at once (docs/guide.md "Debugging"): the adapter's startDebugging starts a child
session of the same debugger that ends with its parent, and a launch.ini compound starts its
configurations in turn, the next once nothing waits for an answer."""
import unittest
import debughost


class Sessions(debughost.DebugHost):
    def test_start_debugging_makes_a_child_session(self):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')
        out = self.run_editor([*self.start(), 'wait-debug paused', 'wait 800', 'print-debug', 'echo --',
                               'debug-stop', 'wait-debug ended', 'wait 800', 'print-debug'], mode='child')
        first, second = out[:out.index('--')], out[out.index('--') + 1:]
        sessions = self.debug_lines(first)
        self.assertEqual(len(sessions), 2, first)
        child = sessions[1]
        self.assertEqual(self.field(child, 'name'), 'Child')
        self.assertEqual(self.field(child, 'parent'), '1')
        self.assertEqual(self.field(child, 'state'), 'paused')
        self.assertEqual(self.field(child, 'reason'), 'entry')
        responses = [l for l in self.dap_log() if l.startswith('RESPONSE startDebugging ')]
        self.assertTrue(responses and responses[0].split(' ')[2] == 'True', self.dap_log())
        args = [l for l in self.dap_log() if l.startswith('ARGS ') and '"Child"' in l]
        self.assertTrue(args, self.dap_log())
        # the parent stopped: the child ended with it
        self.assertEqual([self.field(l, 'state') for l in self.debug_lines(second)], ['ended', 'ended'], second)

    def test_a_compound_starts_its_configurations_in_turn(self):
        self.scenario()
        self.launch_ini('[A]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n'
                        '[B]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n'
                        '[Both]\ncompound = A | B\n')
        out = self.run_editor(['debug-start Both', 'wait 500', 'print-dialog', 'dialog yes', 'wait 1500',
                               'print-dialog', 'print-debug'])
        dialogs = [l for l in out if l.startswith('dialog=')]
        self.assertEqual(dialogs[1], 'dialog=none', out)          # one approval for both
        sessions = self.debug_lines(out)
        self.assertEqual([self.field(l, 'name') for l in sessions], ['A', 'B'], out)
        self.assertEqual([self.field(l, 'state') for l in sessions], ['paused', 'paused'], out)

    def test_a_compound_naming_a_missing_configuration(self):
        self.scenario()
        self.launch_ini('[A]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n[Both]\ncompound = Nope | A\n')
        out = self.run_editor(['debug-start Both', 'wait 500', 'dialog yes', 'wait 1000', 'print-debug',
                               'print-console'])
        self.assertEqual([self.field(l, 'name') for l in self.debug_lines(out)], ['A'], out)
        self.assertTrue([l for l in out if l.startswith('error') and 'Nope' in l], out)


if __name__ == '__main__':
    unittest.main()
