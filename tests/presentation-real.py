#!/usr/bin/env python3
"""Editor presentation with a real language server through the first-party lsp extension: clangd's
folding ranges, semantic tokens, inlay hints and document highlights. Skipped unless RHUN_TEST_LSP
names the lsp extension's binary for this platform (built with the matching SDK) and
RHUN_TEST_LSP_INI its manifest, and clangd is on PATH.

  RHUN_TEST_LSP=/path/to/lsp-macos-arm64 RHUN_TEST_LSP_INI=/path/to/extension.ini \\
      python3 tests/presentation-real.py
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
TARGET = {'darwin': 'macos-arm64', 'linux': 'linux-x86_64'}.get(os.uname().sysname.lower(), '')
CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n[updates]\ncheck = false\n'
          '[git]\nenabled = false\n')
MAIN_C = '''#include <stdio.h>

struct point {
    int x;
    int y;
};

static int add(int left, int right) {
    int total = left;
    total += right;
    return total;
}

int main(void) {
    struct point p = {1, 2};
    int sum = add(p.x, p.y);
    printf("%d\\n", sum);
    return 0;
}
'''


@unittest.skipUnless(LSP and INI and Path(LSP).exists() and shutil.which('clangd'),
                     'RHUN_TEST_LSP, RHUN_TEST_LSP_INI or clangd missing')
class Real(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-pres-real-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        (self.proj / 'main.c').write_text(MAIN_C)
        (self.work / 'config/rhun').mkdir(parents=True)
        (self.work / 'config/rhun/config').write_text(CONFIG)
        ext = self.work / 'exts/rhun-editor/lsp'
        (ext / 'bin').mkdir(parents=True)
        shutil.copy(INI, ext / 'extension.ini')
        shutil.copy(LSP, ext / 'bin' / f'lsp-{TARGET}')
        self.env = dict(os.environ, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'), XDG_DATA_HOME=str(self.work / 'data'))

    def tearDown(self):
        self.tmp.cleanup()

    def test_clangd_folds_colors_hints_and_highlights(self):
        script = self.work / 'script.rsc'
        script.write_text('\n'.join(['wait 100', f'open {self.proj / "main.c"}', 'wait-ext rhun-editor/lsp running',
                                     'wait 8000', 'key ctrl+Home'] + ['key Down'] * 8 +
                                    ['key End', 'key Left', 'key Left', 'key Left', 'wait 1500',
                                     'print-present tokens', 'print-present hints', 'print-present ranges',
                                     'print-present highlights', 'quit']) + '\n')
        r = subprocess.run([str(EXE), str(self.proj), '--headless', '1000x600', '--scale', '1',
                            '--extensions', str(self.work / 'exts'), '--script', str(script)],
                           env=self.env, capture_output=True, timeout=180)
        out = r.stdout.decode(errors='replace').splitlines()
        self.assertTrue(any(l.startswith('tokens lsp legend=clangd ') for l in out), out)
        self.assertIn('tk 8 12 3 cls=3 fx=0', out)              # add: a function
        self.assertIn('hint 16 19 before label=left: ', out)     # a parameter's name
        self.assertIn('range 8-11 kind=1', out)                  # add's body folds
        self.assertIn('highlight 9:17-9:21 text', out)           # "left" under the caret, and its uses


if __name__ == '__main__':
    unittest.main()
