#!/usr/bin/env python3
"""The test explorer with rhun-editor/tests and the real tools: go test and cargo test run through
test-exec in projects copied from the extension's fixtures. TESTS_DIR=PATH names a checkout of
rhun-editor/tests (built here with go build); without it, or without go (cargo), the tests skip.

Each run gets its own HOME and config; the Go build cache and the Rust toolchains stay the user's
(GOCACHE, RUSTUP_HOME, CARGO_HOME), so the tools find what they have."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
SRC = os.environ.get('TESTS_DIR')
TARGET = 'windows-x64' if os.name == 'nt' else 'macos-arm64' if sys.platform == 'darwin' else 'linux-x86_64'
CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
GO = 'go:example.com/demo'
CARGO = 'cargo:demo'


def tool_env(name, default):
    """a tool's own folder from the real environment (go env, rustup's default)"""
    if os.environ.get(name):
        return os.environ[name]
    if name == 'GOCACHE' and shutil.which('go'):
        return subprocess.run(['go', 'env', 'GOCACHE'], capture_output=True, text=True).stdout.strip()
    return default


@unittest.skipUnless(SRC, 'TESTS_DIR names no checkout of rhun-editor/tests')
class RealTools(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('go'):              # the extension is built with go (both tests need it)
            raise unittest.SkipTest('no go on PATH')
        cls.tmp = tempfile.TemporaryDirectory(prefix='rhun-tests-real-')
        cls.work = Path(cls.tmp.name).resolve()
        ext = cls.work / 'exts/rhun-editor/tests'
        (ext / 'bin').mkdir(parents=True)
        shutil.copy(Path(SRC) / 'extension.ini', ext / 'extension.ini')
        exe = ext / 'bin' / ('tests-' + TARGET + ('.exe' if os.name == 'nt' else ''))
        r = subprocess.run(['go', 'build', '-o', str(exe), '.'], cwd=SRC, capture_output=True,
                           env=dict(os.environ, CGO_ENABLED='0'), timeout=600)
        if r.returncode != 0:
            raise unittest.SkipTest('go build failed: ' + r.stderr.decode(errors='replace')[-500:])
        home = Path.home()
        cls.tools = {'GOCACHE': tool_env('GOCACHE', ''), 'RUSTUP_HOME': tool_env('RUSTUP_HOME', str(home / '.rustup')),
                     'CARGO_HOME': tool_env('CARGO_HOME', str(home / '.cargo'))}

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        self.case = Path(tempfile.mkdtemp(dir=self.work))
        self.proj = self.case / 'proj'
        cfg = self.case / 'config/rhun/config'
        cfg.parent.mkdir(parents=True)
        cfg.write_text(CONFIG, encoding='utf-8')

    def fixture(self, name):
        shutil.copytree(Path(SRC) / 'tests/fixtures' / name, self.proj)

    def run_editor(self, actions, timeout=400):
        env = dict(os.environ, HOME=self.case.as_posix(), XDG_CONFIG_HOME=(self.case / 'config').as_posix(),
                   XDG_STATE_HOME=(self.case / 'state').as_posix(), XDG_DATA_HOME=(self.case / 'data').as_posix(),
                   TMPDIR=self.case.as_posix())
        env.update({k: v for k, v in self.tools.items() if v})
        script = self.case / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', *actions, 'quit']) + '\n', encoding='utf-8')
        r = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', '1000x600', '--scale', '1',
                            '--extensions', str(self.work / 'exts'), '--script', script.as_posix()],
                           env=env, capture_output=True, timeout=timeout)
        self.assertEqual(r.returncode, 0, r.stderr.decode(errors='replace')[-2000:])
        return [l.strip() for l in r.stdout.decode('utf-8', errors='replace').splitlines()]

    def item(self, out, ident):
        hits = [l for l in out if (' id=' + ident + ' ') in l]
        self.assertTrue(hits, (ident, out))
        return hits[-1]

    @unittest.skipUnless(shutil.which('go'), 'no go on PATH')
    def test_go(self):
        self.fixture('godemo')
        (self.proj / 'broken').mkdir()
        (self.proj / 'broken/broken_test.go').write_text(
            'package broken\n\nimport "testing"\n\nfunc TestX(t *testing.T) { undefined() }\n', encoding='utf-8')
        calc = self.proj / 'calc'
        out = self.run_editor([
            'open ' + (calc / 'calc_test.go').as_posix(), 'cmd testing', 'wait-test-items 2',
            'test-expand tests gomod:example.com/demo', 'wait-test-items 4', 'test-expand tests %s/calc' % GO,
            'test-expand tests %s/broken' % GO, 'wait-test-items 8', 'wait 300', 'echo @found', 'print-tests all',
            'cmd test_run_all', 'wait 800', 'dialog yes', 'wait-tests', 'echo @ran', 'print-tests all',
            'print-test-result tests %s/calc.TestGreet' % GO, 'print-test-result tests %s/broken' % GO,
            'print-gutter', 'cmd test_coverage_all', 'wait-tests', 'print-coverage ' + (calc / 'calc.go').as_posix(),
            'test-select tests %s/calc.TestSkip' % GO, 'test-action run', 'wait 500', 'wait-tests', 'print-test-runs'])
        found = out[out.index('@found'):out.index('@ran')]
        # discovery: packages and their tests, with ranges, from the source
        self.assertIn('notrun TestAdd id=%s/calc.TestAdd kind=test ms=- range=5:1-14:2' % GO, found)
        self.assertIn('notrun TestX id=%s/broken.TestX kind=test ms=- range=5:1-5:41' % GO, found)
        ran = out[out.index('@ran'):]
        # results: subtests found while running, failures, a skip, a package that does not build
        self.assertTrue(self.item(ran, GO + '/calc.TestAdd').startswith('failed TestAdd '))
        self.assertTrue(self.item(ran, GO + '/calc.TestAdd/case').startswith('passed case '))
        self.assertTrue(self.item(ran, GO + '/calc.TestAdd/case#01').startswith('failed case#01 '))
        self.assertTrue(self.item(ran, GO + '/calc.TestSkip').startswith('skipped TestSkip '))
        self.assertTrue(self.item(ran, GO + '/broken').startswith('errored broken '))
        greet = [l for l in out if l.startswith('message=Greet mismatch')]
        self.assertTrue(greet and greet[0].endswith(
            'calc_test.go:20:1 expected=Hello, rhun!\\nWelcome. actual=Hello, rhun'), out)
        self.assertTrue([l for l in out if l.startswith('message=undefined: undefined at=') and
                         l.endswith('broken_test.go:5:28')], out)
        self.assertTrue([l for l in out if l.startswith('output=') and '[build failed]' in l], out)
        # the open file's glyphs, and coverage from go test -coverprofile
        self.assertIn('line=5 glyph=failed item=%s/calc.TestAdd' % GO, out)
        self.assertIn('line=24 glyph=skipped item=%s/calc.TestSkip' % GO, out)
        self.assertIn('covered=5 partial=1 missed=2 lines=3:C,4:P,5:M,6:M,7:C,10:C,11:C,12:C', out)
        runs = [l for l in out if l.startswith('run=')]
        self.assertEqual(len(runs), 3, out)
        self.assertIn('profile=coverage state=ended', runs[1])
        # one test again: it and its package (which passes)
        self.assertIn('profile=run state=ended passed=1 failed=0 errored=0 skipped=1 notrun=0', runs[2])

    @unittest.skipUnless(shutil.which('cargo'), 'no cargo on PATH')
    def test_cargo(self):
        self.fixture('rsdemo')
        lib = self.proj / 'src/lib.rs'
        out = self.run_editor([
            'open ' + lib.as_posix(), 'cmd testing', 'wait-test-items 2', 'test-expand tests ' + CARGO,
            'wait-test-items 4', 'wait 300', 'echo @found', 'print-tests all',
            'cmd test_run_all', 'wait 800', 'dialog yes', 'wait-tests', 'echo @ran', 'print-tests all',
            'print-test-result tests %s:lib:tests::adds_wrong' % CARGO,
            'print-test-result tests %s:lib:tests::strings' % CARGO, 'print-gutter', 'print-test-runs'])
        found = out[out.index('@found'):out.index('@ran')]
        self.assertIn('notrun lib id=%s:lib kind=group ms=- lazy' % CARGO, found)
        self.assertIn('notrun tests/api id=%s:tests/api kind=file ms=- lazy' % CARGO, found)
        ran = out[out.index('@ran'):]
        self.assertTrue(self.item(ran, CARGO + ':lib:tests::adds').startswith('passed tests::adds '))
        self.assertTrue(self.item(ran, CARGO + ':lib:tests::adds_wrong').startswith('failed tests::adds_wrong '))
        self.assertTrue(self.item(ran, CARGO + ':lib:tests::slow').startswith('skipped tests::slow '))
        self.assertTrue(self.item(ran, CARGO + ':tests/api:api_works').startswith('passed api_works '))
        # assert_eq! values, Debug strings unescaped, and the panic's place
        self.assertTrue([l for l in out if l.startswith('message=') and
                         l.endswith('src/lib.rs:16:9 expected=5 actual=4')], out)
        self.assertTrue([l for l in out if l.startswith('message=') and
                         l.endswith('src/lib.rs:25:9 expected=a\\nc actual=a\\nb')], out)
        self.assertIn('line=15 glyph=failed item=%s:lib:tests::adds_wrong' % CARGO, out)
        self.assertIn('line=10 glyph=passed item=%s:lib:tests::adds' % CARGO, out)
        runs = [l for l in out if l.startswith('run=')]
        self.assertTrue(runs and 'passed=2 failed=2 errored=0 skipped=1' in runs[-1], out)


if __name__ == '__main__':
    unittest.main()
