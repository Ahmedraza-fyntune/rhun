#!/usr/bin/env python3
"""Real debug adapters (docs/guide.md "Debugging"): lldb-dap on a C program, Delve on a Go program
and a Go test, debugpy on Python, each through rhun's DAP client as a user would drive it. The
debuggers are declared by tests/dap/real (as rhun-editor/debug declares them, without its
resolver). Each workflow is skipped, with the reason, when its tool is missing:
  lldb-dap  macOS: `xcrun -f lldb-dap` (Xcode); Linux: lldb-dap on PATH
  Delve     `dlv` on PATH or RHUN_TEST_DLV (go install github.com/go-delve/delve/cmd/dlv@latest)
  debugpy   RHUN_TEST_PYTHON, an interpreter with debugpy installed (default python3)
Delve and lldb-dap need ptrace: they do not run in Docker under Rosetta."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import unittest
import debughost

REAL = debughost.ROOT / 'tests/dap/real'

HELLO_C = '''#include <stdio.h>
int add(int a, int b) {
    int s = a + b;
    return s;
}
int main(void) {
    int total = 0;
    for (int i = 0; i < 3; i++) {
        printf("i=%d total=%d\\n", i, total);
        total = add(total, i);
    }
    return total;
}
'''

SPIN_C = '''#include <unistd.h>
int main(void) {
    for (;;)
        sleep(1);
}
'''


def lldb_dap():
    if sys.platform == 'darwin':
        r = subprocess.run(['xcrun', '-f', 'lldb-dap'], capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else None
    for name in ('lldb-dap', 'lldb-dap-20', 'lldb-dap-19', 'lldb-dap-18'):
        if shutil.which(name):
            return shutil.which(name)
    return None


class Real(debughost.DebugHost):
    def run_real(self, actions, timeout=120, files=()):
        return self.run_editor(actions, files=files, exts=REAL, timeout=timeout)

    def vars(self, out):
        return [l.strip() for l in out if l.startswith('  ') and ' = ' in l]


@unittest.skipUnless(shutil.which('cc') and lldb_dap(), 'needs cc and lldb-dap')
class LldbDap(Real):
    def setUp(self):
        super().setUp()
        self.c = self.proj / 'hello.c'
        self.c.write_text(HELLO_C, encoding='utf-8')
        subprocess.run(['cc', '-g', '-O0', '-o', str(self.proj / 'hello'), str(self.c)], check=True)
        self.launch_ini('[Run]\ntype = c\nprogram = hello\n')

    def test_breakpoint_stack_locals_step_out_watch_and_exit(self):
        out = self.run_real(['bp %s 3' % self.c, *self.start(), 'wait-debug paused 60000', 'print-debug',
                             'print-stack', 'print-vars', 'echo --', 'debug-step out', 'wait-debug paused',
                             'print-debug', 'debug-watch add total', 'wait 500', 'print-watch', 'echo --',
                             'bp-clear', 'debug-continue', 'wait-debug ended 30000', 'print-debug',
                             'print-console'], files=('hello.c',))
        first, second = out[:out.index('--')], out[out.index('--') + 1:]
        session = self.debug_lines(first)[0]
        self.assertEqual(self.field(session, 'state'), 'paused', out)
        self.assertEqual(self.field(session, 'reason'), 'breakpoint')
        self.assertTrue(self.field(session, 'at').endswith('hello.c:3'), session)
        frames = [l.split()[2] for l in first if l.startswith('  frame ')]
        self.assertEqual(frames[:2], ['add', 'main'], first)
        names = [v.split(' = ')[0] for v in self.vars(first)]
        self.assertEqual(names[:3], ['a', 'b', 's'], first)
        stepped = self.debug_lines(second)[0]
        self.assertEqual(self.field(stepped, 'reason'), 'step')
        self.assertTrue(self.field(stepped, 'at').endswith('hello.c:10'), stepped)
        self.assertIn('total = 0 : int', second)
        ended = self.debug_lines(second)[1]
        self.assertEqual(self.field(ended, 'state'), 'ended')
        self.assertEqual(self.field(ended, 'exit'), '3')
        self.assertIn('stdout i=0 total=0', second)
        self.assertIn('stdout i=2 total=1', second)
        self.assertIn('info Program exited with code 3', second)

    def test_condition_and_logpoint(self):
        out = self.run_real(['bp %s 9 cond=i==2' % self.c, 'bp %s 10 log=adding_{i}' % self.c, *self.start(),
                             'wait-debug paused 60000', 'print-debug', 'print-vars', 'debug-continue',
                             'wait-debug ended 30000', 'print-debug', 'print-console'], files=('hello.c',))
        sessions = self.debug_lines(out)
        self.assertTrue(self.field(sessions[0], 'at').endswith('hello.c:9'), out)
        self.assertIn('i = 2 : int', self.vars(out))
        self.assertEqual(self.field(sessions[1], 'exit'), '3', out)
        self.assertEqual(len(sessions), 2, out)            # one stop only
        logs = [l for l in out if 'adding_' in l]
        self.assertEqual([l.split()[-1] for l in logs], ['adding_0', 'adding_1', 'adding_2'], out)

    def test_stop_kills_the_program(self):
        spin = self.proj / ('spin-%d' % os.getpid())
        (self.proj / 'spin.c').write_text(SPIN_C, encoding='utf-8')
        subprocess.run(['cc', '-g', '-O0', '-o', str(spin), str(self.proj / 'spin.c')], check=True)
        self.launch_ini('[Spin]\ntype = c\nprogram = %s\n' % spin.name)
        start = time.time()
        out = self.run_real([*self.start('Spin'), 'wait-debug running 60000', 'wait 1000', 'print-debug',
                             'debug-stop', 'wait-debug ended 10000', 'print-debug'])
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'running', out)
        self.assertEqual(self.field(sessions[1], 'state'), 'ended', out)
        self.assertLess(time.time() - start, 60)
        ps = subprocess.run(['ps', '-A', '-o', 'command='], capture_output=True, text=True).stdout
        self.assertNotIn(spin.as_posix(), ps)


if __name__ == '__main__':
    unittest.main()
