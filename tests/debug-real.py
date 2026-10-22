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

THREAD_C = '''#include <pthread.h>
#include <stdio.h>
static int work(int n) {
    int r = n * 2;
    return r;
}
static void *worker(void *arg) {
    printf("worker %d\\n", work(21));
    return 0;
}
int main(void) {
    pthread_t t;
    pthread_create(&t, 0, worker, 0);
    pthread_join(t, 0);
    return 7;
}
'''

SPIN_C = '''#include <unistd.h>
int main(void) {
    for (;;)
        sleep(1);
}
'''


MAIN_GO = '''package main

import (
	"fmt"
	"os"
	"sync"
)

type Point struct {
	X, Y int
	Name string
}

func add(a, b int) int {
	s := a + b
	return s
}

func main() {
	p := Point{X: 1, Y: 2, Name: "pt"}
	m := map[string]int{"one": 1, "two": 2}
	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(n int) { defer wg.Done(); _ = n * 2 }(i)
	}
	wg.Wait()
	total := add(p.X, m["two"])
	fmt.Println("total", total)
	os.Exit(total)
}
'''

CALC_TEST_GO = '''package main

import "testing"

func TestAdd(t *testing.T) {
	if got := add(1, 2); got != 3 {
		t.Fatalf("add = %d", got)
	}
}

func TestOther(t *testing.T) {
	t.Log("other")
}
'''

APP_PY = '''class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y


def add(a, b):
    s = a + b
    return s


def main():
    d = {'one': 1, 'two': 2}
    items = list(range(500))
    p = Point(1, 2)
    total = add(p.x, d['two'])
    print('total', total)
    if total == 3:
        raise ValueError('three')


main()
'''

INPUT_PY = '''name = input('name? ')
print('hello', name)
'''


def dlv():
    path = os.environ.get('RHUN_TEST_DLV') or shutil.which('dlv')
    return path if path and os.access(path, os.X_OK) and shutil.which('go') else None


def debugpy_python():
    python = os.environ.get('RHUN_TEST_PYTHON', 'python3')
    r = subprocess.run([python, '-c', 'import debugpy'], capture_output=True)
    return shutil.which(python) if r.returncode == 0 else None


def lldb_dap():
    if sys.platform == 'darwin':
        r = subprocess.run(['xcrun', '-f', 'lldb-dap'], capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else None
    for name in ('lldb-dap', 'lldb-dap-20', 'lldb-dap-19', 'lldb-dap-18'):
        if shutil.which(name):
            return shutil.which(name)
    return None


# Ubuntu's lldb-dap asks https://debuginfod.ubuntu.com (its default server-urls, DEBUGINFOD_URLS or
#   not) for the debug info of the libraries the program loads, and answers launch only after: 90 s,
#   the debuginfod timeout, on the GitHub runners. The tests turn the lookups off
NO_DEBUGINFOD = ('' if sys.platform == 'darwin' else
                 'initCommands = "?settings clear plugin.symbol-locator.debuginfod.server-urls"\n')


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
        self.launch_ini('[Run]\ntype = c\nprogram = hello\n' + NO_DEBUGINFOD)

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

    def test_a_worker_thread_stop_and_continue(self):
        # lldb-dap's first thread list leaves the worker out: it is listed anyway, with its frames,
        #   and Continue names it
        src = self.proj / 'thread.c'
        src.write_text(THREAD_C, encoding='utf-8')
        subprocess.run(['cc', '-g', '-O0', '-pthread', '-o', str(self.proj / 'thread'), str(src)], check=True)
        self.launch_ini('[Thread]\ntype = c\nprogram = thread\n' + NO_DEBUGINFOD)
        out = self.run_real(['bp %s 4' % src, *self.start('Thread'), 'wait-debug paused 60000', 'wait 500',
                             'print-debug', 'print-stack', 'print-vars', 'echo --', 'debug-continue',
                             'wait-debug ended 30000', 'print-debug'], files=('thread.c',))
        first, second = out[:out.index('--')], out[out.index('--') + 1:]
        session = self.debug_lines(first)[0]
        self.assertEqual(self.field(session, 'state'), 'paused', out)
        thread = self.field(session, 'thread')
        focused = [l for l in first if l.startswith('thread %s ' % thread)]
        self.assertTrue(focused and focused[0].endswith(' *'), first)
        frames = [l.split()[2] for l in first if l.startswith('  frame ')]
        self.assertEqual(frames[:2], ['work', 'worker'], first)
        self.assertIn('n', [v.split(' = ')[0] for v in self.vars(first)], first)
        ended = self.debug_lines(second)[0]
        self.assertEqual((self.field(ended, 'state'), self.field(ended, 'exit')), ('ended', '7'), second)

    def test_stop_kills_the_program(self):
        spin = self.proj / ('spin-%d' % os.getpid())
        (self.proj / 'spin.c').write_text(SPIN_C, encoding='utf-8')
        subprocess.run(['cc', '-g', '-O0', '-o', str(spin), str(self.proj / 'spin.c')], check=True)
        self.launch_ini('[Spin]\ntype = c\nprogram = %s\n' % spin.name + NO_DEBUGINFOD)
        start = time.time()
        out = self.run_real([*self.start('Spin'), 'wait-debug running 60000', 'wait 1000', 'print-debug',
                             'debug-stop', 'wait-debug ended 10000', 'print-debug'])
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'running', out)
        self.assertEqual(self.field(sessions[1], 'state'), 'ended', out)
        self.assertLess(time.time() - start, 60)
        ps = subprocess.run(['ps', '-A', '-o', 'command='], capture_output=True, text=True).stdout
        self.assertNotIn(spin.as_posix(), ps)


