#!/usr/bin/env python3
"""Problem patterns, matchers and the Problems store (tasks design 3.3, 4.3, 4.5; src/app/taskmatch.s,
problems.s, the line tap in term.s): the shared vectors of tests/data/patterns.txt through
print-pattern; the built-in matchers on recorded go, go vet, go test, clang, cargo, tsc and msbuild
output (tests/data/tasks); an inline matcher with steps, loop and character columns; lines as the
terminal shows them (escapes applied, wrapped rows joined, carriage returns overwritten); problems
replaced when the program runs again; marks on documents opened before and after."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

host = __import__('ext-host')
ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
DATA = ROOT / 'tests/data/tasks'
WINDOWS = os.name == 'nt'
CAT = 'cat'


class Patterns(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-task-patterns-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(host.CONFIG, encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(), TERM='xterm-256color')

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions, width=1000):
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', f'{width}x700', '--scale', '1',
                                 '--script', script.as_posix()], env=self.env, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8', errors='replace').splitlines()

    def files(self, *names, lines=20):
        for name in names:
            path = self.proj / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('\n'.join(f'line {i} word_{i} more' for i in range(1, lines + 1)) + '\n',
                            encoding='utf-8')

    def problems(self, out):
        prefix = 'problem path=' + self.proj.as_posix() + '/'
        return [line.replace(prefix, 'problem path=') for line in out if line.startswith('problem ')]

    def matched(self, matcher, fixture, *more):
        out = self.run_editor([f'term-run --title t --matcher {matcher} -- {CAT} {(DATA / fixture).as_posix()}',
                               'wait-terminal 1 ended', 'print-problems', *more])
        return out

    # --- patterns ---

    def test_shared_vectors(self):
        rows = []
        for line in (ROOT / 'tests/data/patterns.txt').read_text(encoding='utf-8').splitlines():
            if line.startswith('#'):
                continue
            rest, expected = line.rsplit('\t', 1)
            rows.append((rest, expected))
        out = self.run_editor(['print-pattern ' + rest for rest, _ in rows])
        self.assertEqual(len(out), len(rows), out)
        for (rest, expected), got in zip(rows, out):
            self.assertEqual(got, expected, rest)

    # --- built-in matchers on recorded output ---

    def test_go_build_vet_and_test(self):
        self.files('main.go', 'sub/s.go', 'sum_test.go')
        got = self.problems(self.matched('go', 'go.txt'))
        self.assertEqual(got, [
            'problem path=sub/s.go line=3 col=13 end=- severity=error code=- source=t message=cannot use "s" '
            '(untyped string constant) as int value in variable declaration',
            'problem path=main.go line=4 col=2 end=- severity=error code=- source=t message=declared and not used: x',
            'problem path=main.go line=4 col=7 end=- severity=error code=- source=t message=undefined: undefinedThing',
            'problem path=main.go line=5 col=6 end=- severity=error code=- source=t message=declared and not used: n',
            'problem path=main.go line=5 col=14 end=- severity=error code=- source=t message=cannot use "s" '
            '(untyped string constant) as int value in variable declaration',
            'problem path=sum_test.go line=8 col=0 end=- severity=error code=- source=t message=got 1, want 2'])

    def test_clang_through_its_colors(self):
        self.files('a.c')
        got = self.problems(self.matched('gcc', 'clang.txt'))
        self.assertEqual(got, [
            "problem path=a.c line=2 col=10 end=- severity=error code=- source=t message=use of undeclared "
            "identifier 'undefined_x'",
            "problem path=a.c line=3 col=14 end=- severity=warning code=- source=t message=adding 'int' to a "
            "string does not append to the string [-Wstring-plus-int]",
            'problem path=a.c line=3 col=14 end=- severity=info code=- source=t message=use array indexing to '
            'silence this warning',
            "problem path=a.c line=3 col=9 end=- severity=error code=- source=t message=incompatible pointer to "
            "integer conversion returning 'char *' from a function with result type 'int' [-Wint-conversion]"])

    def test_cargo_two_steps_through_its_colors(self):
        self.files('src/main.rs')
        got = self.problems(self.matched('rustc', 'cargo.txt'))
        self.assertEqual(got, ['problem path=src/main.rs line=3 col=20c end=- severity=error code=E0425 '
                               'source=t message=cannot find value `x` in this scope'])

    def test_tsc_both_formats(self):
        self.files('src/a.ts', 'src/b.ts')
        got = self.problems(self.matched('tsc', 'tsc.txt'))
        self.assertEqual(got, [
            "problem path=src/a.ts line=4 col=7c end=- severity=error code=TS2322 source=t message=Type "
            "'string' is not assignable to type 'number'.",
            "problem path=src/b.ts line=2 col=5c end=- severity=error code=TS2304 source=t message=Cannot "
            "find name 'foo'."])

    def test_msbuild_with_an_end(self):
        self.files('Program.cs')
        got = self.problems(self.matched('msbuild', 'msbuild.txt'))
        self.assertEqual(got, [
            "problem path=Program.cs line=10 col=5c end=- severity=warning code=CS0168 source=t message=The "
            "variable 'e' is declared but never used [/work/app.csproj]",
            "problem path=Program.cs line=12 col=9c end=12:13 severity=error code=CS0103 source=t message=The "
            "name 'nope' does not exist in the current context [/work/app.csproj]"])

    def test_footer_counts_the_problems(self):
        self.files('main.go', 'sub/s.go', 'sum_test.go')
        out = self.matched('go', 'go.txt', 'print-term')
        self.assertTrue(any(line.startswith('── t exited with code 0 after ') and
                            line.endswith(', 6 errors ──') for line in out), out)

    # --- an inline matcher ---

    def test_steps_loop_and_character_columns(self):
        (self.proj / 'ü.txt').write_text('aécd\nüb\nccc\n', encoding='utf-8')
        out = self.run_editor([f'term-run --title l --matcher-file {(DATA / "loop.matcher").as_posix()} -- '
                               f'{CAT} {(DATA / "loop.txt").as_posix()}', 'wait-terminal 1 ended', 'print-problems',
                               'open ' + (self.proj / 'ü.txt').as_posix(), 'wait 300', 'print-marks'])
        self.assertEqual(self.problems(out), [
            'problem path=ü.txt line=1 col=3c end=- severity=warning code=- source=l message=first',
            'problem path=ü.txt line=2 col=2c end=- severity=warning code=- source=l message=second'])
        # the third character of aécd is c (byte 4); the second of üb is b (byte 3)
        marks = [line for line in out if line.endswith(' first') or line.endswith(' second')]
        self.assertEqual(marks, ['1 4 1 6 warning problems:l first', '2 3 2 4 warning problems:l second'])

    # --- lines as the terminal shows them ---

    @unittest.skipIf(WINDOWS, 'POSIX shell')
    def test_wrapped_rows_and_carriage_returns(self):
        self.files('main.go')
        long = 'x' * 150
        out = self.run_editor([f"term-run --title w --matcher go --sh -- printf 'garbage\\rmain.go:1:2: {long}\\n'",
                               'wait-terminal 1 ended', 'print-problems'], width=500)
        self.assertEqual(self.problems(out), ['problem path=main.go line=1 col=2 end=- severity=error code=- '
                                              'source=w message=' + long])

    # --- the store ---

    def test_running_again_replaces_the_problems(self):
        self.files('main.go', 'sub/s.go', 'sum_test.go')
        out = self.run_editor([f'term-run --title t --matcher go -- {CAT} {(DATA / "go.txt").as_posix()}',
                               'wait-terminal 1 ended', 'term-restart 1', 'wait-terminal 1 ended 2',
                               'print-problems'])
        self.assertEqual(len(self.problems(out)), 6)

    def test_marks_on_documents_open_before_and_after(self):
        self.files('main.go', 'sub/s.go', 'sum_test.go')
        out = self.run_editor(['open ' + (self.proj / 'main.go').as_posix(),
                               f'term-run --title t --matcher go -- {CAT} {(DATA / "go.txt").as_posix()}',
                               'wait-terminal 1 ended', 'print-marks',
                               'open ' + (self.proj / 'sub/s.go').as_posix(), 'wait 300', 'print-marks'])
        marks = [line for line in out if 'problems:t' in line or line.startswith('errors=')]
        # "line 4 word_4 more": column 2 starts the word "ine", column 7 is a blank (one character)
        self.assertEqual(marks, [
            '4 2 4 5 error problems:t declared and not used: x',
            '4 7 4 8 error problems:t undefined: undefinedThing',
            '5 6 5 7 error problems:t declared and not used: n',
            '5 14 5 15 error problems:t cannot use "s" (untyped string constant) as int value in variable declaration',
            'errors=4 warnings=0',
            '3 13 3 14 error problems:t cannot use "s" (untyped string constant) as int value in variable declaration',
            'errors=1 warnings=0'])

    # --- the Problems tab ---

    def test_problems_tab_lists_files_and_goes_to_a_problem(self):
        (self.proj / 'main.go').write_text('package main\n\nfunc main() {\n\tx := undefinedThing\n'
                                          '\tvar n int = "s"\n}\n', encoding='utf-8')
        self.files('sub/s.go', 'sum_test.go')
        out = self.run_editor(['print-problems-tab',
                               f'term-run --title t --matcher go -- {CAT} {(DATA / "go.txt").as_posix()}',
                               'wait-terminal 1 ended', 'cmd toggle_problems', 'wait 100', 'print-problems-tab',
                               'print-state', 'key Down', 'key Down', 'key Down', 'key Down', 'key Return',
                               'wait 200', 'print-state'])
        self.assertEqual(out[0], 'tab=none')
        rows = [line for line in out if line.startswith('row ')]
        labels = [(r.split(' label=')[1].split(' desc=')[0].split(' badge=')[0]) for r in rows]
        self.assertEqual(labels, ['sub/s.go', 'cannot use "s" (untyped string constant) as int value in variable '
                                  'declaration', 'main.go', 'declared and not used: x', 'undefined: undefinedThing',
                                  'declared and not used: n', 'cannot use "s" (untyped string constant) as int value '
                                  'in variable declaration', 'sum_test.go', 'got 1, want 2'])
        self.assertIn('badge=4', rows[2])
        self.assertIn('desc=t  4:7', rows[4])
        states = [line for line in out if line.startswith('tabs=')]
        self.assertIn('focus=10', states[0])         # the tab has the keyboard
        # the fourth row: main.go's first problem, at line 4 byte column 2 (x, after a tab: column 5)
        self.assertIn('active=main.go line=4 col=5', states[1])


if __name__ == '__main__':
    unittest.main(verbosity=2)
