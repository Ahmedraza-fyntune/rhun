#!/usr/bin/env python3
"""The remote agent (`rhun --remote-agent`, src/app/ragent.s) spoken to directly over its standard
input and output with the mux protocol (src/app/remote.s, top): the hello, programs on pipes and
pseudo-terminals with flow control, exits and kills, and the file system requests a remote window
makes. Linux only (the agent is a Linux program); each run gets its own HOME."""
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()


class Agent:
    """One agent process and a reader for its stream."""

    def __init__(self, home, env_extra=None):
        env = {'HOME': str(home), 'PATH': '/usr/local/bin:/usr/bin:/bin', 'SHELL': '/bin/sh',
               'USER': 'tester'}
        env.update(env_extra or {})
        self.p = subprocess.Popen([str(EXE), '--remote-agent'], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        self.buf = b''
        self.next_id = 1
        self.data = {}          # channel -> bytes received
        self.eof = set()
        self.exits = {}
        self.credit = {}        # channel -> credit the agent gave back
        self.events = []
        self.replies = {}
        line = self.line(10)
        assert line.startswith(b'hello rhun-remote '), line
        self.hello = line

    def close(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        try:
            self.p.wait(5)
        except subprocess.TimeoutExpired:
            self.p.kill()
            self.p.wait()

    def send(self, data):
        self.p.stdin.write(data)
        self.p.stdin.flush()

    def fill(self, timeout):
        r, _, _ = select.select([self.p.stdout], [], [], timeout)
        if not r:
            return False
        chunk = os.read(self.p.stdout.fileno(), 1 << 20)
        if not chunk:
            raise EOFError('the agent closed its output')
        self.buf += chunk
        return True

    def line(self, timeout):
        end = time.time() + timeout
        while b'\n' not in self.buf:
            if not self.fill(max(0, end - time.time())) and time.time() >= end:
                raise TimeoutError(self.buf)
        line, self.buf = self.buf.split(b'\n', 1)
        return line

    def pump(self, timeout=0.2):
        """Handle every complete message that arrives within timeout."""
        end = time.time() + timeout
        while True:
            while self.one():
                pass
            left = end - time.time()
            if left <= 0:
                return
            self.fill(left)

    def one(self):
        if b'\n' not in self.buf:
            return False
        head, rest = self.buf.split(b'\n', 1)
        f = head.split(b' ')
        kind = f[0]
        need = 0
        if kind == b'd':
            need = int(f[2])
        elif kind == b'ok':
            need = int(f[2])
        elif kind == b'v':
            need = int(f[3])
        if len(rest) < need:
            return False
        body, self.buf = rest[:need], rest[need:]
        if kind == b'd':
            self.data[int(f[1])] = self.data.get(int(f[1]), b'') + body
        elif kind == b'e':
            self.eof.add(int(f[1]))
        elif kind == b'x':
            self.exits[int(f[1])] = int(f[2])
        elif kind == b'w':
            self.credit[int(f[1])] = self.credit.get(int(f[1]), 0) + int(f[2])
        elif kind == b'v':
            self.events.append((int(f[1]), int(f[2]), body))
        elif kind == b'ok':
            self.replies[int(f[1])] = ('ok', body)
        elif kind == b'error':
            self.replies[int(f[1])] = ('error', int(f[2]))
        return True

    def call(self, line, body=b'', timeout=10):
        rid = self.next_id
        self.next_id += 1
        self.send(b'%d %s %d\n' % (rid, line.encode(), len(body)) + body)
        end = time.time() + timeout
        while rid not in self.replies:
            if time.time() > end:
                raise TimeoutError(line)
            self.pump(0.05)
        return self.replies.pop(rid)

    def wait_for(self, cond, timeout=10):
        end = time.time() + timeout
        while not cond():
            if time.time() > end:
                raise TimeoutError
            self.pump(0.05)


def spawn_body(argv, cwd='', env=()):
    out = cwd.encode() + b'\0'
    for a in argv:
        out += a.encode() + b'\0'
    out += b'\0'
    for e in env:
        out += e.encode() + b'\0'
    return out


@unittest.skipUnless(sys.platform.startswith('linux'), 'the agent is a Linux program')
class RemoteAgent(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / 'home'
        self.home.mkdir()
        self.agent = Agent(self.home)

    def tearDown(self):
        self.agent.close()
        self.tmp.cleanup()

    def test_hello_and_info(self):
        f = self.agent.hello.split(b' ')
        self.assertEqual(len(f), 4)
        self.assertEqual(len(f[3]), 16)
        kind, body = self.agent.call('info')
        self.assertEqual(kind, 'ok')
        self.assertIn(b'home=%s\n' % str(self.home).encode(), body)
        self.assertIn(b'shell=/bin/sh\n', body)

    def test_pipe_program(self):
        a = self.agent
        kind, body = a.call('spawn 3 0 3 0 0', spawn_body(['sh', '-c', 'echo out; echo err >&2; exit 7'],
                                                        str(self.home)))
        self.assertEqual(kind, 'ok', body)
        self.assertGreater(int(body), 0)
        a.wait_for(lambda: 3 in a.exits and 3 in a.eof)
        self.assertEqual(a.exits[3], 7)
        self.assertEqual(sorted(a.data[3].split()), [b'err', b'out'])

    def test_input_and_credit(self):
        a = self.agent
        kind, _ = a.call('spawn 5 0 0 0 0', spawn_body(['cat']))
        self.assertEqual(kind, 'ok')
        payload = b'x' * 300000
        a.send(b'd 5 %d\n' % len(payload) + payload + b'e 5\n')
        a.wait_for(lambda: 5 in a.eof and len(a.data.get(5, b'')) == len(payload))
        self.assertEqual(a.data[5], payload)
        a.wait_for(lambda: a.credit.get(5, 0) == len(payload))
        a.wait_for(lambda: a.exits.get(5) == 0)

    def test_flow_control_stops_reading(self):
        a = self.agent
        kind, _ = a.call('spawn 6 0 0 0 0', spawn_body(['head', '-c', '3000000', '/dev/zero']))
        self.assertEqual(kind, 'ok')
        # the window is 1 MB: without credit no more comes
        a.pump(1.0)
        self.assertEqual(len(a.data.get(6, b'')), 1048576)
        a.send(b'w 6 4000000\n')
        a.wait_for(lambda: 6 in a.eof)
        self.assertEqual(len(a.data[6]), 3000000)

    def test_error_channel(self):
        a = self.agent
        kind, _ = a.call('spawn 7 0 8 0 0', spawn_body(['sh', '-c', 'echo o; echo e >&2']))
        self.assertEqual(kind, 'ok')
        a.wait_for(lambda: 7 in a.eof and 8 in a.eof)
        self.assertEqual(a.data[7], b'o\n')
        self.assertEqual(a.data[8], b'e\n')

    def test_env_and_path_lookup(self):
        a = self.agent
        kind, _ = a.call('spawn 9 0 0 0 0', spawn_body(['/bin/sh', '-c', 'echo "$RHUN_X:$HOME"'],
                                                     env=['RHUN_X=yes']))
        self.assertEqual(kind, 'ok')
        a.wait_for(lambda: 9 in a.eof)
        self.assertEqual(a.data[9], b'yes:%s\n' % str(self.home).encode())
        kind, err = a.call('spawn 10 0 0 0 0', spawn_body(['no-such-program-here']))
        self.assertEqual((kind, err), ('error', 2))

    def test_pty_shell_kill_resize(self):
        a = self.agent
        kind, body = a.call('spawn 11 1 0 100 30', spawn_body([], str(self.home), ['TERM=dumb']))
        self.assertEqual(kind, 'ok', body)
        a.send(b'd 11 22\nstty size; echo hi-$$\n')
        a.wait_for(lambda: b'30 100' in a.data.get(11, b'') and b'hi-' in a.data.get(11, b''))
        self.assertEqual(a.call('resize 11 120 40')[0], 'ok')
        a.send(b'd 11 10\nstty size\n')
        a.wait_for(lambda: b'40 120' in a.data.get(11, b''))
        self.assertEqual(a.call('kill 11 9 1')[0], 'ok')
        a.wait_for(lambda: 11 in a.exits)
        self.assertEqual(a.exits[11], 128 + 9)

    def test_terminal_close_hangs_up(self):
        a = self.agent
        kind, _ = a.call('spawn 12 1 0 80 24', spawn_body(['sh']))
        self.assertEqual(kind, 'ok')
        a.send(b'e 12\n')
        a.wait_for(lambda: 12 in a.exits)
        self.assertEqual(a.exits[12], 128 + 1)

    def test_busy_channel(self):
        a = self.agent
        self.assertEqual(a.call('spawn 13 0 0 0 0', spawn_body(['sleep', '5']))[0], 'ok')
        self.assertEqual(a.call('spawn 13 0 0 0 0', spawn_body(['true'])), ('error', 16))
        self.assertEqual(a.call('kill 13 15 0')[0], 'ok')
        a.wait_for(lambda: 13 in a.exits)

    def test_files(self):
        a = self.agent
        d = self.home / 'proj'
        p = str(d).encode()
        self.assertEqual(a.call('mkdir 1', p + b'/sub/deep')[0], 'ok')
        self.assertTrue((d / 'sub/deep').is_dir())
        f = p + b'/a.txt'
        self.assertEqual(a.call('write 2 644 %d' % len(f), f + b'hello\n')[0], 'ok')
        self.assertEqual((d / 'a.txt').read_bytes(), b'hello\n')
        self.assertEqual(a.call('write 2 644 %d' % len(f), f + b'again'), ('error', 17))
        self.assertEqual(a.call('write 1 644 %d' % len(f), f + b'replaced\n')[0], 'ok')
        self.assertEqual(a.call('write 4 644 %d' % len(f), f + b'more\n')[0], 'ok')
        self.assertEqual((d / 'a.txt').read_bytes(), b'replaced\nmore\n')
        self.assertEqual(a.call('read 0 100', f), ('ok', b'replaced\nmore\n'))
        self.assertEqual(a.call('read 3 4', f), ('ok', b'lace'))
        kind, st = a.call('stat', f)
        self.assertEqual(kind, 'ok')
        self.assertEqual(len(st), 144)
        self.assertEqual(int.from_bytes(st[48:56], 'little'), 14)
        self.assertEqual(a.call('stat', p + b'/missing'), ('error', 2))
        os.symlink('a.txt', d / 'link')
        self.assertEqual(a.call('readlink', p + b'/link'), ('ok', b'a.txt'))
        self.assertEqual(a.call('realpath', p + b'/sub/../link'), ('ok', f))
        kind, listing = a.call('list', p)
        self.assertEqual(kind, 'ok')
        entries = sorted(e for e in listing.split(b'\0') if e)
        self.assertEqual(entries, [b'd sub', b'f a.txt', b'l link'])
        b2 = p + b'/b.txt'
        self.assertEqual(a.call('rename 0 %d' % len(f), f + b2)[0], 'ok')
        self.assertTrue((d / 'b.txt').exists())
        (d / 'c.txt').write_text('c')
        self.assertEqual(a.call('rename 1 %d' % len(b2), b2 + p + b'/c.txt'), ('error', 17))
        self.assertEqual(a.call('remove 0', p + b'/sub'), ('error', 39))
        self.assertEqual(a.call('remove 1', p + b'/sub')[0], 'ok')
        self.assertFalse((d / 'sub').exists())
        self.assertEqual(a.call('remove 0', b2)[0], 'ok')
        self.assertFalse((d / 'b.txt').exists())

    def test_links_access_and_parts(self):
        a = self.agent
        d = self.home / 'p'
        (d / 'sub').mkdir(parents=True)
        (d / 'f').write_text('x')
        os.symlink('sub', d / 'tosub')
        os.symlink('f', d / 'tof')
        os.symlink('missing', d / 'dangling')
        p = str(d).encode()
        kind, listing = a.call('list', p)
        self.assertEqual(sorted(e for e in listing.split(b'\0') if e),
                         [b'L tosub', b'd sub', b'f f', b'l dangling', b'l tof'])
        self.assertEqual(a.call('access 2', p + b'/f')[0], 'ok')
        self.assertEqual(a.call('access 2', p + b'/none'), ('error', 2))
        big = p + b'/big'
        self.assertEqual(a.call('write 8 600 %d' % len(big), big + b'one,')[0], 'ok')
        self.assertEqual(a.call('write 4 600 %d' % len(big), big + b'two')[0], 'ok')
        self.assertEqual((d / 'big').read_bytes(), b'one,two')
        self.assertEqual(oct((d / 'big').stat().st_mode & 0o777), '0o600')

    def test_files_and_grep(self):
        a = self.agent
        d = self.home / 'proj'
        (d / 'src/deep').mkdir(parents=True)
        (d / '.git').mkdir()
        (d / 'node_modules').mkdir()
        (d / 'src/a.rs').write_text('fn main() {\n    let Needle = 1;\n}\n')
        (d / 'src/deep/b.txt').write_text('needle here\nnothing\n\t\tneedle again\n')
        (d / 'node_modules/x.js').write_text('needle')
        (d / '.git/config').write_text('needle')
        (d / 'bin.dat').write_bytes(b'needle\0\1\2')
        body = str(d).encode() + b'\0.git node_modules'
        kind, files = a.call('files 1000', body)
        self.assertEqual(kind, 'ok')
        self.assertEqual(sorted(f for f in files.split(b'\0') if f), [b'bin.dat', b'src/a.rs', b'src/deep/b.txt'])
        kind, out = a.call('files 1', body)
        self.assertEqual(len([f for f in out.split(b'\0') if f]), 1)
        kind, out = a.call('grep 100 0', body + b'\0needle')
        self.assertEqual(kind, 'ok')
        f = out.split(b'\0')
        recs = [tuple(f[i:i + 4]) for i in range(0, len(f) - 1, 4)]
        self.assertEqual(sorted(recs), [(b'src/a.rs', b'1', b'8', b'let Needle = 1;'),
                                        (b'src/deep/b.txt', b'0', b'0', b'needle here'),
                                        (b'src/deep/b.txt', b'2', b'2', b'needle again')])
        kind, out = a.call('grep 100 1', body + b'\0Needle')
        self.assertEqual(out.split(b'\0')[:2], [b'src/a.rs', b'1'])
        self.assertEqual(len(out.split(b'\0')), 5)

    def test_watch(self):
        a = self.agent
        d = self.home / 'w'
        d.mkdir()
        p = str(d).encode()
        kind, wd = a.call('watch %d' % (0x2 | 0x8 | 0x100 | 0x200 | 0x40 | 0x80), p)
        self.assertEqual(kind, 'ok')
        (d / 'new.txt').write_text('x')
        a.wait_for(lambda: any(e[2] == b'new.txt' and e[1] & 0x100 for e in a.events))
        self.assertTrue(all(e[0] == int(wd) for e in a.events))
        self.assertEqual(a.call('unwatch %d' % int(wd))[0], 'ok')

    def test_unknown_verb_and_garbage(self):
        a = self.agent
        self.assertEqual(a.call('frobnicate'), ('error', 38))
        # data for a channel that is not there is dropped
        a.send(b'd 900 3\nabc')
        self.assertEqual(a.call('info')[0], 'ok')

    def test_quit_ends_programs(self):
        a = self.agent
        kind, body = a.call('spawn 14 0 0 0 0', spawn_body(['sleep', '30']))
        self.assertEqual(kind, 'ok')
        pid = int(body)
        a.send(b'0 quit 0\n')
        a.p.wait(5)
        end = time.time() + 5
        while time.time() < end:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.05)
        else:
            self.fail('sleep outlived the agent')

    def test_login_environment(self):
        """The login shell's profile reaches programs (a PATH entry like ~/.cargo/bin)."""
        self.agent.close()
        (self.home / '.profile').write_text('export RHUN_FROM_PROFILE=1\necho noise\n')
        a = self.agent = Agent(self.home)
        kind, _ = a.call('spawn 15 0 0 0 0', spawn_body(['sh', '-c', 'echo "$RHUN_FROM_PROFILE"']))
        self.assertEqual(kind, 'ok')
        a.wait_for(lambda: 15 in a.eof)
        self.assertEqual(a.data[15], b'1\n')


if __name__ == '__main__':
    unittest.main()
