#!/usr/bin/env python3
"""A program with several threads (docs/guide.md "Debugging"): a stop on a worker thread lists that
thread with its frames even when the adapter's thread list leaves it out (lldb-dap does at the
first stop), Continue names the stopped thread, thread events while paused fetch the list again,
another thread can be focused, a thread that exited is not the one Pause names, and a continued
event for another thread alone (allThreadsContinued false) keeps the stop."""
import json
import unittest
import debughost

RUN = '[Run]\ntype = fake\nprogram = scenario.json\n'


class Threads(debughost.DebugHost):
    def worker_steps(self, **extra):
        a = self.src.as_posix()
        worker = {'file': a, 'line': 2, 'function': 'add', 'thread': 2, 'locals': {'a': 1, 'b': 2}}
        worker.update(extra)
        return [{'file': a, 'line': 6, 'function': 'main', 'locals': {'total': 0}},
                worker,
                {'file': a, 'line': 3, 'function': 'add', 'thread': 2, 'locals': {'s': 3}},
                {'file': a, 'line': 9, 'function': 'main', 'locals': {'total': 3}}]

    def requests_of(self, command):
        res = []
        for line in self.requests():
            name, _, args = line.partition(' ')
            if name == command:
                res.append(json.loads(args or '{}'))
        return res

    def stack_lines(self, out):
        return [l for l in out if l.startswith('thread ') or l.startswith('  frame ')]

    def test_a_worker_stop_left_out_of_the_list_still_shows_and_continues(self):
        self.scenario(self.worker_steps())
        self.launch_ini(RUN)
        out = self.run_editor(['bp %s 2' % self.src.as_posix(), *self.start(), 'wait-debug paused',
                               'wait 500', 'print-debug', 'print-stack', 'echo --', 'debug-continue',
                               'wait-debug ended', 'wait 300', 'print-debug'], mode='threads,lldb-threads')
        first, second = out[:out.index('--')], out[out.index('--') + 1:]
        session = self.debug_lines(first)[0]
        self.assertEqual(self.field(session, 'state'), 'paused', first)
        self.assertEqual(self.field(session, 'thread'), '2', first)
        stack = self.stack_lines(first)
        self.assertIn('thread 2 Thread 2 *', stack, first)
        self.assertTrue(any(l.startswith('  frame 0 add ') and l.endswith('a.c:2 *') for l in stack), stack)
        # the adapter's list had only "Thread 1": the stopped thread is still the one continued
        self.assertEqual([r.get('threadId') for r in self.requests_of('continue')], [2], self.dap_log())
        session = self.debug_lines(second)[0]
        self.assertEqual((self.field(session, 'state'), self.field(session, 'exit')), ('ended', '3'), second)

    def test_a_thread_started_while_paused_is_listed_and_can_be_focused(self):
        self.scenario(self.worker_steps(threadStarted=3))
        self.launch_ini(RUN)
        out = self.run_editor(['bp %s 2' % self.src.as_posix(), *self.start(), 'wait-debug paused',
                               'wait 600', 'print-stack', 'echo --', 'debug-thread 1', 'wait 500',
                               'print-debug', 'print-stack', 'print-vars', 'echo --', 'debug-continue',
                               'wait-debug ended'], mode='threads')
        first = out[:out.index('--')]
        second = out[out.index('--') + 1:len(out) - out[::-1].index('--') - 1]
        self.assertGreaterEqual(len(self.requests_of('threads')), 2, self.dap_log())
        self.assertEqual([l for l in self.stack_lines(first) if l.startswith('thread ')],
                         ['thread 1 main', 'thread 2 worker2 *', 'thread 3 worker3'], first)
        # thread 1 focused: its stack, its frame's scopes, and Continue names it
        self.assertEqual(self.field(self.debug_lines(second)[0], 'thread'), '1', second)
        self.assertIn(1, [r.get('threadId') for r in self.requests_of('stackTrace')], self.dap_log())
        stack = self.stack_lines(second)
        self.assertIn('thread 1 main *', stack, second)
        self.assertTrue(any(l.startswith('  frame 0 wait1') for l in stack), stack)
        self.assertTrue(any('waiting' in l for l in second), second)
        self.assertEqual([r.get('threadId') for r in self.requests_of('continue')], [1], self.dap_log())

    def test_return_on_a_call_stack_thread_row_focuses_it(self):
        self.scenario(self.worker_steps())
        self.launch_ini(RUN)
        out = self.run_editor(['bp %s 2' % self.src.as_posix(), *self.start(), 'wait-debug paused', 'wait 500',
                               'print-debug-tree stack', 'view-focus debug.callstack', 'key Down', 'key Down',
                               'key Return', 'wait 500', 'print-debug', 'print-debug-tree stack'], mode='threads')
        rows = [l for l in out if l.startswith('row ')]
        self.assertIn('id=s1/t1 label=main', rows[1])
        self.assertIn('id=s1/t2 label=worker2', rows[2])
        self.assertEqual(self.field(self.debug_lines(out)[0], 'thread'), '1', out)
        after = rows[len(rows) // 2:]
        self.assertTrue(any('id=s1/f0 label=wait1' in l for l in after), after)

    def test_pause_after_the_remembered_thread_exited_names_a_live_one(self):
        a = self.src.as_posix()
        self.scenario([{'file': a, 'line': 2, 'function': 'add', 'thread': 2},
                       {'file': a, 'line': 3, 'function': 'add', 'thread': 1, 'threadExit': 2},
                       {'file': a, 'line': 8, 'function': 'main', 'block': True},
                       {'file': a, 'line': 9, 'function': 'main'}])
        self.launch_ini(RUN)
        out = self.run_editor([*self.start(), 'wait-debug running', 'wait 500', 'debug-pause',
                               'wait-debug paused 5000', 'wait 300', 'print-debug'], mode='threads')
        session = self.debug_lines(out)[0]
        self.assertEqual(self.field(session, 'state'), 'paused', out)
        self.assertEqual([r.get('threadId') for r in self.requests_of('pause')], [1], self.dap_log())

    def test_another_thread_continuing_alone_keeps_the_stop(self):
        self.scenario(self.worker_steps(continuedOther=1))
        self.launch_ini(RUN)
        out = self.run_editor(['bp %s 2' % self.src.as_posix(), *self.start(), 'wait-debug paused',
                               'wait 600', 'print-debug', 'print-stack', 'echo --', 'debug-continue',
                               'wait-debug ended', 'print-debug'], mode='threads,single-continue')
        first, second = out[:out.index('--')], out[out.index('--') + 1:]
        session = self.debug_lines(first)[0]
        self.assertEqual((self.field(session, 'state'), self.field(session, 'thread')), ('paused', '2'), first)
        self.assertTrue(any(l.startswith('  frame 0 add ') for l in self.stack_lines(first)), first)
        self.assertEqual(self.field(self.debug_lines(second)[0], 'state'), 'ended', second)


if __name__ == '__main__':
    unittest.main()
