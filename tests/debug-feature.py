#!/usr/bin/env python3
"""Feature `debug` (docs/extensions/v1.1.md "debug"): an extension starts a session of one of its
own debuggers with debug-start within 10 s of one of its commands, once per command, after the
user's approval, and hears debug-ended with the program's exit code. The extension is the fake
debugger's own program (tests/dap/debugfake.py), driven by a mode.json in its state folder."""
import json
import unittest
import debughost


class Feature(debughost.DebugHost):
    def ext_state(self):
        return self.work / 'state/rhun/extensions/rhun-tests--debugfake'

    def mode(self, **mode):
        state = self.ext_state()
        state.mkdir(parents=True, exist_ok=True)
        (state / 'mode.json').write_text(json.dumps(mode), encoding='utf-8')

    def ext_log(self):
        path = self.ext_state() / 'debugfake.log'
        return path.read_text(encoding='utf-8').splitlines() if path.exists() else []

    def leaves(self, **extra):
        program = self.scenario().as_posix()
        leaves = [['s', 'type', 'fake'], ['s', 'program', program]]
        for path, (kind, value) in extra.items():
            leaves.append([kind, path.replace('__', '.'), value])
        return leaves

    def test_debug_start_runs_a_session_and_reports_its_end(self):
        self.mode(start=[{'name': 'From ext', 'leaves': self.leaves(
            args__0=('s', 'x y'), args__1=('s', '-v'), count=('n', 7), stopOnEntry=('b', 'false'),
            env__LOG=('s', 'debug'), extra=('z', ''))}])
        out = self.run_editor(['cmd rhun-tests/debugfake.start', 'wait 500', 'print-dialog', 'dialog yes',
                               'wait-debug ended', 'print-debug', 'wait 300'])
        dialog = [l for l in out if l.startswith('dialog=')][0]
        self.assertEqual(dialog, 'dialog=Let Debug Fake run programs in proj?', out)
        session = self.debug_lines(out)[0]
        self.assertEqual(self.field(session, 'name'), 'From', out)       # "From ext": print-debug cuts at spaces
        self.assertEqual(self.field(session, 'exit'), '3')
        log = self.ext_log()
        self.assertIn('ok 1 1', log)
        self.assertIn('0 debug-ended 1 3', log)
        self.assertLess(log.index('ok 1 1'), log.index('0 debug-ended 1 3'))
        args = self.args_sent()
        self.assertEqual(args['name'], 'From ext')
        self.assertEqual(args['type'], 'fake')
        self.assertEqual(args['request'], 'launch')
        self.assertEqual(args['args'], ['x y', '-v'])
        self.assertEqual(args['count'], 7)
        self.assertIs(args['stopOnEntry'], False)
        self.assertEqual(args['env'], {'LOG': 'debug'})
        self.assertIsNone(args['extra'])

    def test_declined_approval(self):
        self.mode(start=[{'leaves': self.leaves()}])
        out = self.run_editor(['cmd rhun-tests/debugfake.start', 'wait 500', 'dialog no', 'wait 300', 'print-debug'])
        self.assertIn('error 1 cancelled', self.ext_log())
        self.assertFalse(self.log.exists(), 'the adapter never started')
        self.assertEqual(self.field(self.debug_lines(out)[0], 'reason'), 'cancelled')

    def test_approved_once_per_project(self):
        self.mode(start=[{'leaves': self.leaves()}, {'leaves': self.leaves()}])
        self.run_editor(['cmd rhun-tests/debugfake.start', 'wait 500', 'dialog yes', 'wait-debug ended',
                         'cmd rhun-tests/debugfake.start', 'wait 500', 'print-dialog', 'wait-debug ended',
                         'wait 300'])
        log = self.ext_log()
        self.assertIn('ok 1 1', log)
        self.assertIn('ok 2 2', log)
        self.assertIn('0 debug-ended 2 3', log)

    def test_without_the_feature(self):
        self.mode(features='', start=[{'leaves': self.leaves()}])
        out = self.run_editor(['cmd rhun-tests/debugfake.start', 'wait 500', 'print-debug'])
        self.assertIn('error 1 unknown debug-start needs the debug feature', self.ext_log())
        self.assertEqual(self.debug_lines(out), [])

    def test_a_type_not_its_own(self):
        leaves = self.leaves()
        leaves[0] = ['s', 'type', 'go']
        self.mode(start=[{'leaves': leaves}])
        self.run_editor(['cmd rhun-tests/debugfake.start', 'wait 500'])
        self.assertIn("error 1 refused the configuration's type is not one of your debuggers", self.ext_log())

    def test_one_session_per_command(self):
        self.mode(burst=True, start=[{'leaves': self.leaves()}, {'leaves': self.leaves()}])
        self.run_editor(['cmd rhun-tests/debugfake.start', 'wait 500', 'dialog yes', 'wait-debug ended', 'wait 300'])
        log = self.ext_log()
        self.assertIn('ok 1 1', log)
        self.assertIn('error 2 refused not within 10 s of one of your commands', log)

    def test_busy_while_the_approval_is_asked(self):
        self.mode(start=[{'leaves': self.leaves()}, {'leaves': self.leaves()}])
        self.run_editor(['cmd rhun-tests/debugfake.start', 'wait 500', 'cmd rhun-tests/debugfake.start', 'wait 500',
                         'dialog yes', 'wait-debug ended', 'wait 300'])
        log = self.ext_log()
        self.assertIn('error 2 busy', log)
        self.assertIn('ok 1 1', log)

    def test_bodies_that_do_not_parse(self):
        bad = ['1\nx 4 4\ntypefake', '2\ns 4 4\ntypefake', '1\ns 4 9\ntypefake', '1\nn 5 2\ncount1x',
               '1\nb 3 3\nyesyes', '1\nz 1 1\naa', 'nope', '3\ns 4 4\ntypefakes 3 1\na.bxs 5 1\na.b.cy']
        # two at a time: a third syntax error in a row ends the program (v1)
        for pair in (bad[0:2], bad[2:4], bad[4:6], bad[6:8]):
            with self.subTest(pair=pair):
                log = self.ext_state() / 'debugfake.log'
                if log.exists():
                    log.unlink()
                self.mode(burst=True, start=[{'raw': body} for body in pair])
                self.run_editor(['cmd rhun-tests/debugfake.start', 'wait 500'])
                errors = [l for l in self.ext_log() if l.startswith('error ')]
                self.assertEqual(len(errors), 2, self.ext_log())
                for i, line in enumerate(errors):
                    self.assertTrue(line.startswith('error %d syntax' % (i + 1)), errors)


if __name__ == '__main__':
    unittest.main()
