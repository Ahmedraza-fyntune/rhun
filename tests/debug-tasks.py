#!/usr/bin/env python3
"""launch.ini's before and after keys (docs/guide.md "Debugging"): the tasks group runs the before
task (tasks_run_named) and the launch goes on once it exits 0; a failing or unknown one stops the
launch; the after task runs when the session ends. A small task provider publishes the tasks next
to the fake debugger extension."""
import json
from pathlib import Path
import unittest
import debughost

DAP = debughost.ROOT / 'tests/dap'

DRIVER = r'''import os, sys
out, inp = sys.stdout.buffer, sys.stdin.buffer
def task(tid, label, cmd):
    head = f'{tid} shell {len(label)} {len(cmd.encode())} 0 0\n'
    return head.encode() + label.encode() + cmd.encode()
TASKS = [task('build', 'Build', 'echo built > built.txt'), task('fail', 'Fail', 'echo nope; exit 2'),
         task('cleanup', 'Cleanup', 'echo cleaned > cleaned.txt'),
         task('slowa', 'Slow A', 'sleep 1.5; echo a > a.txt'), task('slowb', 'Slow B', 'sleep 4; echo b > b.txt')]
out.write(b'hello 1 terminals tasks\n'); out.flush()
for line in inp:
    if line.startswith(b'0 ready '):
        body = (str(len(TASKS)) + '\n').encode() + b''.join(TASKS)
        out.write(b'1 tasks-set ' + str(len(body)).encode() + b'\n' + body); out.flush()
    if line.startswith(b'0 bye'):
        break
'''