@unittest.skipUnless(dlv(), 'needs go and dlv (RHUN_TEST_DLV or on PATH)')
class Delve(Real):
    def setUp(self):
        super().setUp()
        self.src.unlink()                   # the harness's a.c: Go refuses C files without cgo
        (self.proj / 'go.mod').write_text('module example.com/hello\n\ngo 1.21\n', encoding='utf-8')
        self.main = self.proj / 'main.go'
        self.main.write_text(MAIN_GO, encoding='utf-8')
        self.test = self.proj / 'calc_test.go'
        self.test.write_text(CALC_TEST_GO, encoding='utf-8')
        # Delve on PATH; Go's caches outlive the test (a fresh one rebuilds the standard library)
        cache = Path(os.environ.get('TMPDIR', '/tmp')) / 'rhun-test-go'
        self.env['PATH'] = str(Path(dlv()).parent) + os.pathsep + self.env['PATH']
        self.env['GOCACHE'] = str(cache / 'cache')
        self.env['GOPATH'] = str(cache / 'path')
        self.env['GOFLAGS'] = '-p=2'

    def test_program_goroutines_struct_map_step_into_exit_code(self):
        self.launch_ini('[Run]\ntype = go\nprogram = ${project}\n')
        out = self.run_real(['bp %s 28' % self.main, *self.start(), 'wait-debug paused 120000', 'print-debug',
                             'print-stack', 'debug-expand Locals/p', 'debug-expand Locals/m', 'wait 1000',
                             'print-vars', 'echo --', 'debug-step into', 'wait-debug paused', 'print-debug',
                             'bp-clear', 'debug-continue', 'wait-debug ended 30000', 'print-debug',
                             'print-console'], timeout=240, files=('main.go',))
        first, second = out[:out.index('--')], out[out.index('--') + 1:]
        session = self.debug_lines(first)[0]
        self.assertTrue(self.field(session, 'at').endswith('main.go:28'), out)
        threads = [l for l in first if l.startswith('thread ')]
        self.assertGreater(len(threads), 1, first)          # goroutines are threads
        self.assertIn('main.main', threads[0])
        variables = self.vars(first)
        for line in ('X = 1 : int', 'Y = 2 : int', 'Name = "pt" : string', '"two" = 2 : string: int'):
            self.assertIn(line, variables)
        stepped = self.debug_lines(second)[0]
        self.assertEqual(self.field(stepped, 'reason'), 'step')
        self.assertTrue(self.field(stepped, 'at').endswith('main.go:14'), stepped)
        ended = self.debug_lines(second)[1]
        self.assertEqual(self.field(ended, 'exit'), '3', second)
        self.assertIn('stdout total 3', second)              # the program's own output

    def test_one_test_in_test_mode(self):
        self.launch_ini('[Test]\ntype = go\nmode = test\nprogram = ${project}\nargs = -test.run ^TestAdd$ -test.v\n')
        out = self.run_real(['bp %s 6' % self.test, *self.start('Test'), 'wait-debug paused 120000',
                             'print-debug', 'print-stack', 'bp-clear', 'debug-continue', 'wait-debug ended 30000',
                             'print-debug', 'print-console'], timeout=240, files=('calc_test.go',))
        sessions = self.debug_lines(out)
        self.assertTrue(self.field(sessions[0], 'at').endswith('calc_test.go:6'), out)
        self.assertTrue(any('.TestAdd ' in l for l in out if l.startswith('  frame 0')), out)
        self.assertEqual(self.field(sessions[1], 'exit'), '0', out)
        self.assertTrue(any('--- PASS: TestAdd' in l for l in out), out)
        self.assertFalse(any('TestOther' in l for l in out), out)


