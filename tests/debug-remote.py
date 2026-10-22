#!/usr/bin/env python3
"""The debugger in a remote window (docs/guide.md "Debugging"): launch.ini is the host's file
(Debug: Add Configuration and Open Configurations go through the remote file system), and a debugger
reached over TCP (as Delve is) runs on the host and is connected to through the host: the host makes
the connection to its own loopback, again until the adapter listens or 10 s have passed, and only
then does initialize go out.

Remote (Linux only): the `local:` transport is a remote window to this machine, and
RHUN_REMOTE_STRICT=1 stops rhun when a local file function is given a path of the project.
DockerHost: a Linux container reached with `docker exec` (the host remote.py sets up, with python3
for the fake adapter); a macOS client needs a Linux build to send (RHUN_TEST_LINUX_EXE). The fake
debugger's extension never runs there: its folder, with the adapter, is copied before the launch."""
import json
import os
from pathlib import Path
import shutil
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



LINUX_EXE = os.environ.get('RHUN_TEST_LINUX_EXE') or (str(EXE) if sys.platform.startswith('linux') else '')
IMAGE = 'rhun-remote-host'
HOST = 'rhun-test-debug-host'
DOCKERFILE = ('FROM debian:stable-slim\n'
              'RUN apt-get update && apt-get install -y --no-install-recommends openssh-server '
              'openssh-client git python3 procps && rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd\n')


def have_docker():
    try:
        return subprocess.run(['docker', 'info'], capture_output=True, timeout=20).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def docker(*args, check=True, input=None):
    return subprocess.run(['docker', *args], capture_output=True, check=check, input=input, timeout=900)


