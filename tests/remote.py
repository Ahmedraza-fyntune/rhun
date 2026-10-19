#!/usr/bin/env python3
"""Remote windows (src/app/remote.s, remoteui.s, ragent.s) driven headlessly against real hosts:
a Linux container reached with `docker exec` and with ssh (sshd in a second container, key and
password logins), and on Linux the `local:` transport (sh -s on this machine). Checks the
bootstrap, the upload and the cached second start, a remote terminal, ssh's password question
through askpass, a dropped connection and Reconnect, and a failed connection's message.

Needs docker. A macOS or Windows client needs a Linux build of rhun to send: RHUN_TEST_LINUX_EXE
(the Linux client sends itself). Each run gets its own HOME, config and state."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
LINUX_EXE = os.environ.get('RHUN_TEST_LINUX_EXE') or (str(EXE) if sys.platform.startswith('linux') else '')
IMAGE = 'rhun-remote-host'
HOST = 'rhun-test-remote-host'
SSHD = 'rhun-test-remote-sshd'
SSH_PORT = int(os.environ.get('RHUN_TEST_SSH_PORT', '2222'))
DOCKERFILE = ('FROM debian:stable-slim\n'
              'RUN apt-get update && apt-get install -y --no-install-recommends openssh-server '
              'openssh-client git python3 procps && rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd\n')


def have_docker():
    try:
        return subprocess.run(['docker', 'info'], capture_output=True, timeout=20).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def docker(*args, check=True, input=None):
    return subprocess.run(['docker', *args], capture_output=True, check=check, input=input, timeout=600)


def ensure_image():
    if docker('image', 'inspect', IMAGE, check=False).returncode != 0:
        subprocess.run(['docker', 'build', '-q', '--platform', 'linux/amd64', '-t', IMAGE, '-'],
                       input=DOCKERFILE.encode(), check=True, capture_output=True, timeout=900)


DOCKER = have_docker()


@unittest.skipUnless(DOCKER, 'needs docker')
@unittest.skipUnless(LINUX_EXE, 'needs a Linux rhun to send (RHUN_TEST_LINUX_EXE)')
class Remote(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        ensure_image()
        cls.tmp = tempfile.TemporaryDirectory(prefix='rhun-remote-')
        base = Path(cls.tmp.name)
        # the host for docker exec, with a project
        docker('rm', '-f', HOST, check=False)
        docker('run', '-d', '--platform', 'linux/amd64', '--name', HOST, IMAGE, 'sleep', 'infinity')
        docker('exec', HOST, 'sh', '-c',
               'mkdir -p /root/proj/src/deep /root/proj/node_modules && cd /root/proj && '
               'printf "hello\\nworld\\n" > a.txt && printf "fn main() {\\n    let needle = 1;\\n}\\n" > src/main.rs && '
               'echo "needle deep" > src/deep/b.txt && echo needle > node_modules/x.js && git init -q && '
               'git add . && git -c user.name=t -c user.email=t@t commit -qm init')
        slug = '-root-proj'
        docker('exec', '-i', HOST, 'sh', '-c', 'mkdir -p /root/.claude/projects/%s && cat > '
               '/root/.claude/projects/%s/s1.jsonl' % (slug, slug),
               input=(ROOT / 'tests/data/agents/claude.jsonl').read_bytes().replace(b'@PROJECT@', b'/root/proj'))
        # sshd: a key for root, a password for pw
        key = base / 'key'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
        docker('rm', '-f', SSHD, check=False)
        docker('run', '-d', '--platform', 'linux/amd64', '--name', SSHD, '-p', '127.0.0.1:%d:22' % SSH_PORT,
               IMAGE, 'sh', '-c', 'ssh-keygen -A && exec /usr/sbin/sshd -D -e -o PasswordAuthentication=yes')
        docker('exec', '-i', SSHD, 'sh', '-c',
               'mkdir -p /root/.ssh /root/proj && cat > /root/.ssh/authorized_keys && '
               'chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys && '
               'useradd -m -s /bin/bash pw && echo pw:s3cret-pw | chpasswd && mkdir -p /home/pw/proj && '
               'chown pw /home/pw/proj', input=(base / 'key.pub').read_bytes())
        conf = base / 'ssh_config'
        common = ('  HostName 127.0.0.1\n  Port %d\n  StrictHostKeyChecking no\n'
                  '  UserKnownHostsFile /dev/null\n  LogLevel ERROR\n' % SSH_PORT)
        cls.known = base / 'known_hosts'
        asking = ('  HostName 127.0.0.1\n  Port %d\n  StrictHostKeyChecking ask\n  UserKnownHostsFile %s\n'
                  '  LogLevel ERROR\n' % (SSH_PORT, cls.known))
        conf.write_text('Host keyhost\n  User root\n  IdentityFile %s\n  IdentitiesOnly yes\n%s'
                        'Host pwhost\n  User pw\n  PubkeyAuthentication no\n'
                        '  PreferredAuthentications password,keyboard-interactive\n%s'
                        'Host askhost\n  User root\n  IdentityFile %s\n  IdentitiesOnly yes\n%s'
                        % (key, common, common, key, asking))
        cls.wrapper = base / 'ssh-wrapper'
        cls.wrapper.write_text('#!/bin/sh\nexec ssh -F %s "$@"\n' % conf)
        cls.wrapper.chmod(0o755)
        end = time.time() + 30
        while time.time() < end:
            r = subprocess.run([str(cls.wrapper), 'keyhost', 'true'], capture_output=True, timeout=30)
            if r.returncode == 0:
                break
            time.sleep(0.5)

    @classmethod
    def tearDownClass(cls):
        docker('rm', '-f', HOST, check=False)
        docker('rm', '-f', SSHD, check=False)
        cls.tmp.cleanup()

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix='run-', dir=self.tmp.name))
        for d in ('home', 'config/rhun', 'state', 'tmp'):
            (self.dir / d).mkdir(parents=True)
        (self.dir / 'config/rhun/config').write_text('[remote]\nagent_binary = %s\n' % LINUX_EXE)

    def run_script(self, spec, path, lines, timeout=120, env_extra=None, home=None):
        script = self.dir / 't.rsc'
        script.write_text('\n'.join(lines) + '\nquit\n')
        env = dict(os.environ)
        env.update({'HOME': str(home or self.dir / 'home'), 'XDG_CONFIG_HOME': str(self.dir / 'config'),
                    'XDG_STATE_HOME': str(self.dir / 'state'), 'TMPDIR': str(self.dir / 'tmp'),
                    'RHUN_SSH': str(self.wrapper)})
        env.update(env_extra or {})
        args = [str(EXE), '--headless', '1000x700', '--remote', spec]
        if path:
            args.append(path)
        args += ['--script', str(script)]
        p = subprocess.run(args, capture_output=True, timeout=timeout, env=env)
        return p.stdout.decode(errors='replace')

    def field(self, out, line_start, key):
        for line in out.splitlines():
            if line.startswith(line_start):
                for f in line.split(' '):
                    if f.startswith(key + '='):
                        return f[len(key) + 1:]
        return None

    def test_docker_bootstrap_cache_and_terminal(self):
        lines = ['wait-remote 90', 'print-remote', 'print-project', 'cmd toggle_terminal', 'wait 500',
                 'type echo hi-$((40+2))', 'key Return', 'wait-term hi-42', 'print-term']
        out = self.run_script('docker:' + HOST, '/root/proj', lines)
        self.assertEqual(self.field(out, 'remote=', 'state'), 'connected', out)
        self.assertIn('project=~/proj', out)          # the host's home as ~
        self.assertIn('hi-42', out.split('print-term')[-1] if 'print-term' in out else out)
        first = int(self.field(out, 'remote=', 'out'))
        self.assertGreater(first, 1000000)      # the binary went up
        out = self.run_script('docker:' + HOST, '/root/proj', ['wait-remote 90', 'print-remote'])
        self.assertEqual(self.field(out, 'remote=', 'state'), 'connected', out)
        self.assertLess(int(self.field(out, 'remote=', 'out')), 10000)   # cached on the host

    def test_ssh_key(self):
        out = self.run_script('ssh:keyhost', '/root/proj', ['wait-remote 90', 'print-remote',
                                                           'cmd toggle_terminal', 'wait 500',
                                                           'type echo "$SSH_CONNECTION" | wc -w', 'key Return',
                                                           'wait-term 4', 'print-term'])
        self.assertEqual(self.field(out, 'remote=', 'state'), 'connected', out)
        self.assertEqual(self.field(out, 'remote=', 'remote'), 'ssh')

    def test_ssh_password_through_askpass(self):
        out = self.run_script('ssh:pwhost', '/home/pw/proj', ['wait 4000', 'print-palette', 'type s3cret-pw',
                                                              'key Return', 'wait-remote 90', 'print-remote',
                                                              'print-project'])
        self.assertIn("password:", out)
        self.assertEqual(self.field(out, 'remote=', 'state'), 'connected', out)
        self.assertIn('project=~/proj', out)
        # Escape answers no: it fails, saying so
        out = self.run_script('ssh:pwhost', '/home/pw/proj', ['wait 4000', 'key Escape', 'wait 3000',
                                                              'key Escape', 'wait 3000', 'key Escape',
                                                              'wait-remote 30', 'print-remote'])
        self.assertEqual(self.field(out, 'remote=', 'state'), 'failed', out)
        # the askpass folder went with the window
        self.assertFalse([p for p in Path('/tmp').glob('rhun-askpass-*') if p.stat().st_uid == os.getuid()
                          and p.stat().st_mtime > time.time() - 60])

    def test_ssh_host_key_question(self):
        """An unknown host key: ssh asks through askpass, the window offers Yes and No; Yes reaches
        ssh as "yes", which records the key and connects."""
        if self.known.exists():
            self.known.unlink()
        out = self.run_script('ssh:askhost', '/root/proj', ['wait 4000', 'print-palette', 'key Return',
                                                           'wait-remote 90', 'print-remote'])
        self.assertIn('> Yes\n  No', out)
        self.assertEqual(self.field(out, 'remote=', 'state'), 'connected', out)
        self.assertIn('127.0.0.1', self.known.read_text())

    def test_drop_and_reconnect(self):
        lines = ['wait-remote 90', 'cmd toggle_terminal', 'wait 500', 'remote-drop', 'wait 200',
                 'print-remote', 'remote-reconnect', 'wait-remote 90', 'print-remote',
                 'cmd toggle_terminal', 'wait 500', 'type echo back-$((1+1))', 'key Return',
                 'wait-term back-2', 'print-term']
        out = self.run_script('docker:' + HOST, '/root/proj', lines)
        states = [self.field(l, 'remote=', 'state') for l in out.splitlines() if l.startswith('remote=')]
        self.assertEqual(states, ['lost', 'connected'], out)
        self.assertIn('back-2', out)

    def host_read(self, path):
        return docker('exec', HOST, 'cat', path).stdout.decode()

    def test_workspace_files_git_search_and_agents(self):
        """The explorer, a document opened, edited and saved, a change made on the host reloading it,
        Go to File, Find in Files, git's status and the agents panel, all of the host's, with
        RHUN_REMOTE_STRICT=1 stopping rhun on any local access to the project."""
        docker('exec', HOST, 'sh', '-c', 'cd /root/proj && git checkout -q -- . && rm -f fresh.txt')
        lines = ['wait-remote 90', 'wait 500', 'print-explorer', 'open /root/proj/a.txt', 'wait 300', 'print-doc',
                 'key ctrl+End', 'type saved here', 'key ctrl+s', 'wait 500', 'wait-git', 'print-git',
                 'cmd quick_open', 'type main.r', 'print-palette', 'key Escape',
                 'cmd find_in_files', 'type needle', 'wait-grep', 'print-palette', 'key Escape',
                 'open /root/proj/src/deep/b.txt', 'wait 300', 'cmd toggle_terminal', 'wait 500',
                 "type printf 'from the host\\n' > /root/proj/src/deep/b.txt; touch /root/proj/fresh.txt; echo done-1",
                 'key Return', 'wait-term done-1', 'wait 1500', 'print-doc', 'print-explorer',
                 'wait-agents', 'print-agents']
        out = self.run_script('docker:' + HOST, '/root/proj', lines, env_extra={'RHUN_REMOTE_STRICT': '1'})
        self.assertNotIn('RHUN_REMOTE_STRICT', out)
        self.assertIn('src/\na.txt\n', out)
        self.assertNotIn('node_modules', out.split('field=')[0])
        self.assertIn('hello\nworld\n', out)
        self.assertEqual(self.host_read('/root/proj/a.txt'), 'hello\nworld\nsaved here\n')
        self.assertIn('git on branch=master', out)
        self.assertIn('M a.txt', out)
        self.assertIn('field=main.r\n> src/main.rs', out)
        self.assertIn('field=needle\n', out)
        grep = out.split('field=needle\n')[1]
        self.assertIn('needle deep', grep)
        self.assertIn('let needle = 1;', grep)
        self.assertIn('from the host\n\n<eod>', out)        # reloaded from the host's change
        self.assertIn('fresh.txt', out.split('from the host\n\n<eod>')[1])
        self.assertIn('Claude: Status bar work', out)

    def test_unsaved_text_survives_a_drop(self):
        docker('exec', HOST, 'sh', '-c', 'cd /root/proj && git checkout -q -- .')
        # the text stays, a save while the connection is down is made once it is back
        lines = ['wait-remote 90', 'open /root/proj/a.txt', 'wait 300', 'key ctrl+End', 'type kept',
                 'remote-drop', 'wait 200', 'print-remote', 'print-doc', 'key ctrl+s', 'wait 300', 'print-toast',
                 'remote-reconnect', 'wait-remote 90', 'print-remote', 'wait 1000', 'print-doc']
        out = self.run_script('docker:' + HOST, '/root/proj', lines)
        states = [self.field(l, 'remote=', 'state') for l in out.splitlines() if l.startswith('remote=')]
        self.assertEqual(states, ['lost', 'connected'], out)
        self.assertIn('kept', out)
        self.assertIn('Not connected: saved when %s is back' % HOST, out)
        self.assertEqual(self.host_read('/root/proj/a.txt'), 'hello\nworld\nkept\n')

    def test_failure_is_reported(self):
        out = self.run_script('docker:no-such-container-here', '', ['wait-remote 60', 'print-remote'])
        self.assertEqual(self.field(out, 'remote=', 'state'), 'failed', out)
        self.assertIn('error=Could not connect to no-such-container-here', out)

@unittest.skipUnless(sys.platform.startswith('linux'), 'local: runs the agent on this machine')
class LocalTransport(unittest.TestCase):
    """sh -s on this machine: the whole remote path without docker or sshd."""

    def test_local_transport(self):
        with tempfile.TemporaryDirectory(prefix='rhun-remote-local-') as tmp:
            base = Path(tmp)
            for d in ('home', 'config', 'state', 'tmp', 'proj'):
                (base / d).mkdir()
            script = base / 't.rsc'
            script.write_text('wait-remote 60\nprint-remote\nprint-project\ncmd toggle_terminal\nwait 500\n'
                              'type echo hi-$((40+2))\nkey Return\nwait-term hi-42\nprint-term\nquit\n')
            env = dict(os.environ, HOME=str(base / 'home'), XDG_CONFIG_HOME=str(base / 'config'),
                       XDG_STATE_HOME=str(base / 'state'), TMPDIR=str(base / 'tmp'), SHELL='/bin/sh')
            out = subprocess.run([str(EXE), '--headless', '1000x700', '--remote', 'local:', str(base / 'proj'),
                                  '--script', str(script)], capture_output=True, timeout=120,
                                 env=env).stdout.decode(errors='replace')
            self.assertIn('state=connected', out)
            self.assertIn('project=%s' % (base / 'proj'), out)
            self.assertIn('hi-42', out)
            self.assertTrue(list((base / 'home/.cache/rhun-remote').glob('*/rhun')))


    def test_typing_never_waits_for_the_host(self):
        """With every agent reply 300 ms late, 40 typed characters cost no more than a few replies."""
        with tempfile.TemporaryDirectory(prefix='rhun-remote-slow-') as tmp:
            base = Path(tmp)
            for d in ('home', 'config', 'state', 'proj'):
                (base / d).mkdir()
            (base / 'proj/a.txt').write_text('text\n')
            env = dict(os.environ, HOME=str(base / 'home'), XDG_CONFIG_HOME=str(base / 'config'),
                       XDG_STATE_HOME=str(base / 'state'), SHELL='/bin/sh', RHUN_REMOTE_DELAY_MS='300')
            times = []
            for typing in ('', 'type ' + 'x' * 40):
                rsc = base / 't.rsc'
                rsc.write_text('wait-remote 60\nopen %s/proj/a.txt\nwait 300\necho start\n%s\necho end\nprint-doc\nquit\n'
                               % (base, typing))
                t0 = time.time()
                p = subprocess.run([str(EXE), '--headless', '800x600', '--remote', 'local:', str(base / 'proj'),
                                    '--script', str(rsc)], capture_output=True, timeout=180, env=env)
                times.append(time.time() - t0)
                out = p.stdout.decode(errors='replace')
            self.assertIn('x' * 40 + 'text', out)
            self.assertLess(times[1] - times[0], 4.0, times)

    def test_ui_scripts_under_strict(self):
        """Every tests/scripts/*.rsc in a remote window (local: shares this machine's paths) with
        RHUN_REMOTE_STRICT=1: no local file function may see a path of the project, and none may
        crash. Outputs may differ (the host's shell prompt, recent folders are the remote's)."""
        stops = []
        with tempfile.TemporaryDirectory(prefix='rhun-remote-ui-') as tmp:
            base = Path(tmp)
            # rhun's own resources the scripts name live in the repository (the project): copies
            compose = base / 'compose.txt'
            shutil.copy(ROOT / 'tests/data/compose.txt', compose)
            icons = base / 'icons'
            shutil.copytree(ROOT / 'tests/data/icons', icons, symlinks=True)
            for script in sorted((ROOT / 'tests/scripts').glob('*.rsc')):
                n = script.stem
                home = base / ('home-' + n)
                home.mkdir()
                if (ROOT / 'tests/data' / (n + '.home')).is_dir():
                    shutil.copytree(ROOT / 'tests/data' / (n + '.home'), home, dirs_exist_ok=True)
                if (ROOT / 'tests/data' / (n + '.setup')).is_file():
                    subprocess.run(['sh', str(ROOT / 'tests/data' / (n + '.setup')), str(home),
                                    str(base / ('state-' + n))], capture_output=True, check=False)
                text = 'wait-remote 30\n' + script.read_text(encoding='utf-8').replace('@HOME@', str(home))
                start = next((l[len('# start: '):] for l in text.splitlines() if l.startswith('# start: ')),
                             str(ROOT))
                rsc = base / (n + '.rsc')
                rsc.write_text(text, encoding='utf-8')
                env = dict(os.environ, RHUN_REMOTE_STRICT='1', HOME=str(home),
                           XDG_CONFIG_HOME=str(base / ('config-' + n)), XDG_STATE_HOME=str(base / ('state-' + n)),
                           XCOMPOSEFILE=str(compose), XCURSOR_PATH=str(icons),
                           XCURSOR_THEME='child', SHELL='/bin/sh', PS1='$ ', GROK_HOME='')
                p = subprocess.run([str(EXE), '--remote', 'local:', start, '--headless', '1400x860', '--script',
                                    str(rsc)], capture_output=True, timeout=120, env=env, cwd=ROOT)
                out = (p.stdout + p.stderr).decode(errors='replace')
                if 'RHUN_REMOTE_STRICT' in out or p.returncode != 0:
                    stops.append('%s (exit %d): %s' % (n, p.returncode,
                                 next((l for l in out.splitlines() if 'STRICT' in l), '')))
        self.assertEqual(stops, [])


if __name__ == '__main__':
    unittest.main()
