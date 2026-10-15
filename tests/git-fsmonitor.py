#!/usr/bin/env python3
"""A repository's own config cannot make rhun run a program by being opened: git's fsmonitor hook
(core.fsmonitor in .git/config) runs on every git status. rhun runs git with core.fsmonitor=false.
(A folder a rhun://file/ link opens runs no git at all until it is trusted: tests/git-trust.py.)"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()


@unittest.skipIf(os.name == 'nt', 'the hook is a shell script')
class GitFsmonitor(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-fsmonitor-')
        self.work = Path(self.tmp.name).resolve()
        self.repo = self.work / 'repo'
        self.repo.mkdir()
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = true\n'
                          '[editor]\ncursor_blink = false\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=str(self.work),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(),
                        GIT_CONFIG_NOSYSTEM='1')
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.repo / 'file.txt').write_text('one\ntwo\n')
        self.git('add', '-A')
        self.git('commit', '-qm', 'Initial')
        (self.repo / 'file.txt').write_text('one\ntwo changed\n')
        self.marker = self.work / 'ran'
        hook = self.work / 'hook.sh'
        hook.write_text(f'#!/bin/sh\ntouch "{self.marker}"\nexit 1\n')
        hook.chmod(0o755)
        self.git('config', 'core.fsmonitor', str(hook))

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.repo), *args], env=self.env, check=True,
                              capture_output=True).stdout

    def test_opening_runs_no_fsmonitor_hook(self):
        # the hook runs for a plain git status, so the test would see it run
        self.git('status', '--porcelain')
        self.assertTrue(self.marker.exists(), 'this git does not run core.fsmonitor')
        self.marker.unlink()
        for target in (self.repo / 'file.txt', self.repo):
            with self.subTest(path=target):
                script = self.work / 'commands.rsc'
                script.write_text('wait-git\nprint-scm\nquit\n', encoding='utf-8')
                result = subprocess.run([str(EXE), str(target), '--headless', '1000x700',
                                         '--scale', '1', '--script', str(script)], env=self.env,
                                        capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
                # git did run: the changed file is listed
                self.assertIn('file.txt', result.stdout.decode('utf-8'))
                self.assertFalse(self.marker.exists(), 'opening the repository ran its fsmonitor hook')


if __name__ == '__main__':
    unittest.main()
