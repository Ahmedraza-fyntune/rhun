#!/usr/bin/env python3
"""Open Folder's "Open <folder> in a new window" starts another rhun with that folder, and this window
keeps its project. RHUN_NEW_WINDOW stands in for the program, and notes what it was given."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()


@unittest.skipIf(os.name == 'nt', 'RHUN_NEW_WINDOW is Unix only; Windows starts rhun.exe itself')
class NewWindow(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-new-window-')
        self.home = Path(self.tmp.name).resolve()
        self.alpha = self.home / 'work/alpha'
        self.beta = self.home / 'work/beta'
        self.alpha.mkdir(parents=True)
        self.beta.mkdir(parents=True)
        (self.alpha / 'a.txt').write_text('a\n', encoding='utf-8')
        self.noted = self.home / 'noted.txt'
        self.program = self.home / 'other-rhun'
        self.program.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "' + self.noted.as_posix() + '"\n',
                                encoding='utf-8')
        self.program.chmod(0o755)
        config = self.home / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n'
                          '[ui]\nagents_panel = false\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix(),
                        RHUN_NEW_WINDOW=self.program.as_posix())

    def tearDown(self):
        self.tmp.cleanup()

    def test_opens_the_folder_in_another_rhun(self):
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join(['cmd open_folder', 'type ../beta/', 'print-palette',
                                     'key Down', 'key Return', 'wait 300', 'print-palette',
                                     'print-project', 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(self.alpha), '--headless', '1000x700',
                                 '--script', str(script)], env=self.env, capture_output=True,
                                text=True, encoding='utf-8', timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            'field=~/work/alpha/../beta/', '> Open ~/work/beta', '  Open ~/work/beta in a new window',
            'none', 'project=~/work/alpha'])
        for _ in range(100):
            if self.noted.exists() and self.noted.read_text(encoding='utf-8'):
                break
            time.sleep(0.05)
        self.assertEqual(self.noted.read_text(encoding='utf-8'), self.beta.as_posix() + '\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