@unittest.skipUnless(have_docker(), 'needs docker')
@unittest.skipUnless(LINUX_EXE, 'needs a Linux rhun to send (RHUN_TEST_LINUX_EXE)')
class DockerHost(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if docker('image', 'inspect', IMAGE, check=False).returncode != 0:
            docker('build', '-q', '--platform', 'linux/amd64', '-t', IMAGE, '-', input=DOCKERFILE.encode())
        docker('rm', '-f', HOST, check=False)
        docker('run', '-d', '--platform', 'linux/amd64', '--name', HOST, IMAGE, 'sleep', 'infinity')
        steps = [{'file': '/root/proj/a.c', 'line': 6, 'function': 'main', 'locals': {'total': 0}},
                 {'file': '/root/proj/a.c', 'line': 9, 'function': 'main', 'output': 'done\n'}]
        docker('exec', '-i', HOST, 'sh', '-c', 'mkdir -p /root/proj && cat > /root/proj/scenario.json',
               input=json.dumps({'steps': steps, 'exitCode': 3}).encode())

    @classmethod
    def tearDownClass(cls):
        docker('rm', '-f', HOST, check=False)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-dbg-docker-')
        self.base = Path(self.tmp.name)
        for d in ('home', 'config/rhun', 'state', 'tmp'):
            (self.base / d).mkdir(parents=True)
        (self.base / 'config/rhun/config').write_text(
            '[remote]\nagent_binary = %s\n[updates]\ncheck = false\n[git]\nenabled = false\n' % LINUX_EXE)

    def tearDown(self):
        self.tmp.cleanup()

    cache_blocked = False

    def extension(self, mode):
        """the fake debugger with its adapter inside its folder (the folder is what reaches the host);
        its tcp adapter gets the mode as an argument (the host's adapter has the host's environment)"""
        dst = self.base / 'exts/rhun-tests/debugfake'
        dst.mkdir(parents=True)
        ini = (EXTS / 'rhun-tests/debugfake/extension.ini').read_text(encoding='utf-8')
        ini = ini.replace('${extension}/../../../fakedap.py', '${extension}/fakedap.py')
        ini = ini.replace('../../../debugfake.py', 'debugfake.py')
        ini = ini.replace('--listen 127.0.0.1:${port}', '--listen 127.0.0.1:${port} --mode x%s' % (',' + mode if mode else ''))
        (dst / 'extension.ini').write_text(ini, encoding='utf-8')
        shutil.copy(ROOT / 'tests/dap/fakedap.py', dst / 'fakedap.py')
        shutil.copy(ROOT / 'tests/dap/debugfake.py', dst / 'debugfake.py')
        shutil.copytree(EXTS / 'rhun-tests/debugfake/templates', dst / 'templates')
        return self.base / 'exts'

    def run_tcp(self, lines, mode='', timeout=180):
        docker('exec', '-i', HOST, 'sh', '-c', 'mkdir -p /root/proj/.rhun && cat > /root/proj/.rhun/launch.ini',
               input=b'[Run]\ntype = faketcp\nprogram = scenario.json\nstopOnEntry = yes\n')
        script = self.base / 't.rsc'
        # the extension never ran on the host: its folder (and so its adapter) is copied there first
        docker('exec', HOST, 'rm', '-rf', '/root/.cache/rhun-remote/extensions')
        if self.cache_blocked:
            docker('exec', HOST, 'sh', '-c', 'mkdir -p /root/.cache/rhun-remote && '
                   'touch /root/.cache/rhun-remote/extensions')
        script.write_text('\n'.join(['wait-remote 90', 'debug-start Run', 'wait 500', 'dialog yes', *lines,
                                      'quit']) + '\n')
        env = dict(os.environ, HOME=str(self.base / 'home'), XDG_CONFIG_HOME=str(self.base / 'config'),
                   XDG_STATE_HOME=str(self.base / 'state'), TMPDIR=str(self.base / 'tmp'))
        p = subprocess.run([str(EXE), '--headless', '1000x700', '--remote', 'docker:' + HOST, '/root/proj',
                            '--extensions', str(self.extension(mode)), '--script', str(script)],
                           capture_output=True, timeout=timeout, env=env)
        out = p.stdout.decode(errors='replace').splitlines()
        self.assertEqual(p.returncode, 0, p.stderr.decode(errors='replace')[-3000:])
        return out

    def sessions(self, out):
        return [l for l in out if l.startswith('session=')]

    def field(self, line, name):
        for part in line.split(' '):
            if part.startswith(name + '='):
                return part[len(name) + 1:]
        return None

    def test_a_tcp_adapter_on_the_host(self):
        out = self.run_tcp(['wait-debug paused 30000', 'print-debug', 'debug-continue', 'wait-debug ended 20000',
                            'print-debug', 'print-console'])
        sessions = self.sessions(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'paused', out)
        self.assertEqual((self.field(sessions[1], 'state'), self.field(sessions[1], 'exit')), ('ended', '3'), out)
        self.assertTrue([l for l in out if l.startswith('stdout DAP server listening at: 127.0.0.1:')], out)
        self.assertIn('stdout done', out)

    def test_an_adapter_listening_late(self):
        out = self.run_tcp(['wait-debug paused 30000', 'print-debug', 'debug-stop', 'wait-debug ended 20000',
                            'print-debug'], mode='tcp-late=2500')
        sessions = self.sessions(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'paused', out)
        self.assertEqual(self.field(sessions[-1], 'state'), 'ended', out)

    def test_an_extension_that_cannot_be_copied(self):
        self.cache_blocked = True
        try:
            out = self.run_tcp(['wait-debug ended 30000', 'print-debug', 'print-console'])
        finally:
            docker('exec', HOST, 'rm', '-rf', '/root/.cache/rhun-remote/extensions')
        sessions = self.sessions(out)
        self.assertEqual(self.field(sessions[-1], 'state'), 'ended', out)
        self.assertTrue([l for l in out if "the debugger's extension could not be copied to the host: " in l], out)
        ps = docker('exec', HOST, 'ps', '-eo', 'args').stdout.decode()
        self.assertNotIn('fakedap.py', ps)

    def test_nobody_listening(self):
        out = self.run_tcp(['wait 2000', 'print-debug', 'wait-debug ended 20000', 'print-debug', 'print-console'],
                           mode='tcp-never')
        sessions = self.sessions(out)
        self.assertEqual(self.field(sessions[0], 'state'), 'connecting', out)
        self.assertEqual(self.field(sessions[-1], 'state'), 'ended', out)
        self.assertTrue([l for l in out if 'did not accept a connection on 127.0.0.1:' in l and 'in 10 s' in l], out)
        ps = docker('exec', HOST, 'ps', '-eo', 'args').stdout.decode()
        self.assertNotIn('fakedap.py', ps)


if __name__ == '__main__':
    unittest.main()
