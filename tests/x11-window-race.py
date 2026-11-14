#!/usr/bin/env python3
"""A maximize between state and geometry replies must not replace normal window bounds."""
import ctypes as c
import ctypes.util
import os
from pathlib import Path
import select
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()


class Key(c.Structure):
    _fields_ = [('type', c.c_int), ('serial', c.c_ulong), ('send_event', c.c_int),
                ('display', c.c_void_p), ('window', c.c_ulong), ('root', c.c_ulong),
                ('subwindow', c.c_ulong), ('time', c.c_ulong), ('x', c.c_int), ('y', c.c_int),
                ('x_root', c.c_int), ('y_root', c.c_int), ('state', c.c_uint),
                ('keycode', c.c_uint), ('same_screen', c.c_int)]


class Mapping(c.Structure):
    _fields_ = [('type', c.c_int), ('serial', c.c_ulong), ('send_event', c.c_int),
                ('display', c.c_void_p), ('window', c.c_ulong), ('request', c.c_int),
                ('first_keycode', c.c_int), ('count', c.c_int)]


class Client(c.Structure):
    _fields_ = [('type', c.c_int), ('serial', c.c_ulong), ('send_event', c.c_int),
                ('display', c.c_void_p), ('window', c.c_ulong), ('message_type', c.c_ulong),
                ('format', c.c_int), ('data', c.c_long * 5)]


class Event(c.Union):
    _fields_ = [('key', Key), ('mapping', Mapping), ('client', Client),
                ('pad', c.c_long * 24)]


def exact(stream, count):
    data = bytearray()
    while len(data) < count:
        chunk = stream.recv(count - len(data))
        if not chunk:
            raise EOFError()
        data.extend(chunk)
    return bytes(data)


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def until(fn, message):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        value = fn()
        if value:
            return value
        time.sleep(.05)
    raise AssertionError(message)


@unittest.skipUnless(sys.platform == 'linux' and shutil.which('Xvfb') and shutil.which('xdotool'),
                     'requires Linux, Xvfb and xdotool')
