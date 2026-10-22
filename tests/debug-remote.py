#!/usr/bin/env python3
"""The debugger in a remote window (docs/guide.md "Debugging"): launch.ini is the host's file
(Debug: Add Configuration and Open Configurations go through the remote file system), and a debugger
reached over TCP says it does not run there yet instead of waiting 10 s for a port on this machine.
Linux only: the `local:` transport is a remote window to this machine, and RHUN_REMOTE_STRICT=1 stops
rhun when a local file function is given a path of the project."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
EXTS = ROOT / 'tests/dap/exts'


@unittest.skipUnless(sys.platform.startswith('linux'), 'the local: transport is Linux only')
class Remote(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-dbg-remote-')
        self.base = Path(self.tmp.name)
        for d in ('home', 'config/rhun', 'state', 'tmp', 'proj'):
            (self.base / d).mkdir(parents=True)
        (self.base / 'config/rhun/config').write_text('[updates]\ncheck = false\n[git]\nenabled = false\n')
        self.proj = self.base / 'proj'

    def tearDown(self):
        self.tmp.cleanup()

    def run_remote(self, lines):
        script = self.base / 't.rsc'
        script.write_text('\n'.join(['wait-remote 60', *lines, 'quit']) + '\n')
        env = dict(os.environ, RHUN_REMOTE_STRICT='1', HOME=str(self.base / 'home'),
                   XDG_CONFIG_HOME=str(self.base / 'config'), XDG_STATE_HOME=str(self.base / 'state'),
                   TMPDIR=str(self.base / 'tmp'), SHELL='/bin/sh')
        p = subprocess.run([str(EXE), '--headless', '1000x700', '--remote', 'local:', str(self.proj),
                            '--extensions', str(EXTS), '--script', str(script)], capture_output=True,
                           timeout=120, env=env)
        out = (p.stdout + p.stderr).decode(errors='replace')
        self.assertEqual(p.returncode, 0, out)
        self.assertNotIn('RHUN_REMOTE_STRICT', out)
        return out

    def test_add_and_open_configurations_use_the_hosts_file(self):
        out = self.run_remote(['print-remote', 'cmd debug_add_configuration', 'type launch', 'key Return',
                               'wait 500', 'cmd debug_open_configurations', 'wait 300', 'print-configs'])
        self.assertIn('state=connected', out)
        ini = (self.proj / '.rhun/launch.ini').read_text()
        self.assertIn('[Fake launch]\ntype = fake\n', ini)
        self.assertIn('config=Fake launch', out)

    def test_a_tcp_debugger_says_it_does_not_run_here(self):
        (self.proj / '.rhun').mkdir()
        (self.proj / '.rhun/launch.ini').write_text('[Run]\ntype = faketcp\nprogram = x.json\n')
        out = self.run_remote(['debug-start Run', 'wait 500', 'print-debug', 'print-console'])
        self.assertTrue([l for l in out if 'does not do in a remote window yet' in l], out)
        self.assertFalse([l for l in out if l.startswith('session=')], out)


if __name__ == '__main__':
    unittest.main()
