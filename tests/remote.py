#!/usr/bin/env python3
"""Remote windows (src/app/remote.s, remoteui.s, ragent.s) driven headlessly against real hosts:
a Linux container reached with `docker exec` and with ssh (sshd in a second container, key and
password logins), and on Linux the `local:` transport (sh -s on this machine). Checks the
bootstrap, the upload and the cached second start, a remote terminal, ssh's password question
through askpass, a dropped connection and Reconnect, and a failed connection's message.

Extensions in a remote window run on the host (src/app/remoteext.s): the echo extension is copied
into the host's cache once, writes its state there, and where = local keeps one on this machine.

Needs docker. A macOS or Windows client needs a Linux build of rhun to send: RHUN_TEST_LINUX_EXE
(the Linux client sends itself). Each run gets its own HOME, config and state."""
import os
import re
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
ECHO_CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[files]\nrestore_session = false\n'
               'restore_project = false\n[updates]\ncheck = false\n[git]\nenabled = false\n')


def echo_extension(folder, **changes):
    """A copy of the echo extension (tests/ext/echo.py) with its script inside its folder, as an
    installed extension has it; changes replace parts of its manifest."""
    dst = Path(folder) / 'rhun-tests' / 'echo'
    dst.mkdir(parents=True)
    manifest = (ROOT / 'tests/ext/exts/rhun-tests/echo/extension.ini').read_text(encoding='utf-8')
    manifest = manifest.replace('run = ../../../echo.py', 'run = echo.py')
    for old, new in changes.items():
        assert old in manifest, old
        manifest = manifest.replace(old, new)
    (dst / 'extension.ini').write_text(manifest, encoding='utf-8')
    shutil.copy(ROOT / 'tests/ext/echo.py', dst / 'echo.py')
    return Path(folder)