@unittest.skipUnless(debugpy_python(), 'needs a python with debugpy (RHUN_TEST_PYTHON)')
class Debugpy(Real):
    def setUp(self):
        super().setUp()
        self.app = self.proj / 'app.py'
        self.app.write_text(APP_PY, encoding='utf-8')

    def ini(self, console='internalConsole', program='app.py'):
        self.launch_ini('[Run]\ntype = python\nprogram = %s\npython = %s\nconsole = %s\n'
                        % (program, debugpy_python(), console))

    def test_locals_eval_uncaught_exception_exit_code(self):
        self.ini()
        out = self.run_real(['bp %s 17' % self.app, 'exc-filter python uncaught 1', *self.start(),
                             'wait-debug paused 60000', 'print-debug', 'print-stack', 'debug-expand Locals/d',
                             'debug-expand Locals/p', 'wait 1500', 'print-vars', 'debug-eval total * 10', 'wait 500',
                             'bp-clear', 'debug-continue', 'wait-debug paused 30000', 'print-debug',
                             'debug-continue', 'wait-debug ended 30000', 'print-debug', 'print-console'],
                            files=('app.py',))
        sessions = self.debug_lines(out)
        self.assertTrue(self.field(sessions[0], 'at').endswith('app.py:17'), out)
        frames = [l.split()[2] for l in out if l.startswith('  frame ')]
        self.assertEqual(frames[:2], ['main', '<module>'], out)
        variables = self.vars(out)
        for line in ("'two' = 2 : int", 'x = 1 : int', 'y = 2 : int', 'total = 3 : int'):
            self.assertIn(line, variables)
        self.assertIn('result 30', out)
        self.assertEqual(self.field(sessions[1], 'reason'), 'exception', out)
        self.assertTrue(self.field(sessions[1], 'at').endswith('app.py:19'), out)
        self.assertIn('error ValueError: three', out)
        self.assertEqual(self.field(sessions[2], 'exit'), '1', out)
        self.assertIn('stdout total 3', out)

    def test_integrated_terminal_reads_input(self):
        (self.proj / 'ask.py').write_text(INPUT_PY, encoding='utf-8')
        self.ini('integratedTerminal', 'ask.py')
        out = self.run_real([*self.start(), 'wait-term name?', 'type rhun', 'key Return', 'wait-term hello rhun',
                             'wait-debug ended 30000', 'print-terminals', 'print-term', 'print-debug'])
        self.assertTrue(any('hello rhun' in l for l in out), out)
        self.assertTrue(any('kind=terminal' in l for l in out), out)
        self.assertEqual(self.field(self.debug_lines(out)[0], 'exit'), '0', out)


if __name__ == '__main__':
    unittest.main()
