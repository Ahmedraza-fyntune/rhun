#!/usr/bin/env python3
"""The DAP wire (src/app/dapwire.s): messages written a byte at a time or several per write, bytes
outside the framing (shown as adapter: lines, then the next header is found), a header without
Content-Length, a body that is not JSON, a large message, a flood of output events handled across
frames, and a message over the 8 MB cap. The adapter is tests/dap/fakedap.py."""
import unittest
import debughost


class Framing(debughost.DebugHost):
    def full_run(self, mode, extra=(), timeout=60):
        self.launch_ini()
        return self.run_editor(['bp %s 3' % self.src, *self.start(), 'wait-debug paused', 'print-debug',
                                'bp-clear', 'debug-continue', 'wait-debug ended', 'print-debug', *extra],
                               mode=mode, timeout=timeout)

    def assert_normal(self, out):
        sessions = self.debug_lines(out)
        self.assertEqual(len(sessions), 2, out)
        self.assertEqual(self.field(sessions[0], 'state'), 'paused', out)
        self.assertTrue(self.field(sessions[0], 'at').endswith('a.c:3'), out)
        self.assertEqual(self.field(sessions[1], 'exit'), '3', out)

    def test_split_and_coalesced_writes(self):
        for mode in ('split', 'coalesce'):
            with self.subTest(mode=mode):
                self.assert_normal(self.full_run(mode))

    def test_junk_before_a_header(self):
        out = self.full_run('junk-stdout', ['print-console'])
        self.assert_normal(out)
        self.assertIn('adapter hello from the program', out)
        self.assertIn('adapter more junk', out)

    def test_header_without_length_ends_the_session(self):
        self.launch_ini()
        out = self.run_editor([*self.start(), 'wait-debug ended', 'print-debug'], mode='no-length')
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'ended', out)
        self.assertIn("reason=the debugger's output is not DAP (no Content-Length)", sessions[0])

    def test_body_that_is_not_json(self):
        self.launch_ini()
        out = self.run_editor([*self.start(), 'wait-debug ended', 'print-debug'], mode='bad-json')
        sessions = self.debug_lines(out)
        self.assertIn('reason=the debugger sent a message that is not JSON', sessions[0])

    def test_large_message(self):
        out = self.full_run('big=3000000', ['print-console'])
        self.assert_normal(out)
        big = [line for line in out if line.startswith('stdout BBBB')]
        self.assertEqual(len(big), 1, out[:20])
        self.assertEqual(len(big[0]), len('stdout ') + 4096)       # a console line is cut at 4 KiB

    def test_message_over_the_cap(self):
        self.launch_ini()
        out = self.run_editor([*self.start(), 'wait-debug ended', 'print-debug'], mode='big=9000000')
        sessions = self.debug_lines(out)
        self.assertIn('reason=the debugger sent a message over 8 MB', sessions[0])

    def test_flood_of_output(self):
        out = self.full_run('flood=3000', ['print-console'])
        self.assert_normal(out)
        flood = [line for line in out if line.startswith('stdout flood ')]
        self.assertEqual(len(flood), 3000)
        self.assertEqual(flood[-1], 'stdout flood 2999')

if __name__ == '__main__':
    unittest.main()