class Tasks(debughost.DebugHost):
    def exts(self):
        """the fake debugger (its adapter by absolute path) and the task provider"""
        root = self.work / 'exts'
        fake = root / 'rhun-tests/debugfake'
        fake.mkdir(parents=True)
        ini = (DAP / 'exts/rhun-tests/debugfake/extension.ini').read_text(encoding='utf-8')
        ini = ini.replace('${extension}/../../../', DAP.as_posix() + '/').replace('../../../debugfake.py', 'debugfake.py')
        (fake / 'extension.ini').write_text(ini, encoding='utf-8')
        (fake / 'debugfake.py').write_text((DAP / 'debugfake.py').read_text(encoding='utf-8'), encoding='utf-8')
        driver = root / 't/driver'
        driver.mkdir(parents=True)
        (driver / 'extension.ini').write_text(
            'name = driver\nowner = t\ntitle = Driver\nversion = 1\nprotocol = 1\nruntime = python3\n'
            'run = main.py\non = startup\n[needs]\nterminal = run\n', encoding='utf-8')
        (driver / 'main.py').write_text(DRIVER, encoding='utf-8')
        return root

    def run_tasks(self, ini, actions):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\n' + ini)
        return self.run_editor(actions, exts=self.exts())

    def test_before_runs_first(self):
        out = self.run_tasks('before = build\n', ['wait 300', 'debug-start Run', 'wait 500', 'print-dialog',
                                                   'dialog yes', 'wait 1500', 'print-dialog', 'dialog yes',
                                                   'wait-debug ended', 'print-debug', 'print-console'])
        dialogs = [l for l in out if l.startswith('dialog=')]
        self.assertEqual(dialogs, ['dialog=Let Driver run programs in proj?',
                                   'dialog=Let Debug Fake run programs in proj?'], out)
        self.assertEqual((self.proj / 'built.txt').read_text().strip(), 'built')
        self.assertEqual(self.field(self.debug_lines(out)[0], 'exit'), '3', out)
        self.assertLess(out.index('info Running the prelaunch task build'), out.index('info Starting the debugger'))

    def test_a_failing_before_task_asks(self):
        out = self.run_tasks('before = fail\n', ['wait 300', 'debug-start Run', 'wait 500', 'dialog yes',
                                                  'wait 1500', 'print-dialog', 'dialog no', 'wait 200', 'print-debug',
                                                  'print-console'])
        dialog = [l for l in out if l.startswith('dialog=')][0]
        self.assertEqual(dialog, 'dialog=The prelaunch task failed', out)
        self.assertIn('text=fail did not succeed. Debug anyway?', out)
        self.assertIn('info Launch cancelled', out)
        self.assertEqual(self.debug_lines(out), [], out)
        self.assertFalse(self.log.exists(), 'the adapter never started')

    def test_debug_anyway_after_a_failing_before_task(self):
        out = self.run_tasks('before = fail\n', ['wait 300', 'debug-start Run', 'wait 500', 'dialog yes',
                                                  'wait 1500', 'dialog yes', 'wait 500', 'print-dialog', 'dialog yes',
                                                  'wait-debug ended', 'print-debug'])
        self.assertEqual(self.field(self.debug_lines(out)[-1], 'exit'), '3', out)

    def test_an_unknown_before_task(self):
        out = self.run_tasks('before = nosuch\n', ['wait 300', 'debug-start Run', 'wait 300', 'print-console'])
        self.assertIn("error the configuration's before task is not a task (or more than one task has that name)",
                      out)

    def test_stop_while_the_before_task_waits(self):
        out = self.run_tasks('before = build\n', ['wait 300', 'debug-start Run', 'wait 300', 'debug-stop',
                                                   'wait 200', 'print-console', 'print-debug'])
        self.assertIn('info Launch cancelled', out)
        self.assertEqual(self.debug_lines(out), [], out)

    def test_after_runs_when_the_session_ends(self):
        self.run_tasks('after = cleanup\n', ['wait 300', 'debug-start Run', 'wait 500', 'dialog yes',
                                              'wait-debug ended', 'wait 500', 'print-dialog', 'dialog yes',
                                              'wait 1500'])
        self.assertEqual((self.proj / 'cleaned.txt').read_text().strip(), 'cleaned')

    def test_debug_start_waits_while_a_launch_is_prepared(self):
        # review: an extension's debug-start during the before task replaced the launch's configuration
        state = self.work / 'state/rhun/extensions/rhun-tests--debugfake'
        state.mkdir(parents=True)
        program = self.scenario(name='other.json').as_posix()
        (state / 'mode.json').write_text(json.dumps({'start': [{'name': 'From ext', 'leaves': [
            ['s', 'type', 'fake'], ['s', 'program', program]]}]}), encoding='utf-8')
        out = self.run_tasks('before = slowa\n', ['wait 300', 'debug-start Run', 'wait 500', 'dialog yes',
                                                   'cmd rhun-tests/debugfake.start', 'wait 2500', 'print-dialog',
                                                   'dialog yes', 'wait-debug ended', 'print-debug'])
        log = (state / 'debugfake.log').read_text(encoding='utf-8').splitlines()
        self.assertIn('error 1 busy a launch is being prepared', log)
        self.assertEqual([self.field(l, 'name') for l in self.debug_lines(out)], ['Run'], out)

    def test_an_abandoned_launchs_task_does_not_continue_the_next(self):
        # review: A's before task ending went on with B's launch before B's own task was done
        self.scenario()
        self.launch_ini('[A]\ntype = fake\nprogram = scenario.json\nbefore = slowa\n'
                        '[B]\ntype = fake\nprogram = scenario.json\nbefore = slowb\n')
        out = self.run_editor(['wait 300', 'debug-start A', 'wait 300', 'dialog yes', 'wait 200', 'debug-stop',
                               'debug-start B', 'wait 2500', 'print-debug', 'echo --', 'wait 3000', 'dialog yes',
                               'wait-debug ended', 'print-debug'], exts=self.exts())
        first, second = out[:out.index('--')], out[out.index('--') + 1:]
        self.assertEqual(self.debug_lines(first), [], first)
        self.assertEqual([self.field(l, 'name') for l in self.debug_lines(second)], ['B'], second)
        self.assertTrue((self.proj / 'b.txt').exists())


if __name__ == '__main__':
    unittest.main()