def ext_line(out):
    return next((l for l in out.splitlines() if l.startswith('rhun-tests/echo ')), '')


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

    def run_script(self, spec, path, lines, timeout=120, env_extra=None, home=None, extra=()):
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
        args += [*extra, '--script', str(script)]
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
        out = self.run_script('docker:' + HOST, '/root/proj', lines, env_extra={'RHUN_REMOTE_SESSION': '0'})
        states = [self.field(l, 'remote=', 'state') for l in out.splitlines() if l.startswith('remote=')]
        self.assertEqual(states, ['lost', 'connected'], out)
        self.assertIn('back-2', out)

    def test_the_session_outlives_a_drop(self):
        """The agent keeps its programs when the connection goes: after Reconnect the same shell
        answers in the same tab (its variable is still set), and a program that ended meanwhile
        reports its exit."""
        lines = ['wait-remote 90', 'cmd toggle_terminal', 'wait 500', 'type X=kept-$((20+1)); echo set-$X',
                 'key Return', 'wait-term set-kept-21', 'term-run --title t --sh -- sleep 1; exit 7',
                 'remote-drop', 'wait 2500', 'print-remote', 'remote-reconnect', 'wait-remote 90', 'wait 500',
                 'print-remote', 'print-terminals', 'term-select 1', 'type echo got-$X', 'key Return',
                 'wait-term got-kept-21', 'print-term']
        out = self.run_script('docker:' + HOST, '/root/proj', lines)
        remotes = [l for l in out.splitlines() if l.startswith('remote=')]
        self.assertEqual([self.field(l, 'remote=', 'state') for l in remotes], ['lost', 'connected'], out)
        self.assertNotEqual(self.field(remotes[0], 'remote=', 'detached'), '0', out)
        self.assertEqual(self.field(remotes[1], 'remote=', 'detached'), '0', out)
        self.assertIn('got-kept-21', out)
        self.assertIn('term=2 kind=terminal owner=- task=- state=exited code=7 ', out)
        self.assertIn('attached to session ', (self.dir / 'state/rhun/remote.log').read_text())
        # Disconnect ends the session: nothing of it is left on the host
        out = self.run_script('docker:' + HOST, '/root/proj',
                              ['wait-remote 90', 'cmd toggle_terminal', 'wait 500', 'cmd remote_disconnect',
                               'wait 1000', 'print-remote'])
        left = docker('exec', HOST, 'sh', '-c', 'ls /root/.cache/rhun-remote/s 2>/dev/null; true').stdout.decode()
        self.assertEqual(left.split(), [], left)

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

    def test_journaled_delete_and_undo(self):
        """The explorer's Delete is a workspace edit: the host's file moves into the local journal and
        Undo Last Multi-File Edit puts it back on the host."""
        docker('exec', HOST, 'sh', '-c', 'cd /root/proj && git checkout -q -- . && rm -f fresh.txt')
        lines = ['wait-remote 90', 'wait 300', 'click 60 122 right', 'menu-pick Delete', 'print-dialog',
                 'dialog yes', 'wait 500', 'print-explorer', 'cmd undo_workspace_edit', 'wait 500', 'print-tx',
                 'print-explorer']
        out = self.run_script('docker:' + HOST, '/root/proj', lines, env_extra={'RHUN_REMOTE_STRICT': '1'})
        self.assertNotIn('RHUN_REMOTE_STRICT', out)
        self.assertIn('dialog=Delete a.txt?', out)
        self.assertIn('state=undone', out)
        self.assertEqual(self.host_read('/root/proj/a.txt'), 'hello\nworld\n')

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

    def test_task_terminal_runs_on_the_host(self):
        out = self.run_script('docker:' + HOST, '/root/proj',
                              ['wait-remote 90', 'term-run --title t -- cat a.txt', 'wait-terminal 1 ended',
                               'wait 300', 'print-term', 'print-terminals'])
        self.assertIn('hello\nworld', out)
        out = self.run_script('docker:' + HOST, '/root/proj',
                              ['wait-remote 90', 'term-run --title t --cwd src --sh -- ls; echo in-$PWD',
                               'wait-terminal 1 ended', 'wait 300', 'print-term'])
        self.assertIn('main.rs', out)
        self.assertIn('in-/root/proj/src', out)

    def test_forwarded_port(self):
        """A port of the host's loopback is reached here: remote-forward listens on 127.0.0.1 and the
        agent connects each connection to the host's server; remote_forward_url rewrites loopback
        URLs (resources' external-uri) and leaves others alone."""
        import urllib.request
        docker('exec', '-d', HOST, 'sh', '-c', 'cd /root/proj && exec python3 -m http.server 8765 --bind 127.0.0.1')
        script = self.dir / 't.rsc'
        script.write_text('wait-remote 90\nwait 500\nremote-forward 8765\necho ready\nwait 6000\n'
                          'print-forward-url http://localhost:8765/a.txt?x=1#y\nprint-forward-url http://[::1]:8765/\n'
                          'print-forward-url https://example.com:8765/\nprint-forward-url http://localhost:9/\n'
                          'print-remote\nremote-unforward 0\nprint-remote\nquit\n')
        env = dict(os.environ, HOME=str(self.dir / 'home'), XDG_CONFIG_HOME=str(self.dir / 'config'),
                   XDG_STATE_HOME=str(self.dir / 'state'), TMPDIR=str(self.dir / 'tmp'))
        p = subprocess.Popen([str(EXE), '--headless', '1000x700', '--remote', 'docker:' + HOST, '/root/proj',
                              '--script', str(script)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env)
        out = b''
        try:
            while b'ready' not in out:
                chunk = os.read(p.stdout.fileno(), 4096)
                if not chunk:
                    break
                out += chunk
            local = int(out.split(b'local=')[1].split()[0])
            body = b''
            for _ in range(20):         # the server may still be starting
                try:
                    body = urllib.request.urlopen('http://127.0.0.1:%d/a.txt' % local, timeout=5).read()
                    break
                except OSError:
                    time.sleep(0.25)
            out += p.communicate(timeout=60)[0]
        finally:
            if p.poll() is None:
                p.kill()
            docker('exec', HOST, 'sh', '-c', 'pkill -f "http.server 8765" || true', check=False)
        text = out.decode(errors='replace')
        self.assertIn(b'hello\n', body, text)
        self.assertIn('url=http://localhost:%d/a.txt?x=1#y' % local, text)
        self.assertIn('url=http://127.0.0.1:%d/' % local, text)
        self.assertIn('url=-\n', text)                    # not the host's loopback
        self.assertIn('url=http://localhost:10009/', text)  # a low port is forwarded above 10000
        self.assertIn(' forwards=8765:%d,9:10009' % local, text)
        self.assertEqual(text.count(' forwards='), 1, text)

    def test_a_big_save_keeps_mode_link_and_neighbours(self):
        """A file over 32 MB goes in parts into a temporary file made exclusively next to the file
        its link leads to: an unrelated PATH.rhun-save stays, the link stays a link, the mode stays."""
        docker('exec', HOST, 'sh', '-c', 'cd /root/proj && rm -f big* && head -c 36000000 /dev/zero | tr "\\0" a '
               '| fold -w 99 > big.txt && chmod 600 big.txt && ln -s big.txt big-link.txt && '
               'echo keep > big.txt.rhun-save')
        out = self.run_script('docker:' + HOST, '/root/proj',
                              ['wait-remote 90', 'open /root/proj/big-link.txt', 'wait 4000', 'key ctrl+Home',
                               'type Z', 'key ctrl+s', 'wait 8000', 'print-state'], timeout=240)
        self.assertIn(' dirty=0 ', out)
        check = docker('exec', HOST, 'sh', '-c', 'cd /root/proj && stat -c %a big.txt && '
                       '{ [ -L big-link.txt ] && echo link; } && head -c 2 big.txt && echo && cat big.txt.rhun-save && '
                       'ls | grep -c rhun-save').stdout.decode()
        self.assertEqual(check.split(), ['600', 'link', 'Za', 'keep', '1'], check)
        docker('exec', HOST, 'sh', '-c', 'cd /root/proj && rm -f big*')

    def test_changes_made_while_disconnected_reach_open_files(self):
        """A file of the host changed while the connection was down is compared once it is back (no
        watch event told of it): the open, unchanged document shows the host's text."""
        docker('exec', HOST, 'sh', '-c', 'cd /root/proj && git checkout -q -- .')
        script = self.dir / 't.rsc'
        script.write_text('wait-remote 90\nopen /root/proj/a.txt\nwait 500\nremote-drop\necho dropped\n'
                          'wait 3000\nremote-reconnect\nwait-remote 90\nwait 2500\nprint-doc\nquit\n')
        env = dict(os.environ, HOME=str(self.dir / 'home'), XDG_CONFIG_HOME=str(self.dir / 'config'),
                   XDG_STATE_HOME=str(self.dir / 'state'), TMPDIR=str(self.dir / 'tmp'))
        p = subprocess.Popen([str(EXE), '--headless', '1000x700', '--remote', 'docker:' + HOST, '/root/proj',
                              '--script', str(script)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env)
        out = b''
        try:
            while b'dropped' not in out:
                chunk = os.read(p.stdout.fileno(), 4096)
                if not chunk:
                    break
                out += chunk
            docker('exec', HOST, 'sh', '-c', 'printf "changed while away\\n" > /root/proj/a.txt')
            out += p.communicate(timeout=120)[0]
        finally:
            if p.poll() is None:
                p.kill()
            docker('exec', HOST, 'sh', '-c', 'cd /root/proj && git checkout -q -- .')
        self.assertIn('changed while away', out.decode(errors='replace'))

    def echo_on_host(self, exts, command='echo.swrite'):
        (self.dir / 'config/rhun/config').write_text('[remote]\nagent_binary = %s\n%s' % (LINUX_EXE, ECHO_CONFIG))
        return self.run_script('docker:' + HOST, '/root/proj',
                               ['wait-remote 90', 'cmd ' + command, 'wait-ext echo running', 'wait 1500',
                                'print-toast', 'print-extensions'], extra=['--extensions', str(exts)])

    def test_extension_runs_on_the_host(self):
        docker('exec', HOST, 'rm', '-rf', '/root/.cache/rhun-remote/extensions',
               '/root/.local/state/rhun/extensions')
        exts = echo_extension(self.dir / 'exts')
        out = self.echo_on_host(exts)
        self.assertIn('toast=probe ok', out)
        line = ext_line(out)
        self.assertIn('state=running', line, out)
        self.assertIn(' confined=', line)
        # its files in the host's cache, its state folder the host's (the probe wrote there)
        listing = docker('exec', HOST, 'ls', '/root/.cache/rhun-remote/extensions/rhun-tests/echo').stdout.decode()
        self.assertTrue(re.fullmatch(r'0\.0\.1-[0-9a-f]{16}\n', listing), listing)
        version = listing.strip()
        docker('exec', HOST, 'test', '-f', '/root/.cache/rhun-remote/extensions/rhun-tests/echo/%s/echo.py' % version)
        docker('exec', HOST, 'test', '-f', '/root/.local/state/rhun/extensions/rhun-tests--echo/state.txt')
        self.assertFalse(list((self.dir / 'state').rglob('state.txt')))
        log = (self.dir / 'state/rhun/remote.log').read_text()
        self.assertIn('extension copied: ', log)
        # the second start finds it there; a changed file is copied again
        (self.dir / 'state/rhun/remote.log').unlink()
        out = self.echo_on_host(exts)
        self.assertIn('toast=probe ok', out)
        log = (self.dir / 'state/rhun/remote.log').read_text()
        self.assertIn('extension on the host: ', log)
        self.assertNotIn('extension copying', log)
        with open(exts / 'rhun-tests/echo/echo.py', 'a') as f:
            f.write('# changed\n')
        out = self.echo_on_host(exts)
        self.assertIn('toast=probe ok', out)
        listing = docker('exec', HOST, 'ls', '/root/.cache/rhun-remote/extensions/rhun-tests/echo').stdout.decode()
        self.assertEqual(len(listing.split()), 2, listing)

    @unittest.skipIf(sys.platform.startswith('linux'), 'a Linux client runs its own build on the host')
    def test_extension_linux_build_from_its_release(self):
        """An installed program extension whose folder holds this system's build only: its release's
        linux-x86_64 archive is fetched here once (RHUN_EXT_BASE serves the release from files),
        checked against the release's sha256sums.txt, and copied to the host."""
        import hashlib
        import tarfile
        docker('exec', HOST, 'rm', '-rf', '/root/.cache/rhun-remote/extensions', '/root/.local/state/rhun/extensions')
        manifest = (ROOT / 'tests/ext/exts/rhun-tests/echo/extension.ini').read_text(encoding='utf-8')
        manifest = manifest.replace('runtime = python3\nrun = ../../../echo.py\n',
                                    'run.linux-x86_64 = bin/echo-linux\nrun.macos-arm64 = bin/echo-mac\n'
                                    'run.windows-x64 = bin/echo.exe\n')
        launcher = '#!/bin/sh\nexec python3 "$(dirname "$0")/../echo.py"\n'
        # the release: echo-linux-x86_64.tar.gz and sha256sums.txt
        build = self.dir / 'build'
        (build / 'bin').mkdir(parents=True)
        (build / 'extension.ini').write_text(manifest, encoding='utf-8')
        (build / 'bin/echo-linux').write_text(launcher)
        (build / 'bin/echo-linux').chmod(0o755)
        shutil.copy(ROOT / 'tests/ext/echo.py', build / 'echo.py')
        release = self.dir / 'releases/rhun-tests/echo/releases/download/v1'
        release.mkdir(parents=True)
        archive = release / 'echo-linux-x86_64.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            for name in ('extension.ini', 'bin', 'bin/echo-linux', 'echo.py'):
                tar.add(build / name, arcname=name, recursive=False)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (release / 'sha256sums.txt').write_text('%s  echo-linux-x86_64.tar.gz\n' % digest)
        # installed here from that release, with this system's build only
        inst = self.dir / 'config/rhun/extensions/rhun-tests/echo'
        (inst / 'bin').mkdir(parents=True)
        (inst / 'extension.ini').write_text(manifest, encoding='utf-8')
        for name in ('echo-mac', 'echo.exe'):
            (inst / 'bin' / name).write_text(launcher)
            (inst / 'bin' / name).chmod(0o755)
        shutil.copy(ROOT / 'tests/ext/echo.py', inst / 'echo.py')
        (inst / '.rhun-install').write_text('source = github\nrepository = rhun-tests/echo\ntag = v1\n'
                                            'sha256 = %s\nreviewed = no\n' % digest)
        (self.dir / 'config/rhun/config').write_text('[remote]\nagent_binary = %s\n%s' % (LINUX_EXE, ECHO_CONFIG))
        out = self.run_script('docker:' + HOST, '/root/proj',
                              ['wait-remote 90', 'cmd echo.swrite', 'wait-ext echo running', 'wait 1500',
                               'print-toast', 'print-extensions'],
                              env_extra={'RHUN_EXT_BASE': (self.dir / 'releases').as_uri()})
        self.assertIn('toast=probe ok', out)
        self.assertTrue((self.dir / 'state/rhun/remote/extensions/rhun-tests--echo--v1/bin/echo-linux').is_file())
        docker('exec', HOST, 'test', '-f', '/root/.local/state/rhun/extensions/rhun-tests--echo/state.txt')
        log = (self.dir / 'state/rhun/remote.log').read_text()
        self.assertIn("extension's Linux build fetched into ", log)
        self.assertIn('extension copied: ', log)

    def test_extension_links_and_depth(self):
        """Its folder is copied whole or not at all: a link leading outside it, or folders nested
        deeper than 16 levels, stop it with the reason; a link inside it is copied as its target."""
        exts = echo_extension(self.dir / 'inside')
        os.symlink('echo.py', exts / 'rhun-tests/echo/alias.py')
        out = self.echo_on_host(exts)
        self.assertIn('toast=probe ok', out)
        exts = echo_extension(self.dir / 'outside')
        os.symlink('/etc/hosts', exts / 'rhun-tests/echo/hosts')
        out = self.echo_on_host(exts)
        self.assertIn('state=failed', ext_line(out), out)
        self.assertIn('a link to a place outside it, which is not copied to the host: hosts', ext_line(out))
        exts = echo_extension(self.dir / 'deep')
        deep = exts / 'rhun-tests/echo' / '/'.join(['d'] * 18)
        deep.mkdir(parents=True)
        (deep / 'x.txt').write_text('x')
        out = self.echo_on_host(exts)
        self.assertIn('state=failed', ext_line(out), out)
        self.assertIn('deeper than 16 levels', ext_line(out))

    @unittest.skipIf(sys.platform.startswith('linux'), 'a Linux client has the Linux build itself')
    def test_extension_with_only_a_linux_build(self):
        """No program for this system, only run.linux-x86_64 in its folder: the host's to run."""
        docker('exec', HOST, 'rm', '-rf', '/root/.local/state/rhun/extensions')
        exts = echo_extension(self.dir / 'exts', **{'runtime = python3\nrun = echo.py\n':
                                                    'run.linux-x86_64 = bin/echo-linux\n'})
        launcher = exts / 'rhun-tests/echo/bin/echo-linux'
        launcher.parent.mkdir()
        launcher.write_text('#!/bin/sh\nexec python3 "$(dirname "$0")/../echo.py"\n')
        launcher.chmod(0o755)
        out = self.echo_on_host(exts)
        self.assertIn('toast=probe ok', out)
        docker('exec', HOST, 'test', '-f', '/root/.local/state/rhun/extensions/rhun-tests--echo/state.txt')

    def test_where_local_runs_here(self):
        docker('exec', HOST, 'rm', '-rf', '/root/.local/state/rhun/extensions')
        needs = 'documents = write\nterminal = yes\nproject = read'
        exts = echo_extension(self.dir / 'exts', **{'on = command': 'on = command\nwhere = local',
                                                    needs: 'documents = write\nterminal = yes'})
        out = self.echo_on_host(exts)
        self.assertIn('toast=probe ok', out)
        self.assertTrue(list((self.dir / 'state').rglob('state.txt')), out)
        self.assertNotEqual(docker('exec', HOST, 'test', '-e', '/root/.local/state/rhun/extensions',
                                   check=False).returncode, 0)
        # where = local may not ask for the project
        exts = echo_extension(self.dir / 'exts2', **{'on = command': 'on = command\nwhere = local'})
        out = self.echo_on_host(exts)
        self.assertIn('state=failed', ext_line(out), out)
        self.assertIn('reason=where = local cannot go with project or home', ext_line(out))

    def test_failure_is_reported(self):
        out = self.run_script('docker:no-such-container-here', '', ['wait-remote 60', 'print-remote'])
        self.assertEqual(self.field(out, 'remote=', 'state'), 'failed', out)
        self.assertIn('error=Could not connect to no-such-container-here', out)

class LocalWindow(unittest.TestCase):
    def test_where_local_needs_nothing_special_in_a_local_window(self):
        """where = local only limits a remote window's extensions: a local window loads it with
        project = read as any other."""
        with tempfile.TemporaryDirectory(prefix='rhun-remote-lw-') as tmp:
            base = Path(tmp)
            for d in ('home', 'config/rhun', 'state', 'proj'):
                (base / d).mkdir(parents=True)
            (base / 'config/rhun/config').write_text(ECHO_CONFIG)
            exts = echo_extension(base / 'exts', **{'on = command': 'on = command\nwhere = local'})
            script = base / 't.rsc'
            script.write_text('print-extensions\nquit\n')
            env = dict(os.environ, HOME=str(base / 'home'), XDG_CONFIG_HOME=str(base / 'config'),
                       XDG_STATE_HOME=str(base / 'state'))
            out = subprocess.run([str(EXE), str(base / 'proj'), '--headless', '800x600', '--extensions', str(exts),
                                  '--script', str(script)], capture_output=True, timeout=60,
                                 env=env).stdout.decode(errors='replace')
            self.assertIn('state=idle', ext_line(out), out)


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


    def test_extension_on_the_host(self):
        """The echo extension in a local: window runs as the host's: its files in the host's cache,
        its state folder the host's ($HOME/.local/state, not XDG_STATE_HOME)."""
        with tempfile.TemporaryDirectory(prefix='rhun-remote-ext-') as tmp:
            base = Path(tmp)
            for d in ('home', 'config/rhun', 'state', 'proj'):
                (base / d).mkdir(parents=True)
            (base / 'config/rhun/config').write_text(ECHO_CONFIG)
            exts = echo_extension(base / 'exts')
            script = base / 't.rsc'
            script.write_text('wait-remote 60\ncmd echo.swrite\nwait-ext echo running\nwait 1500\nprint-toast\n'
                              'print-extensions\nquit\n')
            env = dict(os.environ, HOME=str(base / 'home'), XDG_CONFIG_HOME=str(base / 'config'),
                       XDG_STATE_HOME=str(base / 'state'), SHELL='/bin/sh')
            out = subprocess.run([str(EXE), '--headless', '1000x700', '--remote', 'local:', str(base / 'proj'),
                                  '--extensions', str(exts), '--script', str(script)], capture_output=True,
                                 timeout=120, env=env).stdout.decode(errors='replace')
            self.assertIn('toast=probe ok', out)
            self.assertIn('state=running', ext_line(out), out)
            self.assertTrue((base / 'home/.local/state/rhun/extensions/rhun-tests--echo/state.txt').is_file())
            self.assertFalse(list((base / 'state').rglob('state.txt')))
            self.assertEqual(len(list((base / 'home/.cache/rhun-remote/extensions/rhun-tests/echo').iterdir())), 1)

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
