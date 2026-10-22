#!/usr/bin/env python3
"""Counted Wayland clipboard transfers on a private headless compositor."""
import json
import os
from pathlib import Path
import select
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
AVAILABLE = sys.platform == 'linux' and all(shutil.which(x) for x in ('sway', 'swaymsg', 'cc'))


@unittest.skipUnless(AVAILABLE and os.geteuid() != 0, 'unprivileged Linux Sway required')
class Clipboard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='rhun-wayland-clipboard-')
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.base = Path(cls.tmp.name)
        runtime = cls.base / 'runtime'
        runtime.mkdir(mode=0o700)
        config = cls.base / 'sway.conf'
        config.write_text('output * resolution 1280x800\n')
        cls.env = dict(os.environ, HOME=str(cls.base), XDG_RUNTIME_DIR=str(runtime),
                       WLR_BACKENDS='headless', WLR_LIBINPUT_NO_DEVICES='1', WLR_RENDERER='pixman')
        cls.env.pop('DISPLAY', None)
        cls.env.pop('WAYLAND_DISPLAY', None)
        cls.logs = []
        cls.processes = []
        cls.addClassCleanup(cls.stop_processes)
        cls.start(['sway', '-d', '-c', str(config)], 'compositor')
        deadline = time.monotonic() + 15
        while not list(runtime.glob('sway-ipc.*.sock')):
            assert cls.processes[0].poll() is None, (cls.base / 'compositor.log').read_text()
            assert time.monotonic() < deadline, 'compositor did not start'
            time.sleep(.025)
        cls.env['SWAYSOCK'] = str(next(runtime.glob('sway-ipc.*.sock')))
        cls.env['WAYLAND_DISPLAY'] = next(p.name for p in runtime.glob('wayland-*')
                                        if not p.name.endswith('.lock'))
        cls.peer_binary = cls.base / 'clipboard-owner'
        keyboard_binary = cls.base / 'keyboard'
        for source, binary in [('wayland-clipboard.c', cls.peer_binary),
                               ('wayland-keyboard.c', keyboard_binary)]:
            subprocess.run(['cc', '-Wall', '-Wextra', '-Wno-unused-parameter',
                            str(ROOT / 'tests' / source), '-lwayland-client', '-o', str(binary)],
                           check=True)
        cls.keyboard = cls.start([str(keyboard_binary), str(ROOT / 'tests/data/keymap-gnome-us.txt')],
                                 'keyboard', stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        assert cls.line(cls.keyboard) == b'ready\n'

    @classmethod
    def start(cls, arguments, name, **kwargs):
        log = open(cls.base / (name + '.log'), 'wb')
        cls.logs.append(log)
        kwargs.setdefault('stdout', log)
        kwargs.setdefault('bufsize', 0)  # select must not miss prefetched handshake lines
        process = subprocess.Popen(arguments, env=cls.env, stderr=log, **kwargs)
        cls.processes.append(process)
        return process

    @staticmethod
    def stop(process):
        if process is None:
            return
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        if process.stdin:
            process.stdin.close()
        if process.stdout:
            process.stdout.close()

    @classmethod
    def stop_processes(cls):
        for process in reversed(cls.processes):
            cls.stop(process)
        for log in cls.logs:
            log.close()

    @staticmethod
    def line(process, seconds=10):
        assert select.select([process.stdout], [], [], seconds)[0], 'peer did not respond'
        line = process.stdout.readline()
        assert line, ('peer exited', process.poll())
        return line

    def setUp(self):
        self.work = Path(tempfile.mkdtemp(prefix='case-', dir=self.base))
        self.addCleanup(shutil.rmtree, self.work)
        self.owner = self.editor = self.client = self.reader = None
        self.addCleanup(self.stop_case)
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          'final_newline = false\n[ui]\nsidebar = false\nagents_panel = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n')
        self.document = self.work / 'document.txt'
        self.document.write_bytes(b'original')

    def stop_case(self):
        if self.reader:
            self.reader.close()
        if self.client:
            self.client.close()
        self.stop(self.editor)
        self.stop(self.owner)

    def start_case(self, data, mimes=('text/plain;charset=utf-8',)):
        if data is not None:
            payload = self.work / 'payload'
            payload.write_bytes(data)
            self.owner = self.start([str(self.peer_binary), str(payload), *mimes],
                                    self.work.name + '-owner', stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE)
            self.assertEqual(self.line(self.owner), b'ready\n')
        env = dict(self.env, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                   XDG_STATE_HOME=str(self.work / 'state'),
                   SHELL=str(getattr(self, 'test_shell', '/nonexistent')))
        control = self.work / 'control'
        log = open(self.work / 'editor.log', 'wb')
        self.logs.append(log)
        self.editor = subprocess.Popen([str(EXE), str(self.document), '--control', str(control)],
                                       env=env, stdout=log, stderr=log)
        deadline = time.monotonic() + 15
        while not control.exists():
            self.alive()
            self.assertLess(time.monotonic(), deadline, 'editor did not start')
            time.sleep(.025)
        self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.client.settimeout(10)
        self.client.connect(str(control))
        self.reader = self.client.makefile('rb')
        while True:
            state = subprocess.check_output(['swaymsg', '-t', 'get_tree', '-r'], env=self.env)
            def focused(node):
                return (node.get('app_id') == 'rhun' and node.get('focused')) or any(
                    focused(child) for child in node.get('nodes', []) + node.get('floating_nodes', []))
            if focused(json.loads(state)):
                break
            self.alive()
            self.assertLess(time.monotonic(), deadline, 'editor did not get keyboard focus')
            time.sleep(.025)
        self.command('wait 50')
        self.assertIn(b'tabs=1', self.command('print-state'))
        self.command('cmd select_all')

    def alive(self):
        self.assertIsNone(self.editor.poll(), (self.work / 'editor.log').read_text())

    def command(self, text):
        self.client.sendall(text.encode() + b'\n')
        result = []
        while True:
            line = self.reader.readline()
            self.assertNotIn(line, (b'', b'error\n'),
                             (text, (self.work / 'editor.log').read_text()))
            if line == b'ok\n':
                return b''.join(result)
            result.append(line)

    def pipe_present(self, inode):
        self.alive()
        for path in Path('/proc/' + str(self.editor.pid) + '/fd').iterdir():
            try:
                if os.readlink(path) == 'pipe:[' + inode + ']':
                    return True
            except FileNotFoundError:
                pass
        return False

    def wait_pipe(self, inode):
        deadline = time.monotonic() + 10
        while not self.pipe_present(inode):
            self.assertLess(time.monotonic(), deadline, 'sender write end not observed')
            time.sleep(.005)

    def request(self, expected_mime):
        self.command('cmd paste')
        return self.owner_request(expected_mime)

    def owner_request(self, expected_mime):
        line = self.line(self.owner).decode().strip().split()
        self.assertEqual(line[:2], ['request', expected_mime])
        inode = line[2]
        self.assertTrue(inode.isdigit())
        self.assertTrue(self.pipe_present(inode), 'receiver read end not observed')
        return inode

    def release_owner(self, inode):
        self.owner.stdin.write(b'finish\n')
        self.owner.stdin.flush()
        self.assertEqual(self.line(self.owner), b'closed 0\n')
        deadline = time.monotonic() + 10
        while self.pipe_present(inode):
            self.assertLess(time.monotonic(), deadline, 'receiver did not finish before timeout')
            time.sleep(.005)

    def finish(self, inode, expected, save=True):
        self.release_owner(inode)
        self.assertEqual(self.command('print-doc'), expected + b'\n<eod>\n')
        if save:
            self.command('cmd save')
            self.assertEqual(self.document.read_bytes(), expected)

    def set_owner_payload(self, text):
        self.owner.stdin.write(b'set ' + text + b'\n')
        self.owner.stdin.flush()
        self.assertEqual(self.line(self.owner), b'updated\n')

    native_mime = 'application/x-rhun-clipboard-v1'

    @staticmethod
    def wire(text, line=False, segments=(), version=1):
        return (struct.pack('<8sIIQQ', b'RHUNCLP\0', version, int(line), len(segments), len(text)) +
                b''.join(struct.pack('<QQ', *piece) for piece in segments) + text)

    def formats_owner(self, native, plain=b'fallback'):
        self.stop(self.owner)
        paths = []
        for name, data in (('native', native), ('plain', plain)):
            path = self.work / ('format-' + name)
            if data is None:
                paths.append('-')
            else:
                path.write_bytes(data)
                paths.append(str(path))
        self.owner = self.start([str(self.peer_binary), '--formats', *paths],
                                self.work.name + '-formats', stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE)
        self.assertEqual(self.line(self.owner), b'ready\n')
        if self.editor is None:
            self.start_case(None)
        else:
            self.command('wait 50')

    def test_outgoing_native_and_advertised_formats(self):
        data = b'x' * 1048576 + 'é水😀\0tail'.encode()
        self.outgoing(data)
        peer, output, inode = self.receiver('native', self.native_mime)
        self.wait_pipe(inode)
        peer.stdin.write(b'formats\n')
        peer.stdin.flush()
        self.assertEqual(self.line(peer), b'formats 15\n')
        self.drain(peer, output, self.wire(data))
        peer, output, _ = self.receiver('plain')
        self.drain(peer, output, data)

    def test_outgoing_native_mixed_readers_survive_replacement_and_loss(self):
        data = b'x' * 1048576 + 'é\0水'.encode()
        self.outgoing(data)
        native = self.receiver('native', self.native_mime)
        plain = self.receiver('plain')
        for _, _, inode in (native, plain):
            self.wait_pipe(inode)
        self.command('type replacement')
        self.command('cmd select_all')
        self.command('cmd copy')
        self.command('wait 50')
        self.formats_owner(self.wire(b'foreign'))
        self.drain(native[0], native[1], self.wire(data))
        self.drain(plain[0], plain[1], data)

    def test_incoming_native_preference_unicode_nul(self):
        data = 'é\0水😀'.encode()
        self.formats_owner(self.wire(data), b'different plain')
        self.finish(self.request(self.native_mime), data)
        self.assertFalse(select.select([self.owner.stdout], [], [], .1)[0])

    def test_incoming_native_line(self):
        self.document.write_bytes(b'abc')
        self.formats_owner(self.wire(b'L\n', line=True))
        self.command('key Home')
        self.command('key Right')
        self.finish(self.request(self.native_mime), b'L\nabc')

    def test_incoming_native_large(self):
        data = 'é水😀\0'.encode() + b'x' * 1048576
        self.formats_owner(self.wire(data), b'different plain')
        self.finish(self.request(self.native_mime), data)

    def test_incoming_native_empty_is_authoritative(self):
        self.formats_owner(self.wire(b''), b'must not appear')
        self.finish(self.request(self.native_mime), b'original')
        self.assertFalse(select.select([self.owner.stdout], [], [], .1)[0])

    def test_incoming_native_only_invalid_and_successor(self):
        self.formats_owner(b'broken', None)
        self.finish(self.request(self.native_mime), b'original')
        self.formats_owner(self.wire(b'valid'), None)
        self.finish(self.request(self.native_mime), b'valid')

    def test_incoming_native_malformed_fallback(self):
        cases = [b'broken', self.wire(b'native', version=2),
                 self.wire('é'.encode(), segments=((0, 1),)), self.wire(b'\xff')]
        for native in cases:
            with self.subTest(native=native):
                self.formats_owner(native)
                self.command('cmd select_all')
                inode = self.request(self.native_mime)
                self.release_owner(inode)
                inode = self.owner_request('text/plain;charset=utf-8')
                self.finish(inode, b'fallback')
                self.command('cmd undo')
                self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')

    def test_incoming_native_stale_and_queued_successor(self):
        self.formats_owner(self.wire(b'native'))
        inode = self.request(self.native_mime)
        self.command('key End')
        self.command('cmd paste')
        self.finish(inode, b'original', save=False)
        inode = self.owner_request(self.native_mime)
        self.finish(inode, b'originalnative')

    def test_incoming_native_fallback_queue(self):
        self.formats_owner(self.wire(b'wrong version', version=2), b'first')
        inode = self.request(self.native_mime)
        self.command('cmd paste')
        self.release_owner(inode)
        inode = self.owner_request('text/plain;charset=utf-8')
        self.finish(inode, b'first', save=False)
        inode = self.owner_request(self.native_mime)
        self.release_owner(inode)
        inode = self.owner_request('text/plain;charset=utf-8')
        self.finish(inode, b'firstfirst')
        for data in (b'first', b'original'):
            self.command('cmd undo')
            self.assertEqual(self.command('print-doc'), data + b'\n<eod>\n')

    def test_incoming_native_selection_change_blocks_fallback(self):
        self.formats_owner(b'broken', b'old plain')
        inode = self.request(self.native_mime)
        old = self.owner
        native_path, plain_path = self.work / 'new-native', self.work / 'new-plain'
        native_path.write_bytes(self.wire(b'fresh'))
        plain_path.write_bytes(b'unrelated plain')
        self.owner = self.start([str(self.peer_binary), '--formats', str(native_path), str(plain_path)],
                                self.work.name + '-new-owner', stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE)
        self.addCleanup(self.stop, old)
        self.assertEqual(self.line(self.owner), b'ready\n')
        self.assertEqual(self.line(old), b'cancelled\n')
        self.command('wait 50')
        old.stdin.write(b'finish\n')
        old.stdin.flush()
        self.assertEqual(self.line(old), b'closed 0\n')
        deadline = time.monotonic() + 10
        while self.pipe_present(inode):
            self.assertLess(time.monotonic(), deadline, 'old native pipe did not finish')
            time.sleep(.005)
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')
        self.assertFalse(select.select([self.owner.stdout], [], [], .1)[0])
        self.finish(self.request(self.native_mime), b'fresh')

    def test_outgoing_native_line_to_live_rhun(self):
        self.document.write_bytes(b'L\nabc')
        self.start_case(None)
        self.command('key ctrl+Home')
        self.command('cmd copy')
        self.command('wait 50')
        peer, output, _ = self.receiver('line', self.native_mime)
        self.drain(peer, output, self.wire(b'L\n', line=True))
        reader = Clipboard()
        try:
            reader.setUp()
            reader.document.write_bytes(b'abc')
            reader.start_case(None)
            reader.command('key Home')
            reader.command('key Right')
            reader.command('cmd paste')
            expected = b'L\nabc\n<eod>\n'
            deadline = time.monotonic() + 10
            while reader.command('print-doc') != expected:
                self.assertLess(time.monotonic(), deadline, 'peer clipboard delivery did not finish')
                reader.command('wait 25')
            reader.command('cmd save')
            self.assertEqual(reader.document.read_bytes(), b'L\nabc')
        finally:
            self.assertTrue(reader.doCleanups())

    def test_outgoing_native_empty(self):
        self.outgoing(b'')
        peer, output, _ = self.receiver('empty-native', self.native_mime)
        self.drain(peer, output, self.wire(b'', line=True))

    def test_incoming_delayed_vim_visual_paste(self):
        self.start_case(b'X')
        self.command('cmd toggle_vim')
        self.command('key Escape')
        self.command('type gg0vl')
        self.assertIn(b'vim=visual', self.command('print-state'))
        self.command('key ctrl+v')
        inode = self.owner_request('text/plain;charset=utf-8')
        self.command('wait 100')
        self.assertIn(b'vim=visual', self.command('print-state'))
        self.finish(inode, b'Xiginal')

    def test_incoming_delayed_target_switch(self):
        self.start_case(b'late')
        inode = self.request('text/plain;charset=utf-8')
        self.command('cmd new_file')
        self.command('type second')
        self.release_owner(inode)
        self.assertEqual(self.command('print-doc'), b'second\n<eod>\n')
        self.command('cmd prev_tab')
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')

    def test_incoming_delayed_selection_change(self):
        self.start_case(b'late')
        inode = self.request('text/plain;charset=utf-8')
        self.command('key End')
        self.finish(inode, b'original')

    def test_incoming_delayed_close_reopen(self):
        self.start_case(b'late')
        inode = self.request('text/plain;charset=utf-8')
        self.command('cmd close_tab')
        self.command('open ' + str(self.document))
        self.finish(inode, b'original')

    def test_incoming_delayed_edit(self):
        self.start_case(b'late')
        inode = self.request('text/plain;charset=utf-8')
        self.command('type changed')
        self.finish(inode, b'changed')

    def test_incoming_queued_pastes_keep_order(self):
        self.start_case(b'first')
        inode = self.request('text/plain;charset=utf-8')
        self.command('cmd paste')
        self.command('cmd paste')
        self.finish(inode, b'first', save=False)
        inode = self.owner_request('text/plain;charset=utf-8')
        self.set_owner_payload(b'second')
        self.finish(inode, b'firstsecond', save=False)
        inode = self.owner_request('text/plain;charset=utf-8')
        self.set_owner_payload(b'third')
        self.finish(inode, b'firstsecondthird')
        for expected in (b'firstsecond', b'first', b'original'):
            self.command('cmd undo')
            self.assertEqual(self.command('print-doc'), expected + b'\n<eod>\n')
        for expected in (b'first', b'firstsecond', b'firstsecondthird'):
            self.command('cmd redo')
            self.assertEqual(self.command('print-doc'), expected + b'\n<eod>\n')

    def test_incoming_queue_after_invalid_transfer(self):
        self.start_case(b'\xff')
        inode = self.request('text/plain;charset=utf-8')
        self.command('cmd paste')
        self.finish(inode, b'original')
        inode = self.owner_request('text/plain;charset=utf-8')
        self.set_owner_payload(b'valid')
        self.finish(inode, b'valid')

    def test_incoming_delayed_terminal_switch(self):
        records = self.work / 'terminal-input'
        records.mkdir()
        self.test_shell = self.work / 'test-shell'
        self.test_shell.write_text(
            '#!/usr/bin/python3\nimport os, tty\nfrom pathlib import Path\n'
            'tty.setraw(0)\n'
            'path = Path(' + repr(str(records)) + ') / str(os.getpid())\n'
            'path.touch()\n'
            'while True:\n'
            ' data = os.read(0, 4096)\n'
            ' if not data: break\n'
            ' with path.open("ab") as output: output.write(data)\n')
        self.test_shell.chmod(0o700)
        self.start_case(b'late\n')

        def until(predicate):
            deadline = time.monotonic() + 10
            while not predicate():
                self.alive()
                self.assertLess(time.monotonic(), deadline, 'terminal did not respond')
                time.sleep(.005)

        self.command('cmd toggle_terminal')
        until(lambda: len(list(records.iterdir())) == 1)
        first = next(records.iterdir())
        inode = self.request('text/plain;charset=utf-8')
        self.command('cmd new_terminal')
        until(lambda: len(list(records.iterdir())) == 2)
        second = next(path for path in records.iterdir() if path != first)
        self.release_owner(inode)
        self.set_owner_payload(b'fresh')
        inode = self.request('text/plain;charset=utf-8')
        self.release_owner(inode)
        until(lambda: b'fresh' in second.read_bytes())
        self.assertEqual(second.read_bytes(), b'fresh')
        self.command('cmd prev_tab')
        self.command('type barrier')
        until(lambda: b'barrier' in first.read_bytes())
        self.assertEqual(first.read_bytes(), b'barrier')
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')

    def receiver(self, name='reader', mime='text/plain;charset=utf-8'):
        output = self.work / (name + '.bytes')
        peer = self.start([str(self.peer_binary), '--receive', str(output), mime],
                          self.work.name + '-' + name, stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE)
        self.addCleanup(self.stop, peer)
        self.assertEqual(self.line(peer), b'ready\n')
        peer.stdin.write(b'receive\n')
        peer.stdin.flush()
        line = self.line(peer).decode().strip().split()
        self.assertEqual(line[0], 'receiving')
        self.assertTrue(line[1].isdigit())
        return peer, output, line[1]

    def drain(self, peer, output, expected):
        peer.stdin.write(b'drain\n')
        peer.stdin.flush()
        self.assertEqual(self.line(peer), ('received ' + str(len(expected)) + '\n').encode())
        self.assertEqual(output.read_bytes(), expected)

    def outgoing(self, data):
        self.document.write_bytes(data)
        self.start_case(None)
        self.command('cmd copy')
        self.command('wait 50')

    def test_outgoing_large_counted_unicode(self):
        data = b'x' * 2097152 + 'é水😀\0tail'.encode()
        self.outgoing(data)
        peer, output, inode = self.receiver()
        self.wait_pipe(inode)
        self.drain(peer, output, data)
        self.assertFalse(self.pipe_present(inode))

    def test_outgoing_plain_and_utf8_string(self):
        data = b'x' * 8192 + 'é水😀\0tail'.encode()
        self.outgoing(data)
        for index, mime in enumerate(('text/plain', 'UTF8_STRING')):
            peer, output, _ = self.receiver('reader' + str(index), mime)
            self.drain(peer, output, data)

    def test_outgoing_empty(self):
        self.outgoing(b'')
        peer, output, _ = self.receiver()
        self.drain(peer, output, b'')

    def test_outgoing_two_paused_readers_keep_snapshot(self):
        data = b'x' * 2097152 + 'é水😀\0tail'.encode()
        self.outgoing(data)
        first = self.receiver('first')
        second = self.receiver('second')
        for peer, output, inode in (first, second):
            self.wait_pipe(inode)
        self.assertIn(b'tabs=1', self.command('print-state'))
        self.command('type replacement')
        self.command('cmd select_all')
        self.command('cmd copy')
        self.command('wait 50')
        self.assertEqual(self.command('print-doc'), b'replacement\n<eod>\n')
        for peer, output, inode in (first, second):
            self.drain(peer, output, data)
            self.assertFalse(self.pipe_present(inode))
        peer, output, _ = self.receiver('current')
        self.drain(peer, output, b'replacement')

    def test_outgoing_stalled_reader_times_out(self):
        data = b'x' * 2097152
        self.outgoing(data)
        peer, output, inode = self.receiver()
        self.wait_pipe(inode)
        deadline = time.monotonic() + 35
        while self.pipe_present(inode):
            self.assertLess(time.monotonic(), deadline, 'stalled write end did not expire')
            self.assertIn(b'tabs=1', self.command('print-state'))
            time.sleep(.1)
        peer.stdin.write(b'probe\n')
        peer.stdin.flush()
        self.assertEqual(self.line(peer), b'hup 1\n')
        peer.stdin.write(b'drain\n')
        peer.stdin.flush()
        line = self.line(peer).decode().strip().split()
        self.assertEqual(line[0], 'received')
        count = int(line[1])
        self.assertGreater(count, 0)
        self.assertLess(count, len(data))
        self.assertEqual(output.read_bytes(), data[:count])
        peer, output, _ = self.receiver('after-timeout')
        self.drain(peer, output, data)

    def test_incoming_large_counted_unicode(self):
        data = b'x' * 2097152 + 'é水😀\0tail'.encode()
        self.start_case(data)
        self.finish(self.request('text/plain;charset=utf-8'), data)

    def test_incoming_plain_only(self):
        data = 'plain é水\0tail'.encode()
        self.start_case(data, ('text/plain',))
        self.finish(self.request('text/plain'), data)

    def test_incoming_utf8_string_only(self):
        data = 'string 😀\0tail'.encode()
        self.start_case(data, ('UTF8_STRING',))
        self.finish(self.request('UTF8_STRING'), data)

    def test_incoming_prefers_explicit_utf8(self):
        data = 'chosen é'.encode()
        self.start_case(data, ('text/plain', 'UTF8_STRING', 'text/plain;charset=utf-8'))
        self.finish(self.request('text/plain;charset=utf-8'), data)

    def test_incoming_empty(self):
        self.start_case(b'')
        self.finish(self.request('text/plain;charset=utf-8'), b'original')

    def test_incoming_invalid_utf8(self):
        self.start_case(b'valid-prefix\xff')
        self.finish(self.request('text/plain;charset=utf-8'), b'original')

    def test_incoming_paused_writer(self):
        data = 'é水😀\0tail'.encode()
        self.start_case(data)
        inode = self.request('text/plain;charset=utf-8')
        self.owner.stdin.write(b'part 1\n')
        self.owner.stdin.flush()
        self.assertEqual(self.line(self.owner), b'part 1\n')
        self.assertIn(b'tabs=1', self.command('print-state'))
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')
        self.assertTrue(self.pipe_present(inode))
        self.finish(inode, data)

    def test_incoming_unsupported_mime(self):
        self.start_case(b'image bytes', ('image/png',))
        self.command('cmd paste')
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')
        self.assertFalse(select.select([self.owner.stdout], [], [], .1)[0])

    def test_incoming_missing_selection(self):
        self.start_case(None)
        self.command('cmd paste')
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')

    def test_incoming_stalled_writer_times_out(self):
        self.start_case(b'stalled')
        inode = self.request('text/plain;charset=utf-8')
        deadline = time.monotonic() + 35
        while self.pipe_present(inode):
            self.assertLess(time.monotonic(), deadline, 'stalled read end did not expire')
            self.assertIn(b'tabs=1', self.command('print-state'))
            time.sleep(.1)
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