class WindowRace(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix='rhun-window-race-display-')
        cls.addClassCleanup(temporary.cleanup)
        log = (Path(temporary.name) / 'display.log').open('wb')
        cls.addClassCleanup(log.close)
        read_fd, write_fd = os.pipe()
        server = subprocess.Popen(['Xvfb', '-displayfd', str(write_fd), '-screen', '0',
                                   '1600x1000x24', '-ac', '-noreset', '-nolisten', 'tcp'],
                                  pass_fds=(write_fd,), stdout=log, stderr=log)
        cls.addClassCleanup(stop, server)
        os.close(write_fd)
        try:
            assert select.select([read_fd], [], [], 15)[0], 'private X server did not start'
            number = os.read(read_fd, 64).decode().strip()
        finally:
            os.close(read_fd)
        assert number.isdigit(), number
        direct = dict(os.environ, DISPLAY=':' + number)
        x = c.CDLL(ctypes.util.find_library('X11'))
        for name, arguments, result in [
            ('XInitThreads', [], c.c_int), ('XOpenDisplay', [c.c_char_p], c.c_void_p),
            ('XCloseDisplay', [c.c_void_p], c.c_int),
            ('XInternAtom', [c.c_void_p, c.c_char_p, c.c_int], c.c_ulong),
            ('XChangeProperty', [c.c_void_p, c.c_ulong, c.c_ulong, c.c_ulong, c.c_int,
                                 c.c_int, c.c_void_p, c.c_int], c.c_int),
            ('XResizeWindow', [c.c_void_p, c.c_ulong, c.c_uint, c.c_uint], c.c_int),
            ('XSync', [c.c_void_p, c.c_int], c.c_int),
            ('XDefaultRootWindow', [c.c_void_p], c.c_ulong),
            ('XKeysymToKeycode', [c.c_void_p, c.c_ulong], c.c_ubyte),
            ('XSendEvent', [c.c_void_p, c.c_ulong, c.c_int, c.c_long, c.POINTER(Event)], c.c_int),
        ]:
            getattr(x, name).argtypes, getattr(x, name).restype = arguments, result
        assert x.XInitThreads()
        display = until(lambda: x.XOpenDisplay(direct['DISPLAY'].encode()), 'X display did not open')
        cls.addClassCleanup(x.XCloseDisplay, display)
        cls.number, cls.x, cls.display = number, x, display

    def test_maximize_during_geometry_query(self):
        self.run_case(closing=False)

    def test_quit_capture_does_not_dispatch_new_edits(self):
        self.run_case(closing=True)

    def test_script_quit_does_not_dispatch_new_edits(self):
        self.run_case(closing=True, script='quit')

    def test_script_eof_does_not_dispatch_new_edits(self):
        self.run_case(closing=True, script='eof')

    def test_dirty_quit_only_takes_the_final_snapshot(self):
        self.run_case(closing=True, dirty_quit=True)

    def test_native_quit_does_not_replay_keys_waiting_for_keymap(self):
        self.run_case(closing=False, queued_keys=True)

    def test_native_quit_during_keymap_reload_drops_waiting_keys(self):
        self.run_case(closing=False, queued_keys=True, quit_in_keymap=True)

    def run_case(self, closing, script=None, dirty_quit=False, queued_keys=False,
                 quit_in_keymap=False):
        temporary = tempfile.TemporaryDirectory(prefix='rhun-window-race-')
        self.addCleanup(temporary.cleanup)
        work = Path(temporary.name)
        log = (work / 'desktop.log').open('wb')
        self.addCleanup(log.close)
        number, x, display = self.number, self.x, self.display
        direct = dict(os.environ, DISPLAY=':' + number)
        state = x.XInternAtom(display, b'_NET_WM_STATE', 0)
        maximized = (c.c_ulong * 2)(x.XInternAtom(display, b'_NET_WM_STATE_MAXIMIZED_HORZ', 0),
                                   x.XInternAtom(display, b'_NET_WM_STATE_MAXIMIZED_VERT', 0))
        proxy_path = Path('/tmp/.X11-unix') / ('X' + str(100000 + os.getpid()))
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(str(proxy_path))
        listener.listen(1)
        self.addCleanup(proxy_path.unlink, missing_ok=True)
        self.addCleanup(listener.close)
        armed, injected, normal_sampled = threading.Event(), threading.Event(), threading.Event()
        main_window, proxy_errors = [], []
        queries = []
        keymap_quit = threading.Event()

        def native_quit():
            event = Event()
            event.client.type, event.client.display = 33, display
            event.client.window = main_window[0]
            event.client.message_type = x.XInternAtom(display, b'WM_PROTOCOLS', 0)
            event.client.format = 32
            event.client.data[0] = x.XInternAtom(display, b'WM_DELETE_WINDOW', 0)
            assert x.XSendEvent(display, main_window[0], 0, 0, c.byref(event))

        def proxy():
            client, _ = listener.accept()
            upstream = socket.socket(socket.AF_UNIX)
            upstream.connect('/tmp/.X11-unix/X' + number)
            def responses():
                try:
                    while data := upstream.recv(65536):
                        client.sendall(data)
                except OSError:
                    pass
            threading.Thread(target=responses, daemon=True).start()
            try:
                head = exact(client, 12)
                name_length, data_length = struct.unpack_from('<HH', head, 6)
                upstream.sendall(head + exact(client, ((name_length + 3) & ~3) + ((data_length + 3) & ~3)))
                state_seen = False
                while True:
                    head = exact(client, 4)
                    length = struct.unpack_from('<H', head, 2)[0] * 4
                    if not length:
                        head += exact(client, 4)
                        length = struct.unpack_from('<I', head, 4)[0] * 4
                    request = head + exact(client, length - len(head))
                    if request[0] == 40 and main_window and not armed.is_set():
                        normal_sampled.set()
                    if armed.is_set() and request[0] == 20 and struct.unpack_from('<I', request, 8)[0] == state:
                        queries.append(request)
                        state_seen = True
                        if (closing or queued_keys) and not injected.is_set():
                            if queued_keys:
                                event = Event()
                                event.mapping.type, event.mapping.display = 34, display
                                event.mapping.window = main_window[0]
                                event.mapping.request = 1 # MappingKeyboard
                                event.mapping.first_keycode, event.mapping.count = 8, 248
                                assert x.XSendEvent(display, main_window[0], 0, 0, c.byref(event))
                            for character, modifiers in [('x', 0), ('s', 4)]:
                                event = Event()
                                event.key.type, event.key.display = 2, display
                                event.key.window = main_window[0]
                                event.key.root = x.XDefaultRootWindow(display)
                                event.key.keycode = x.XKeysymToKeycode(display, ord(character))
                                event.key.state, event.key.same_screen = modifiers, 1
                                x.XSendEvent(display, main_window[0], 0, 1, c.byref(event))
                            if queued_keys and not quit_in_keymap:
                                # Quit is accepted before either key can be translated and replayed.
                                native_quit()
                            x.XSync(display, 0)
                            injected.set()
                    if (quit_in_keymap and injected.is_set() and request[0] == 101
                            and not keymap_quit.is_set()):
                        # GetKeyboardMapping has begun, but its reply must consume Quit first.
                        native_quit()
                        x.XSync(display, 0)
                        keymap_quit.set()
                    if not closing and state_seen and not injected.is_set() and request[0] == 14:
                        window = main_window[0]
                        assert struct.unpack_from('<I', request, 4)[0] == window
                        # Model the WM's property and geometry changes after the normal-state reply.
                        x.XChangeProperty(display, window, state, 4, 32, 0, maximized, 2)
                        x.XResizeWindow(display, window, 1500, 950)
                        x.XSync(display, 0)
                        injected.set()
                    upstream.sendall(request)
            except (OSError, EOFError):
                pass
            except Exception as error:
                proxy_errors.append(error)
            finally:
                upstream.close()
                client.close()

        threading.Thread(target=proxy, daemon=True).start()
        config = work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[updates]\ncheck = false\n[git]\nenabled = false\n'
                          '[files]\nrestore_session = false\nrestore_project = false\n')
        control = work / 'control'
        document = work / 'document.txt'
        document.write_text('saved\n')
        env = dict(os.environ, DISPLAY=':' + proxy_path.name[1:], RHUN_BACKEND='x11', HOME=str(work),
                   XDG_CONFIG_HOME=str(work / 'config'), XDG_STATE_HOME=str(work / 'state'))
        env.pop('WAYLAND_DISPLAY', None)
        arguments = [str(EXE), '--wait', str(work), str(document), '--control', str(control)]
        if script:
            actions = work / 'actions.rsc'
            actions.write_text('wait 1500\n' + ('quit\n' if script == 'quit' else ''))
            arguments += ['--script', str(actions)]
        editor = subprocess.Popen(arguments,
                                  env=env, stdout=log, stderr=log)
        self.addCleanup(stop, editor)
        until(control.exists, 'editor control socket did not open')
        if script:
            def find():
                result = subprocess.run(['xdotool', 'search', '--class', '^rhun$'], env=direct,
                                        capture_output=True, text=True)
                return result.stdout.splitlines()
            window = int(until(find, 'script window did not open')[0])
            main_window.append(window)
            armed.set()
            self.assertTrue(injected.wait(10), 'script exit snapshot was not intercepted')
            self.assertEqual(editor.wait(timeout=15), 0)
            self.assertFalse(proxy_errors, proxy_errors)
            self.assertEqual(document.read_text(), 'saved\n', 'new edits ran after quitting')
            return
        client = socket.socket(socket.AF_UNIX)
        self.addCleanup(client.close)
        client.settimeout(15)
        client.connect(str(control))
        reader = client.makefile('rb')
        self.addCleanup(reader.close)
        def command(text):
            client.sendall((text + '\n').encode())
            while (line := reader.readline()) != b'ok\n':
                self.assertNotIn(line, (b'', b'error\n'))
        command('wait 300')
        window = int(subprocess.check_output(['xdotool', 'search', '--class', '^rhun$'], env=direct).strip())
        main_window.append(window)
        x.XResizeWindow(display, window, 900, 640)
        x.XSync(display, 0)
        command('wait 300')
        self.assertTrue(normal_sampled.wait(10), 'initial normal bounds were not sampled')
        command('wait 100')
        armed.set()
        if dirty_quit:
            # Configure arrives inside the control wait, whose following quit is in the same batch.
            # P_tick must not query X before main cancels pending clipboard operations.
            client.sendall(b'wait 300\nquit\n')
            x.XResizeWindow(display, window, 910, 650)
            x.XSync(display, 0)
            self.assertTrue(injected.wait(10), 'final snapshot was not intercepted')
            self.assertEqual(editor.wait(timeout=15), 0)
            self.assertFalse(proxy_errors, proxy_errors)
            self.assertEqual(len(queries), 1, 'a placement query ran before shutdown cleanup')
            self.assertEqual(document.read_text(), 'saved\n')
            return
        if not closing:
            x.XResizeWindow(display, window, 910, 650)
            x.XSync(display, 0)
            self.assertTrue(injected.wait(10), 'geometry request was not intercepted')
            if queued_keys:
                self.assertEqual(editor.wait(timeout=15), 0)
                if quit_in_keymap:
                    self.assertTrue(keymap_quit.is_set(), 'GetKeyboardMapping was not intercepted')
                self.assertFalse(proxy_errors, proxy_errors)
                self.assertEqual(document.read_text(), 'saved\n',
                                 'queued keys edited and saved after Quit')
                return
            command('wait 300')
        client.sendall(b'quit\n')
        self.assertTrue(injected.wait(10), 'final snapshot was not intercepted')
        self.assertEqual(editor.wait(timeout=15), 0)
        self.assertFalse(proxy_errors, proxy_errors)
        if closing:
            self.assertEqual(document.read_text(), 'saved\n', 'new edits ran after quitting')
        else:
            saved = struct.unpack('<IiiIII', (work / 'state/rhun/window-x11').read_bytes())
            self.assertEqual(saved[3:5], (910, 650), 'last normal resize was lost or replaced by maximized bounds')
            self.assertEqual(saved[5], 3)


if __name__ == '__main__':
    unittest.main()
