#!/usr/bin/env python3
"""The "tasks" feature of protocol 1.1 and rhun's task commands (tasks design 1.2, 1.5, 3.5): a fake
provider (the driver below) publishes tasks; rhun lists them in Run Task, runs the build group's
default on ctrl+shift+B after the one approval, runs dependencies first (in sequence, in parallel),
waits for a background task's ready line, leaves dependents unstarted when one fails, and answers
task-start and task-run with the task's TERM. Every line the driver gets goes to a log."""
import json
import os
from pathlib import Path
import unittest

host = __import__('ext-host')
WINDOWS = os.name == 'nt'

DRIVER = r'''import os
import sys
from pathlib import Path

log = open(Path(os.environ['RHUN_STATE']) / 'driver.log', 'ab', buffering=0)
inp = sys.stdin.buffer
out = sys.stdout.buffer
next_id = 1

def send(line, body=b''):
    global next_id
    out.write(str(next_id).encode() + b' ' + line.encode() + b'\n' + body)
    out.flush()
    next_id += 1

def rec(name, args, data=b''):
    return (name + (' ' + args if args else '') + f' {len(data)}\n').encode() + data

def task(task_id, label, cmd, extra=b'', form='shell'):
    cmd = cmd.encode()
    head = f'{task_id} {form} {len(label.encode())} {len(cmd)} 0 {len(extra)}\n'
    return head.encode() + label.encode() + cmd + extra

TASKS = [
    task('build', 'Build', 'echo building; exit 0', rec('group', 'build') + rec('default', '')),
    task('lint', 'Lint', 'echo lint-ok', rec('group', 'build')),
    task('fail', 'Fail', 'echo nope; exit 2'),
    task('serve', 'Serve', "echo starting; sleep 0.3; echo 'Serving HTTP on 0.0.0.0'; sleep 30",
         rec('ready', '', b'Serving HTTP on {_}')),
    task('smoke', 'Smoke', 'echo smoke-ran', rec('depends', 'sequence', b'serve')),
    task('chain', 'Chain', 'echo chain-done', rec('depends', 'sequence', b'lint build')),
    task('after', 'After', 'echo should-not-run', rec('depends', 'sequence', b'fail')),
    task('par', 'Par', 'echo par-done', rec('depends', 'parallel', b'lint build')),
    task('unit', 'Unit', 'echo testing', rec('group', 'test')),
]

def tasks_set(items):
    body = (str(len(items)) + '\n').encode() + b''.join(items)
    send('tasks-set ' + str(len(body)), body)

out.write((HELLO + '\n').encode())
out.flush()
while True:
    line = inp.readline()
    if not line:
        break
    log.write(line)
    words = line.split()
    if line.startswith(b'0 terminal-output '):
        log.write(inp.read(int(words[-1])))
    if line.startswith(b'0 bye'):
        break
    if line.startswith(b'0 ready '):
        tasks_set(TASKS)
    if not line.startswith(b'0 run '):
        continue
    name = words[2].decode().split('.', 1)[1]
    if name in ('chain', 'smoke', 'after', 'par', 'serve', 'build'):
        send('task-start ' + name)
    elif name == 'adhoc':
        d = task('adhoc', 'Adhoc', 'echo adhoc-ran', rec('depends', 'sequence', b'lint'))
        send('task-run ' + str(len(d)), d)
    elif name == 'dup':
        tasks_set([task('a', 'A', 'true'), task('a', 'A2', 'true')])
    elif name == 'nodep':
        tasks_set([task('a', 'A', 'true', rec('depends', 'sequence', b'lint'))])
    elif name == 'cycle':
        tasks_set([task('a', 'A', 'true', rec('depends', 'sequence', b'b')),
                   task('b', 'B', 'true', rec('depends', 'parallel', b'a'))])
    elif name == 'badpat':
        tasks_set([task('a', 'A', 'true', rec('ready', '', b'{nope}'))])
    elif name == 'missing':
        send('task-start nothing-here')
'''

COMMANDS = ('chain', 'smoke', 'after', 'par', 'serve', 'build', 'adhoc', 'dup', 'nodep', 'cycle', 'badpat',
            'missing')


