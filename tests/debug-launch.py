#!/usr/bin/env python3
"""Debug sessions start (docs/guide.md "Debugging"): the approval asked once per extension and
project, the three orders adapters answer launch in, a failed launch, an initialize that never
comes, Run without debugging, an extension without debug = yes, the adapter's error output, and
an adapter that crashes. The adapter is tests/dap/fakedap.py."""
import unittest
import debughost


class Launch(debughost.DebugHost):
    def run_to_end(self, mode=None, extra=()):
        self.launch_ini()
        out = self.run_editor(['bp %s 3' % self.src, *self.start(), 'wait-debug paused', 'print-debug',
                               'bp-clear', 'debug-continue', 'wait-debug ended', 'print-debug',
                               'print-console', *extra], mode=mode)
        return out

    def test_orders_of_launch_and_initialized(self):
        for mode in ('init-after-launch', 'init-early', 'launch-after-config', 'seq0'):
            with self.subTest(mode=mode):
                if self.log.exists():
                    self.log.unlink()
                out = self.run_to_end(mode)
                sessions = self.debug_lines(out)
                self.assertEqual(self.field(sessions[0], 'state'), 'paused', out)
                self.assertTrue(self.field(sessions[0], 'at').endswith('a.c:3'), out)
                self.assertEqual(self.field(sessions[1], 'state'), 'ended', out)
                self.assertEqual(self.field(sessions[1], 'exit'), '3', out)
                self.assertIn('info Program exited with code 3', out)
                reqs = [r.split(' ')[0] for r in self.requests()]
                # breakpoints go out after initialized and before configurationDone
                self.assertLess(reqs.index('setBreakpoints'), reqs.index('configurationDone'), reqs)
                self.assertLess(reqs.index('launch'), reqs.index('configurationDone'), reqs)
                self.assertEqual(reqs[0], 'initialize')
                self.assertEqual(reqs[-1], 'disconnect')

    def test_launch_arguments(self):
        self.launch_ini()
        self.run_to_end()
        args = self.args_sent()
        self.assertEqual(args['type'], 'fake')
        self.assertEqual(args['request'], 'launch')
        self.assertEqual(args['name'], 'Run')
        self.assertEqual(args['program'], (self.proj / 'scenario.json').as_posix())
        self.assertNotIn('noDebug', args)

    def test_approval_asked_once_with_the_command(self):
        self.launch_ini()
        out = self.run_editor(['debug-start Run', 'print-dialog', 'print-debug', 'dialog yes', 'wait-debug ended',
                               'debug-start Run', 'print-dialog', 'wait-debug ended', 'print-debug'])
        dialog = [line for line in out if line.startswith('dialog=')]
        self.assertEqual(dialog[0], 'dialog=Let Debug Fake run programs in proj?', out)
        text = out[out.index(dialog[0]) + 1]
        self.assertTrue(text.startswith('text=Fake Debugger will run '), text)
        self.assertIn('python3', text)
        self.assertIn('fakedap.py', text)
        self.assertIn('as you, with access to all your files', text)
        self.assertEqual(dialog[1], 'dialog=none', out)      # the second start does not ask
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'approval')
        self.assertEqual(self.field(sessions[-1], 'state'), 'ended')
        self.assertEqual(self.field(sessions[-1], 'session'), '2')

    def test_cancel_runs_nothing(self):
        self.launch_ini()
        out = self.run_editor(['debug-start Run', 'dialog no', 'wait 300', 'print-debug'])
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'ended', out)
        self.assertEqual(self.field(sessions[0], 'reason'), 'cancelled', out)
        self.assertFalse(self.log.exists(), 'the adapter never started')

    def test_run_without_debugging(self):
        self.launch_ini()
        out = self.run_editor(['bp %s 3' % self.src, *self.start(run=True), 'wait-debug ended', 'print-debug'])
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'noDebug'), '1')
        self.assertEqual(self.field(sessions[0], 'exit'), '3')
        self.assertTrue(self.args_sent()['noDebug'])
        reqs = [r.split(' ')[0] for r in self.requests()]
        self.assertNotIn('setBreakpoints', reqs)
        self.assertIn('configurationDone', reqs)

    def test_failed_launch_ends_the_session(self):
        self.launch_ini()
        out = self.run_editor([*self.start(), 'wait-debug ended', 'print-debug', 'print-console', 'print-toast'],
                              mode='launch-fail')
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'ended', out)
        self.assertIn('error the program could not be debugged: could not launch: no such program', out)
        self.assertIn('disconnect', ' '.join(self.requests()))

    def test_initialize_timeout(self):
        self.launch_ini()
        out = self.run_editor([*self.start(), 'wait-debug ended 15000', 'print-debug', 'print-console'],
                              mode='no-init-response', timeout=60)
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'ended', out)
        self.assertIn('error the debugger did not answer initialize in 10 s', out)

    def test_needs_debug_yes(self):
        exts = self.work / 'exts'
        folder = exts / 'rhun-tests/nodebug'
        folder.mkdir(parents=True)
        manifest = (debughost.EXTS / 'rhun-tests/debugfake/extension.ini').read_text()
        manifest = manifest.replace('name = debugfake', 'name = nodebug').replace('debug = yes', 'debug = no')
        manifest = manifest.replace('${extension}/../../../fakedap.py', str(debughost.ROOT / 'tests/dap/fakedap.py'))
        manifest = manifest.replace('run = ../../../debugfake.py', 'run = ' + str(debughost.ROOT / 'tests/dap/debugfake.py'))
        (folder / 'extension.ini').write_text(manifest)
        self.launch_ini()
        out = self.run_editor(['debug-start Run', 'print-dialog', 'print-debug', 'print-console'], exts=exts)
        self.assertIn('dialog=none', out)
        self.assertEqual(self.debug_lines(out), [])
        self.assertIn("error the debugger's extension does not declare debug = yes under [needs]", out)

    def test_unknown_type_and_missing_configuration(self):
        self.launch_ini('[Odd]\ntype = nosuch\n')
        out = self.run_editor(['debug-start Odd', 'debug-start Missing', 'print-console'])
        self.assertIn('error no installed extension provides a debugger of type nosuch', out)
        self.assertIn('error no configuration named Missing', out)

    def test_no_launch_ini(self):
        out = self.run_editor(['debug-start Run', 'print-console'])
        self.assertIn('error no launch configurations: add .rhun/launch.ini to the project', out)

    def test_adapter_error_output_in_the_console(self):
        out = self.run_to_end('stderr')
        self.assertIn('adapter fakedap: started', out)
        self.assertIn('adapter fakedap: second line', out)

    def test_adapter_crash(self):
        self.launch_ini()
        out = self.run_editor([*self.start(), 'wait-debug ended', 'print-debug', 'print-console'],
                              mode='crash-at=3')
        sessions = self.debug_lines(out)
        reason = sessions[0].split(' reason=')[1]
        self.assertTrue(reason.startswith('the debugger stopped unexpectedly (exit code 7): '
                                          'fakedap: crashing at step 3'), out)
        self.assertIn('adapter fakedap: crashing at step 3', out)

    def test_environment_and_folder(self):
        self.launch_ini()
        self.env['FAKEDAP_MODE'] = ''
        out = self.run_editor([*self.start(), 'wait-debug ended', 'print-debug'])
        pid = self.field(self.debug_lines(out)[0], 'pid')
        self.assertTrue(pid and pid != '0', out)
        self.assertIn('pid ' + pid, self.dap_log())


if __name__ == '__main__':
    unittest.main()
