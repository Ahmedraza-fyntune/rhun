#!/usr/bin/env python3
"""Language features with real language servers through the first-party lsp extension
(github.com/rhun-editor/lsp). Skipped unless RHUN_TEST_LSP names the lsp extension's binary for
this platform (built from a checkout with the matching SDK) and the server is on PATH (gopls,
clangd, rust-analyzer; RHUN_TEST_SERVER_PATH may add a folder to PATH for them).

  RHUN_TEST_LSP=/path/to/lsp-macos-arm64 RHUN_TEST_LSP_INI=/path/to/extension.ini \\
      python3 tests/langfeat-real.py
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
LSP = os.environ.get('RHUN_TEST_LSP', '')
INI = os.environ.get('RHUN_TEST_LSP_INI', '')
EXTRA = os.environ.get('RHUN_TEST_SERVER_PATH', '')
TARGET = {'darwin': 'macos-arm64', 'linux': 'linux-x86_64'}.get(os.uname().sysname.lower(), '')
CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n[updates]\ncheck = false\n'
          '[git]\nenabled = false\n')


def have(tool):
    path = os.pathsep.join(p for p in (EXTRA, os.environ.get('PATH', '')) if p)
    return shutil.which(tool, path=path) is not None


@unittest.skipUnless(LSP and INI and Path(LSP).exists(), 'RHUN_TEST_LSP and RHUN_TEST_LSP_INI are not set')
class Real(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-real-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        (self.work / 'config/rhun').mkdir(parents=True)
        (self.work / 'config/rhun/config').write_text(CONFIG)
        ext = self.work / 'exts/rhun-editor/lsp'
        (ext / 'bin').mkdir(parents=True)
        shutil.copy(INI, ext / 'extension.ini')
        shutil.copy(LSP, ext / 'bin' / f'lsp-{TARGET}')
        # the go toolchain's caches stay in the run's home
        self.env = dict(os.environ, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'), XDG_DATA_HOME=str(self.work / 'data'),
                        GOFLAGS='-mod=mod', GOTOOLCHAIN='local', GOWORK='off')
        if EXTRA:
            self.env['PATH'] = EXTRA + os.pathsep + self.env['PATH']

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, files, actions, timeout=180):
        script = self.work / 'script.rsc'
        opens = ['open ' + str(self.proj / f) for f in files]
        script.write_text('\n'.join(['wait 100', *opens, *actions, 'quit']) + '\n')
        r = subprocess.run([str(EXE), str(self.proj), '--headless', '1000x600', '--scale', '1',
                            '--extensions', str(self.work / 'exts'), '--script', str(script)],
                           env=self.env, capture_output=True, timeout=timeout)
        self.assertEqual(r.returncode, 0, r.stderr.decode(errors='replace')[-2000:])
        return r.stdout.decode(errors='replace').splitlines()

    def log(self):
        p = self.work / 'state/rhun/extensions/rhun-editor--lsp.log'
        return p.read_text(errors='replace') if p.exists() else ''

    def doc(self, out, marker='==='):
        i = len(out) - 1 - out[::-1].index(marker)
        return '\n'.join(out[i + 1:out.index('<eod>', i)]).rstrip('\n')

    def warm(self, wait=12000):
        """Until the server answers: completion asked a few times while it indexes."""
        return ['wait-ext rhun-editor/lsp running', f'wait {wait}']

    @unittest.skipUnless(have('gopls'), 'gopls is not on PATH')
    def test_gopls_completion_adds_the_import_and_a_native_field(self):
        (self.proj / 'go.mod').write_text('module example.com/demo\n\ngo 1.22\n')
        (self.proj / 'main.go').write_text('package main\n\nfunc main() {\n\ts := "a"\n\t_ = s\n\t\n}\n')
        out = self.run_editor(['main.go'], [
            *self.warm(), 'key ctrl+Home', 'key Down', 'key Down', 'key Down', 'key Down', 'key Down',
            'key End', 'type strings.Cl', 'wait 2500', 'print-complete', 'key Return', 'wait 1500',
            'echo ===', 'print-doc', 'print-state', 'key ctrl+z', 'echo ===', 'print-doc'])
        text = '\n'.join(out)
        self.assertIn('labels=Clone', text, text + self.log())
        accepted = text.split('===')[1]
        self.assertIn('import "strings"', accepted, text)
        self.assertIn('strings.Clone()', accepted, text)
        self.assertIn('line=8 col=19', accepted, text)  # in the native field between the parentheses (tab = 4)
        self.assertNotIn('import "strings"', text.split('===')[2], text)


if __name__ == '__main__':
    unittest.main()