@unittest.skipIf(WINDOWS, 'POSIX shell tasks')
class Tasks(unittest.TestCase):
    setUp = host.Host.setUp
    tearDown = host.Host.tearDown
    run_editor = host.Host.run_editor

    def driver(self, level='run', features='terminals tasks'):
        root = self.work / 'exts'
        folder = root / 't' / 'driver'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'extension.ini').write_text(
            'name = driver\nowner = t\ntitle = Driver\nversion = 1\nprotocol = 1\nruntime = python3\n'
            'run = main.py\non = startup\n[commands]\n' + ''.join(f'{c} = {c}\n' for c in COMMANDS) +
            f'[needs]\nterminal = {level}\n', encoding='utf-8')
        (folder / 'main.py').write_text('HELLO = ' + json.dumps('hello 1 ' + features) + '\n' + DRIVER,
                                        encoding='utf-8')
        return root

    def dlog(self):
        path = self.work / 'state/rhun/extensions/t--driver/driver.log'
        return path.read_bytes().decode('utf-8', errors='replace') if path.exists() else ''

    def go(self, actions, exts=None):
        return self.run_editor(drop_waits=True, exts=exts or self.driver(),
                               actions=['wait-ext driver running', 'wait 300', *actions])

    def allow(self):
        return ['wait 300', 'dialog yes', 'wait 300']

    def terms(self, out):
        return [line.lstrip('*') for line in out if ' kind=' in line]

    def started_order(self, log):
        return [line.split()[4] for line in log.splitlines() if line.startswith('0 terminal-started ')]

    # --- publishing ---

    def test_published_tasks_are_listed(self):
        out = self.go(['print-tasks'])
        self.assertIn('ok 1\n', self.dlog())
        self.assertEqual(out[0], 't/driver id=build group=build default=1 label=Build')
        self.assertEqual(len(out), 9)
        self.assertIn('t/driver id=smoke group=- default=0 label=Smoke', out)

    def test_a_bad_list_changes_nothing(self):
        out = self.go(['cmd t/driver.dup', 'wait 200', 'cmd t/driver.nodep', 'wait 200', 'cmd t/driver.cycle',
                       'wait 200', 'cmd t/driver.badpat', 'wait 200', 'print-tasks'])
        log = self.dlog()
        self.assertIn('error 2 syntax task 1: id listed twice\n', log)
        self.assertIn('error 3 syntax task 1: depends: no task "lint"\n', log)
        self.assertIn('error 4 syntax task 1: depends: a cycle\n', log)
        self.assertIn('error 5 syntax task 1: unknown field\n', log)
        self.assertEqual(len(out), 9)           # the published list stayed

    # --- running ---

    def test_build_task_key_runs_the_default_after_the_approval(self):
        out = self.go(['key ctrl+shift+b', 'print-dialog', *self.allow(), 'wait-terminal 1 ended',
                       'print-terminals'])
        self.assertEqual(out[0], 'dialog=Let Driver run programs in proj?')
        self.assertEqual(out[1], 'text=echo building; exit 0   in ~/proj')
        self.assertIn('term=1 kind=task owner=t/driver task=build state=exited code=0', '\n'.join(out))
        self.assertRegex(self.dlog(), r'0 terminal-started 1 \d+ build\n')

    def test_sequence_runs_dependencies_in_order(self):
        out = self.go(['cmd t/driver.chain', *self.allow(), 'wait-terminal 3 ended', 'wait 300',
                       'print-terminals'])
        log = self.dlog()
        self.assertRegex(log, r'ok 2 3\n')                    # the chain's own TERM
        self.assertEqual(self.started_order(log), ['lint', 'build', 'chain'])
        self.assertEqual(len(self.terms(out)), 3)

    def test_parallel_dependencies(self):
        self.go(['cmd t/driver.par', *self.allow(), 'wait-terminal 3 ended', 'wait 300'])
        order = self.started_order(self.dlog())
        self.assertEqual(sorted(order[:2]), ['build', 'lint'])
        self.assertEqual(order[2], 'par')

    def test_a_failing_dependency_stops_the_chain(self):
        out = self.go(['cmd t/driver.after', *self.allow(), 'wait-terminal 1 ended', 'wait 500',
                       'print-terminals', 'term-select 2', 'print-term'])
        log = self.dlog()
        self.assertEqual(self.started_order(log), ['fail'])
        self.assertIn('── not run: Fail failed ──', out)
        self.assertIn('task=after state=failed', '\n'.join(out))

    def test_a_background_dependency_is_ready_not_ended(self):
        out = self.go(['cmd t/driver.smoke', *self.allow(), 'wait-terminal 2 ended', 'wait 300',
                       'print-terminals', 'cmd t/driver.serve', 'wait 300'])
        log = self.dlog()
        self.assertEqual(self.started_order(log), ['serve', 'smoke'])
        self.assertRegex(log, r'0 task-ready 1 0 0\n')
        self.assertIn('task=serve state=running', '\n'.join(out))
        # starting it again while it runs: its TERM, not a second run
        self.assertRegex(log, r'ok 3 1\n')
        self.assertEqual(self.started_order(log), ['serve', 'smoke'])

    def test_task_run_with_a_published_dependency(self):
        self.go(['cmd t/driver.adhoc', *self.allow(), 'wait-terminal 2 ended', 'wait 300'])
        log = self.dlog()
        self.assertEqual(self.started_order(log), ['lint', 'adhoc'])
        self.assertIn('ok 2 2\n', log)

    def test_no_such_task(self):
        self.go(['cmd t/driver.missing', 'wait 300'])
        self.assertIn('error 2 notask no such published task\n', self.dlog())

    def test_run_task_lists_and_stop_task_stops(self):
        out = self.go(['cmd run_task', 'print-palette', 'key Escape', 'cmd t/driver.serve', *self.allow(),
                       'wait-term Serving', 'cmd stop_task', 'wait-terminal 1 ended', 'print-terminals'])
        palette = [line for line in out if line.startswith('item=') or line.startswith('row=')]
        joined = '\n'.join(out)
        self.assertIn('Build', joined)
        self.assertIn('task=serve state=stopped', joined)

    def test_needs_run(self):
        self.go(['print-tasks'], exts=self.driver(level='yes'))
        self.assertIn('error 1 needs terminal=run\n', self.dlog())

    def test_tasks_need_terminals(self):
        self.go(['print-tasks'], exts=self.driver(features='tasks'))
        log = self.dlog()
        self.assertNotIn('0 features', log)
        self.assertIn('error 1 unknown', log)


if __name__ == '__main__':
    unittest.main(verbosity=2)
