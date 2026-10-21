#!/usr/bin/env python3
"""Debug adapters reached over TCP (docs/guide.md "Debugging"): `transport = tcp` picks a free
loopback port for ${port}, starts the adapter and connects to it (as Delve needs); launch.ini's
`server = HOST:PORT` connects to an adapter that runs already and starts nothing. The adapter is
tests/dap/fakedap.py with --listen."""
import socket
import subprocess
import sys
import time
import unittest
import debughost

FAKEDAP = debughost.ROOT / 'tests/dap/fakedap.py'


class Transport(debughost.DebugHost):
    def tcp_ini(self, extra=''):
        self.scenario()
        self.launch_ini('[Run]\ntype = faketcp\nprogram = scenario.json\n' + extra)

    def run_to_end(self, mode=None):
        return self.run_editor(['bp %s 3' % self.src, *self.start(), 'wait-debug paused', 'print-debug',
                                'print-stack', 'bp-clear', 'debug-continue', 'wait-debug ended',
                                'print-debug', 'print-console'], mode=mode)

    def test_tcp_runs_a_session(self):
        self.tcp_ini()
        out = self.run_to_end()
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'paused', out)
        self.assertTrue(self.field(sessions[0], 'at').endswith('a.c:3'), out)
        self.assertEqual(self.field(sessions[1], 'state'), 'ended', out)
        self.assertEqual(self.field(sessions[1], 'exit'), '3', out)
        self.assertIn('info Program exited with code 3', out)
        log = self.dap_log()
        argv = [l for l in log if l.startswith('argv ')][0]
        port = int(argv.rsplit(':', 1)[1])
        self.assertTrue(0 < port < 65536, argv)
        self.assertIn('accepted', log)
        # what the adapter (or the program it starts) prints on its standard output is program
        # output, not protocol
        self.assertIn('stdout DAP server listening at: 127.0.0.1:%d' % port, out)
        reqs = [r.split(' ')[0] for r in self.requests()]
        self.assertEqual(reqs[0], 'initialize')
        self.assertEqual(reqs[-1], 'disconnect')

    def test_tcp_port_in_the_approval(self):
        self.tcp_ini()
        out = self.run_editor(['debug-start Run', 'print-dialog', 'dialog no', 'wait 200', 'print-debug'])
        text = [l for l in out if l.startswith('text=')][0]
        self.assertRegex(text, r'--listen 127\.0\.0\.1:[1-9][0-9]*')
        self.assertEqual(self.field(self.debug_lines(out)[0], 'reason'), 'cancelled')

    def test_tcp_adapter_listening_late(self):
        self.tcp_ini()
        out = self.run_to_end(mode='tcp-late=1500')
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'paused', out)
        self.assertEqual(self.field(sessions[1], 'exit'), '3', out)

    def test_tcp_adapter_exits_before_listening(self):
        self.tcp_ini()
        out = self.run_editor([*self.start(), 'wait-debug ended 5000', 'print-debug', 'print-console'],
                              mode='tcp-exit')
        reason = self.debug_lines(out)[0].split(' reason=')[1]
        self.assertTrue(reason.startswith('the debugger stopped unexpectedly (exit code 3): '
                                          'could not listen: address already in use'), out)
        self.assertIn('adapter could not listen: address already in use', out)

    def test_tcp_adapter_never_listening(self):
        self.tcp_ini()
        start = time.time()
        out = self.run_editor([*self.start(), 'print-debug', 'wait-debug ended 15000', 'print-debug'],
                              mode='tcp-never')
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'connecting', out)
        reason = sessions[1].split(' reason=')[1].split(' thread=')[0]
        self.assertRegex(reason, r'^the debugger did not accept a connection on 127\.0\.0\.1:[0-9]+ in 10 s$')
        self.assertGreater(time.time() - start, 9)

    def test_stop_while_connecting(self):
        self.tcp_ini()
        out = self.run_editor([*self.start(), 'wait 300', 'debug-stop', 'wait-debug ended 2000', 'print-debug'],
                              mode='tcp-never')
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'ended', out)
        self.assertEqual(self.field(sessions[0], 'reason'), 'stopped', out)

    def serve(self, mode=None):
        """a fake adapter already listening on a free port, as a debug server the user started"""
        s = socket.socket()
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
        s.close()
        env = dict(self.env)
        if mode:
            env['FAKEDAP_MODE'] = mode
        proc = subprocess.Popen([sys.executable, '-I', FAKEDAP.as_posix(), '--listen', '127.0.0.1:%d' % port],
                                env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.addCleanup(proc.stdout.close)
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)      # cleanups run last first: kill, wait, close
        proc.stdout.readline()          # listening
        return port

    def test_server_connects_without_starting_anything(self):
        for host in ('', '127.0.0.1:', 'localhost:'):
            with self.subTest(host=host):
                if self.log.exists():
                    self.log.unlink()
                port = self.serve()
                self.scenario()
                self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nserver = %s%d\n' % (host, port))
                out = self.run_editor(['bp %s 3' % self.src, 'debug-start Run', 'print-dialog', 'wait-debug paused',
                                       'print-debug', 'bp-clear', 'debug-continue', 'wait-debug ended',
                                       'print-debug'])
                self.assertIn('dialog=none', out)        # nothing runs, so nothing is asked
                sessions = self.debug_lines(out)
                self.assertEqual(self.field(sessions[0], 'state'), 'paused', out)
                self.assertEqual(self.field(sessions[1], 'exit'), '3', out)
                args = self.args_sent()
                self.assertNotIn('server', args)
                self.assertEqual(args['program'], (self.proj / 'scenario.json').as_posix())

    def test_server_that_is_not_there(self):
        s = socket.socket()
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
        s.close()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nserver = %d\n' % port)
        out = self.run_editor(['debug-start Run', 'wait 300', 'debug-stop', 'wait-debug ended 2000', 'print-debug'])
        self.assertEqual(self.field(self.debug_lines(out)[0], 'state'), 'ended', out)

    def test_bad_server_values(self):
        for value in ('abc:1', '127.0.0.1:', '1.2.3:80', '256.0.0.1:80', '70000', 'host:80'):
            with self.subTest(value=value):
                self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nserver = %s\n' % value)
                out = self.run_editor(['debug-start Run', 'wait 100', 'print-debug', 'print-console'])
                self.assertEqual(self.debug_lines(out), [], out)
                self.assertIn('error server must be PORT or HOST:PORT, with HOST localhost or an IPv4 address',
                              out)


if __name__ == '__main__':
    unittest.main()
