#!/usr/bin/env python3
"""Exercise the native X11 clipboard on a private X server."""
import ctypes as c
import ctypes.util
import os
from pathlib import Path
import select
import shutil
import socket
import subprocess
import struct
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()


class Selection(c.Structure):
    _fields_ = [('type', c.c_int), ('serial', c.c_ulong), ('send_event', c.c_int),
                ('display', c.c_void_p), ('requestor', c.c_ulong), ('selection', c.c_ulong),
                ('target', c.c_ulong), ('property', c.c_ulong), ('time', c.c_ulong)]


class Request(c.Structure):
    _fields_ = [('type', c.c_int), ('serial', c.c_ulong), ('send_event', c.c_int),
                ('display', c.c_void_p), ('owner', c.c_ulong), ('requestor', c.c_ulong),
                ('selection', c.c_ulong), ('target', c.c_ulong), ('property', c.c_ulong),
                ('time', c.c_ulong)]


class Property(c.Structure):
    _fields_ = [('type', c.c_int), ('serial', c.c_ulong), ('send_event', c.c_int),
                ('display', c.c_void_p), ('window', c.c_ulong), ('atom', c.c_ulong),
                ('time', c.c_ulong), ('state', c.c_int)]


class Destroy(c.Structure):
    _fields_ = [('type', c.c_int), ('serial', c.c_ulong), ('send_event', c.c_int),
                ('display', c.c_void_p), ('event', c.c_ulong), ('window', c.c_ulong)]


class Event(c.Union):
    _fields_ = [('type', c.c_int), ('selection', Selection), ('request', Request),
                ('property', Property), ('destroy', Destroy), ('pad', c.c_long * 24)]


@unittest.skipUnless(sys.platform == 'linux' and shutil.which('Xvfb'), 'Linux Xvfb required')
class Clipboard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server_log = tempfile.TemporaryFile()
        cls.addClassCleanup(cls.server_log.close)
        read_fd, write_fd = os.pipe()
        try:
            cls.server = subprocess.Popen(['Xvfb', '-displayfd', str(write_fd), '-screen', '0',
                '1024x768x24', '-nolisten', 'tcp', '-ac', '-noreset'], pass_fds=(write_fd,),
                stdout=cls.server_log, stderr=cls.server_log)
            cls.addClassCleanup(cls.stop_server)
            os.close(write_fd)
            write_fd = None
            assert select.select([read_fd], [], [], 10)[0], 'private X server did not start'
            number = os.read(read_fd, 64).decode().strip()
            assert number.isdigit(), number
            cls.display_name = ':' + number
        finally:
            os.close(read_fd)
            if write_fd is not None:
                os.close(write_fd)
        cls.x = c.CDLL(ctypes.util.find_library('X11'))
        signatures = {
            'XOpenDisplay': ([c.c_char_p], c.c_void_p),
            'XCloseDisplay': ([c.c_void_p], c.c_int),
            'XDefaultRootWindow': ([c.c_void_p], c.c_ulong),
            'XCreateSimpleWindow': ([c.c_void_p, c.c_ulong, c.c_int, c.c_int, c.c_uint,
                c.c_uint, c.c_uint, c.c_ulong, c.c_ulong], c.c_ulong),
            'XSelectInput': ([c.c_void_p, c.c_ulong, c.c_long], c.c_int),
            'XDestroyWindow': ([c.c_void_p, c.c_ulong], c.c_int),
            'XInternAtom': ([c.c_void_p, c.c_char_p, c.c_int], c.c_ulong),
            'XConvertSelection': ([c.c_void_p, c.c_ulong, c.c_ulong, c.c_ulong,
                c.c_ulong, c.c_ulong], c.c_int),
            'XSetSelectionOwner': ([c.c_void_p, c.c_ulong, c.c_ulong, c.c_ulong], c.c_int),
            'XGetSelectionOwner': ([c.c_void_p, c.c_ulong], c.c_ulong),
            'XGetWindowProperty': ([c.c_void_p, c.c_ulong, c.c_ulong, c.c_long, c.c_long,
                c.c_int, c.c_ulong, c.POINTER(c.c_ulong), c.POINTER(c.c_int),
                c.POINTER(c.c_ulong), c.POINTER(c.c_ulong), c.POINTER(c.c_void_p)], c.c_int),
            'XChangeProperty': ([c.c_void_p, c.c_ulong, c.c_ulong, c.c_ulong, c.c_int,
                c.c_int, c.c_void_p, c.c_int], c.c_int),
            'XSendEvent': ([c.c_void_p, c.c_ulong, c.c_int, c.c_long, c.POINTER(Event)], c.c_int),
            'XPending': ([c.c_void_p], c.c_int),
            'XNextEvent': ([c.c_void_p, c.POINTER(Event)], c.c_int),
            'XFlush': ([c.c_void_p], c.c_int),
            'XSync': ([c.c_void_p, c.c_int], c.c_int),
            'XFree': ([c.c_void_p], c.c_int),
        }
        for name, (arguments, result) in signatures.items():
            function = getattr(cls.x, name)
            function.argtypes, function.restype = arguments, result

    @classmethod
    def stop_server(cls):
        if cls.server.poll() is None:
            cls.server.terminate()
        try:
            cls.server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cls.server.kill()
            cls.server.wait(timeout=5)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-x11-clipboard-')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.env = dict(os.environ, DISPLAY=self.display_name, HOME=str(self.work),
            XDG_CONFIG_HOME=str(self.work / 'config'), XDG_STATE_HOME=str(self.work / 'state'),
            XDG_RUNTIME_DIR=str(self.work), SHELL='/nonexistent')
        self.env.pop('WAYLAND_DISPLAY', None)
        self.env.pop('WAYLAND_SOCKET', None)
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
            'final_newline = false\n'
            '[ui]\nagents_panel = false\nsidebar = false\n[updates]\ncheck = false\n'
            '[git]\nenabled = false\n')
        self.display = self.x.XOpenDisplay(self.display_name.encode())
        self.assertTrue(self.display)
        self.addCleanup(self.x.XCloseDisplay, self.display)
        root = self.x.XDefaultRootWindow(self.display)
        self.window = self.x.XCreateSimpleWindow(self.display, root, 0, 0, 1, 1, 0, 0, 0)
        self.assertTrue(self.window)
        self.addCleanup(self.x.XDestroyWindow, self.display, self.window)
        self.clipboard = self.atom(b'CLIPBOARD')
        self.utf8 = self.atom(b'UTF8_STRING')
        self.native = self.atom(b'application/x-rhun-clipboard-v1')
        self.property = self.atom(b'RHUN_CLIPBOARD_FIXTURE')
        self.events = []
        self.client = None
        self.reader = None
        self.process = None
        self.addCleanup(self.stop_editor)

    def atom(self, name):
        return self.x.XInternAtom(self.display, name, 0)

    def start_editor(self, data):
        self.document = self.work / 'document.txt'
        self.document.write_bytes(data)
        control = self.work / 'control'
        self.log = open(self.work / 'editor.log', 'wb')
        self.addCleanup(self.log.close)
        self.process = subprocess.Popen([str(EXE), str(self.document), '--control', str(control)],
            env=self.env, stdout=self.log, stderr=self.log)
        deadline = time.monotonic() + 10
        while not control.exists():
            self.assertIsNone(self.process.poll(), (self.work / 'editor.log').read_text())
            self.assertLess(time.monotonic(), deadline, 'control socket did not appear')
            time.sleep(.01)
        self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.client.settimeout(10)
        self.client.connect(str(control))
        self.reader = self.client.makefile('rb')
        self.command('wait 50')
        self.assertIn(b'tabs=1', self.command('print-state'))
        # A new client may reuse a previous client's XIDs. No transfer is live yet.
        self.x.XSync(self.display, 1)
        self.events.clear()

    def stop_editor(self):
        if self.process is not None and self.process.poll() is None:
            try:
                if self.client:
                    self.command('quit')
                self.process.wait(timeout=5)
            except (OSError, AssertionError, subprocess.TimeoutExpired):
                self.process.kill()
                self.process.wait(timeout=5)
        if self.reader:
            self.reader.close()
        if self.client:
            self.client.close()
        self.reader = self.client = self.process = None

    def command(self, value):
        self.client.sendall(value.encode() + b'\n')
        result = []
        while True:
            line = self.reader.readline()
            self.assertNotIn(line, (b'', b'error\n'), value)
            if line == b'ok\n':
                return b''.join(result)
            result.append(line)

    def event(self, kind, predicate=lambda event: True):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            for index, event in enumerate(self.events):
                if event.type == kind and predicate(event):
                    return self.events.pop(index)
            if self.x.XPending(self.display):
                event = Event()
                self.x.XNextEvent(self.display, c.byref(event))
                if event.type == kind and predicate(event):
                    return event
                self.events.append(event)
            else:
                time.sleep(.005)
        self.fail('clipboard event did not arrive: ' + str(kind))

    def read_property(self, window, atom):
        offset = 0
        parts = []
        property_type = property_format = None
        while True:
            actual_type, count, after = c.c_ulong(), c.c_ulong(), c.c_ulong()
            format_ = c.c_int()
            pointer = c.c_void_p()
            status = self.x.XGetWindowProperty(self.display, window, atom, offset,
                4096, 1, 0, c.byref(actual_type), c.byref(format_), c.byref(count),
                c.byref(after), c.byref(pointer))
            try:
                self.assertEqual(status, 0)
                if property_type is None:
                    property_type, property_format = actual_type.value, format_.value
                self.assertEqual((actual_type.value, format_.value),
                                 (property_type, property_format))
                if format_.value == 32:
                    value = tuple(c.cast(pointer, c.POINTER(c.c_ulong))[:count.value])
                    byte_count = count.value * 4
                else:
                    self.assertEqual(format_.value, 8)
                    value = c.string_at(pointer, count.value)
                    byte_count = count.value
                parts.append(value)
                if after.value == 0:
                    break
                self.assertGreater(byte_count, 0)
                self.assertEqual(byte_count % 4, 0)
                offset += byte_count // 4
            finally:
                if pointer:
                    self.x.XFree(pointer)
        result = () if property_format == 32 else b''
        for part in parts:
            result += part
        return property_type, property_format, result

    def begin_request(self, target, property_=None, window=None):
        property_ = self.property if property_ is None else property_
        window = self.window if window is None else window
        self.x.XSelectInput(self.display, window, 0x420000)
        self.x.XConvertSelection(self.display, self.clipboard, target, property_,
                                 window, 0)
        self.x.XFlush(self.display)
        event = self.event(31, lambda ev: ev.selection.requestor == window and ev.selection.property in (0, property_)).selection
        self.assertEqual((event.requestor, event.selection, event.target),
                         (window, self.clipboard, target))
        if event.property == 0:
            return None
        self.assertEqual(event.property, property_)
        self.wait_new_value(window, property_)
        result = self.read_property(window, property_)
        return result

    def finish_incremental(self, result, property_, window=None, limit=67108864):
        window = self.window if window is None else window
        self.assertEqual((result[1], len(result[2])), (32, 1))
        lower = result[2][0]
        self.assertLessEqual(lower, limit)
        self.x.XFlush(self.display)
        parts = []
        final_type = final_format = None
        total = 0
        while True:
            self.wait_new_value(window, property_)
            type_, format_, value = self.read_property(window, property_)
            if final_type is None:
                final_type, final_format = type_, format_
            self.assertEqual((type_, format_), (final_type, final_format))
            self.x.XFlush(self.display)
            if not value:
                break
            total += len(value) * (4 if format_ == 32 else 1)
            self.assertLessEqual(total, limit)
            parts.append(value)
        self.assertGreaterEqual(total, lower)
        combined = () if final_format == 32 else b''
        for part in parts:
            combined += part
        return final_type, final_format, combined

    def request_data(self, target, property_=None, window=None):
        property_ = self.property if property_ is None else property_
        result = self.begin_request(target, property_, window)
        if result is None or result[0] != self.atom(b'INCR'):
            return result
        return self.finish_incremental(result, property_, window,
                                       67117088 if target == self.native else 67108864)

    def wait_new_value(self, window, atom):
        self.event(28, lambda ev: (ev.property.window, ev.property.atom, ev.property.state)
                   == (window, atom, 0))

    def request_text(self):
        result = self.request_data(self.utf8)
        self.assertIsNotNone(result)
        type_, format_, value = result
        self.assertEqual((type_, format_), (self.utf8, 8))
        return value

    def plain_request(self, request=None):
        request = self.event(30).request if request is None else request
        if request.target == self.native:
            # This owner supports ordinary text. Refuse native before serving the new window.
            self.assertEqual((request.owner, request.selection), (self.window, self.clipboard))
            self.x.XSelectInput(self.display, request.requestor, 0x420000)
            response = Event()
            response.selection = Selection(31, 0, 1, self.display, request.requestor,
                request.selection, request.target, 0, request.time)
            self.assertTrue(self.x.XSendEvent(self.display, request.requestor, 0, 0, c.byref(response)))
            self.x.XFlush(self.display)
            self.assertEqual(self.event(17, lambda ev: ev.destroy.window == request.requestor).destroy.window,
                             request.requestor)
            old_window = request.requestor
            request = self.event(30).request
            self.assertNotEqual(request.requestor, old_window)
        return request

    def serve_text(self, data, incremental=False, marker=None, request=None, native=False):
        request = self.event(30).request if request is None else request
        if not native:
            request = self.plain_request(request)
        target = self.native if native else self.utf8
        self.assertEqual((request.owner, request.selection, request.target),
                         (self.window, self.clipboard, target))
        self.x.XSelectInput(self.display, request.requestor, 0x420000)
        response = Event()
        response.selection = Selection(31, 0, 1, self.display, request.requestor,
            request.selection, request.target, 0, request.time)
        property_ = request.property or request.target
        if incremental or marker is not None:
            value = c.c_ulong(len(data) if marker is None else marker)
            self.x.XChangeProperty(self.display, request.requestor, property_, self.atom(b'INCR'),
                32, 0, c.byref(value), 1)
            response.selection.property = property_
        elif data is not None:
            buffer = c.create_string_buffer(data)
            self.x.XChangeProperty(self.display, request.requestor, property_, target,
                8, 0, c.cast(buffer, c.c_void_p), len(data))
            response.selection.property = property_
        self.assertTrue(self.x.XSendEvent(self.display, request.requestor, 0, 0, c.byref(response)))
        self.x.XFlush(self.display)
        if incremental and (marker is None or marker <= (67117088 if native else 67108864)):
            offset = 0
            # Deliberately split UTF8 sequences and include properties needing multiple pages.
            for size in (1, 2, 16387, 65537, 262147, len(data)):
                self.wait_delete(request.requestor, property_)
                chunk = data[offset:offset + size]
                offset += len(chunk)
                buffer = c.create_string_buffer(chunk)
                self.x.XChangeProperty(self.display, request.requestor, property_, target,
                    8, 0, c.cast(buffer, c.c_void_p), len(chunk))
                self.x.XFlush(self.display)
                if not chunk:
                    break
            else:
                self.wait_delete(request.requestor, property_)
                self.x.XChangeProperty(self.display, request.requestor, property_, target,
                    8, 0, None, 0)
                self.x.XFlush(self.display)
        event = self.event(17, lambda ev: ev.destroy.window == request.requestor).destroy
        self.assertEqual(event.window, request.requestor)

    def wait_delete(self, window, atom):
        self.event(28, lambda ev: (ev.property.window, ev.property.atom, ev.property.state)
                   == (window, atom, 1))

    @staticmethod
    def wire(text, line=False, segments=(), version=1):
        return (struct.pack('<8sIIQQ', b'RHUNCLP\0', version, int(line), len(segments), len(text)) +
                b''.join(struct.pack('<QQ', *pair) for pair in segments) + text)

    def test_outgoing_native_direct_and_incremental(self):
        for data in (b'small', b'x' * 8192 + 'é水😀\0suffix\n'.encode(),
                     b'x' * 1048576 + 'é水😀\0tail'.encode()):
            with self.subTest(size=len(data)):
                try:
                    self.copy_document(data)
                    self.assertEqual(self.request_data(self.native), (self.native, 8, self.wire(data)))
                    self.assertEqual(self.request_text(), data)
                finally:
                    self.stop_editor()
                    (self.work / 'control').unlink(missing_ok=True)

    def test_outgoing_native_line_to_fresh_rhun_process(self):
        self.start_editor(b'L\nabc')
        self.command('cmd copy')
        self.command('wait 50')
        self.assertEqual(self.request_data(self.native), (self.native, 8, self.wire(b'L\n', True)))
        self.assertEqual(self.request_text(), b'L\n')
        reader = Clipboard()
        try:
            reader.setUp()
            reader.start_editor(b'abc')
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

    def test_outgoing_native_paused_snapshot_after_ownership_loss(self):
        data = b'x' * 1048576 + 'é水😀\0tail'.encode()
        self.copy_document(data)
        result = self.begin_request(self.native)
        self.assertEqual(result[0], self.atom(b'INCR'))
        self.command('cmd select_all')
        self.command('type replacement')
        self.command('cmd copy')
        self.x.XSetSelectionOwner(self.display, self.clipboard, self.window, 0)
        self.x.XFlush(self.display)
        self.assertEqual(self.finish_incremental(result, self.property, limit=67117088),
                         (self.native, 8, self.wire(data)))

    def native_incoming(self, data, expected, initial=b'original', before=('cmd select_all',),
                        incremental=False, fallback=None, marker=None):
        self.start_editor(initial)
        self.x.XSetSelectionOwner(self.display, self.clipboard, self.window, 0)
        self.assertEqual(self.x.XGetSelectionOwner(self.display, self.clipboard), self.window)
        for action in before:
            self.command(action)
        self.command('cmd paste')
        self.serve_text(data, native=True, incremental=incremental, marker=marker)
        if fallback is not None:
            self.serve_text(fallback)
        self.assertEqual(self.command('print-doc'), expected + b'\n<eod>\n')
        self.command('cmd save')
        self.assertEqual(self.document.read_bytes(), expected)

    def test_incoming_native_preference_and_fallback(self):
        cases = [
            ('raw', self.wire(b'native'), b'native', {}),
            ('line', self.wire(b'L\n', True), b'L\nabc', {'initial': b'abc', 'before': ('key Right',)}),
            ('unicode-nul', self.wire('é\0水😀'.encode()), 'é\0水😀'.encode(), {}),
            ('multi', self.wire(b'a\nb\nc', segments=((0, 3), (4, 1))), b'a\nb\nc', {}),
            ('empty', self.wire(b''), b'original', {}),
            ('missing', None, b'fallback', {'fallback': b'fallback'}),
            ('version', self.wire(b'native', version=2), b'fallback', {'fallback': b'fallback'}),
            ('malformed', b'broken', b'fallback', {'fallback': b'fallback'}),
            ('boundary', self.wire('é'.encode(), segments=((0, 1),)), b'fallback', {'fallback': b'fallback'}),
            ('utf8', self.wire(b'\xff'), b'fallback', {'fallback': b'fallback'}),
            ('oversize-marker', b'', b'fallback', {'marker': 67117089, 'fallback': b'fallback'}),
        ]
        for name, wire, expected, options in cases:
            with self.subTest(name=name):
                try:
                    self.native_incoming(wire, expected, **options)
                finally:
                    self.stop_editor()
                    (self.work / 'control').unlink(missing_ok=True)

    def test_incoming_native_incremental_and_invalid_fallback(self):
        data = 'é水😀\0'.encode() + b'x' * 1048576 + '水end'.encode()
        for valid in (True, False):
            with self.subTest(valid=valid):
                try:
                    wire = self.wire(data, version=1 if valid else 2)
                    self.native_incoming(wire, data if valid else b'fallback', incremental=True,
                                         fallback=None if valid else b'fallback')
                finally:
                    self.stop_editor()
                    (self.work / 'control').unlink(missing_ok=True)

    def test_incoming_native_raw_overrides_matching_line_cache(self):
        self.start_editor(b'L\nabc')
        self.command('cmd copy')
        self.command('wait 50')
        self.x.XSetSelectionOwner(self.display, self.clipboard, self.window, 0)
        self.assertEqual(self.x.XGetSelectionOwner(self.display, self.clipboard), self.window)
        self.command('key Down')
        self.command('key Right')
        self.command('cmd paste')
        self.serve_text(self.wire(b'L\n'), native=True)
        self.assertEqual(self.command('print-doc'), b'L\naL\nbc\n<eod>\n')

    def test_incoming_native_stale_target_and_successor(self):
        request = self.delayed_request()
        self.command('key End')
        self.serve_text(self.wire(b'L\n', True), native=True, request=request)
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')
        self.command('cmd paste')
        self.serve_text(self.wire(b'valid'), native=True)
        self.assertEqual(self.command('print-doc'), b'originalvalid\n<eod>\n')

    def test_incoming_native_fallback_queue(self):
        request = self.delayed_request()
        self.command('cmd paste')
        self.serve_text(self.wire(b'invalid', version=2), native=True, request=request)
        self.serve_text(b'first')
        self.assertEqual(self.command('print-doc'), b'first\n<eod>\n')
        self.serve_text(self.wire(b'second'), native=True)
        self.assertEqual(self.command('print-doc'), b'firstsecond\n<eod>\n')
        self.command('cmd undo')
        self.assertEqual(self.command('print-doc'), b'first\n<eod>\n')
        self.command('cmd undo')
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')

    def test_outgoing_standard_and_big_requests(self):
        tail = 'é水😀\0z\n'.encode()
        for size in (5, 65513, 262117, 2097152):
            with self.subTest(size=size):
                data = b'hello' if size == 5 else b'x' * (size - len(tail)) + tail
                try:
                    self.start_editor(data)
                    self.command('cmd select_all')
                    self.command('cmd copy')
                    self.command('wait 50')
                    self.assertEqual(self.request_text(), data)
                finally:
                    self.stop_editor()
                    # Each subcase uses a new control socket and document process.
                    (self.work / 'control').unlink(missing_ok=True)

    def test_outgoing_legacy_string_and_targets(self):
        cases = [('A\téÿ\n'.encode(), b'A\t\xe9\xff\n'),
                 ('water 水'.encode(), None), (b'x' * 8192 + b'A\0suffix', None), (b'', b'')]
        targets = self.atom(b'TARGETS')
        for data, legacy in cases:
            with self.subTest(data=data):
                try:
                    self.start_editor(data)
                    self.command('cmd select_all')
                    self.command('cmd copy')
                    self.command('wait 50')
                    expected_targets = (targets, self.utf8, self.native) + (() if legacy is None else (31,))
                    self.assertEqual(self.request_data(targets), (4, 32, expected_targets))
                    self.assertEqual(self.request_data(31),
                                     None if legacy is None else (31, 8, legacy))
                    self.assertEqual(self.request_text(), data)
                finally:
                    self.stop_editor()
                    (self.work / 'control').unlink(missing_ok=True)

    def copy_document(self, data):
        self.start_editor(data)
        self.command('cmd select_all')
        self.command('cmd copy')
        self.command('wait 50')

    def test_outgoing_paused_reader_keeps_snapshot(self):
        data = b'x' * 131073 + 'é水😀\0tail'.encode()
        self.copy_document(data)
        property_ = self.atom(b'RHUN_OLD_COPY')
        old = self.begin_request(self.utf8, property_)
        self.assertEqual(old[0], self.atom(b'INCR'))
        self.assertIn(b'tabs=1', self.command('print-state'))
        self.command('cmd select_all')
        self.command('type replacement')
        self.command('cmd select_all')
        self.command('cmd copy')
        self.command('wait 50')
        self.assertEqual(self.request_text(), b'replacement')
        self.assertEqual(self.finish_incremental(old, property_), (self.utf8, 8, data))

    def test_outgoing_concurrent_requestors(self):
        data = b'a' * 262145 + 'é\0end'.encode()
        self.copy_document(data)
        root = self.x.XDefaultRootWindow(self.display)
        second = self.x.XCreateSimpleWindow(self.display, root, 0, 0, 1, 1, 0, 0, 0)
        self.assertTrue(second)
        try:
            first_property = self.atom(b'RHUN_FIRST_READER')
            second_property = self.atom(b'RHUN_SECOND_READER')
            first = self.begin_request(self.utf8, first_property)
            other = self.begin_request(self.utf8, second_property, second)
            self.assertEqual(first[0], self.atom(b'INCR'))
            self.assertEqual(other[0], self.atom(b'INCR'))
            self.assertEqual(self.finish_incremental(other, second_property, second),
                             (self.utf8, 8, data))
            self.assertEqual(self.finish_incremental(first, first_property),
                             (self.utf8, 8, data))
        finally:
            self.x.XDestroyWindow(self.display, second)
            self.x.XFlush(self.display)

    def test_outgoing_destroyed_requestors_release_slots(self):
        data = b'b' * 65537
        self.copy_document(data)
        root = self.x.XDefaultRootWindow(self.display)
        for index in range(10):
            with self.subTest(index=index):
                window = self.x.XCreateSimpleWindow(self.display, root, 0, 0, 1, 1, 0, 0, 0)
                self.assertTrue(window)
                try:
                    result = self.begin_request(self.utf8, self.property, window)
                    self.assertIsNotNone(result)
                    self.assertEqual(result[0], self.atom(b'INCR'))
                finally:
                    self.x.XDestroyWindow(self.display, window)
                    self.x.XFlush(self.display)
                self.event(17, lambda ev: ev.destroy.window == window)
                self.command('wait 25')
                self.assertIn(b'tabs=1', self.command('print-state'))
        self.assertEqual(self.request_text(), data)

    def test_incoming_counted_unicode(self):
        data = 'é水😀\0suffix\n'.encode()
        self.check_incoming(data, data)

    def delayed_request(self):
        self.start_editor(b'original')
        self.x.XSetSelectionOwner(self.display, self.clipboard, self.window, 0)
        self.assertEqual(self.x.XGetSelectionOwner(self.display, self.clipboard), self.window)
        self.command('cmd select_all')
        self.command('cmd paste')
        return self.event(30).request

    def test_incoming_delayed_vim_visual_paste(self):
        self.start_editor(b'abcdef')
        self.x.XSetSelectionOwner(self.display, self.clipboard, self.window, 0)
        self.assertEqual(self.x.XGetSelectionOwner(self.display, self.clipboard), self.window)
        self.command('cmd toggle_vim')
        self.command('key Escape')
        self.command('type gg0vl')
        self.assertIn(b'vim=visual', self.command('print-state'))
        self.command('key ctrl+v')
        request = self.event(30).request
        self.command('wait 100')
        self.assertIn(b'vim=visual', self.command('print-state'))
        self.serve_text(b'X', request=request)
        self.assertEqual(self.command('print-doc'), b'Xcdef\n<eod>\n')

    def test_incoming_delayed_target_switch(self):
        request = self.delayed_request()
        self.command('cmd new_file')
        self.command('type second')
        self.serve_text(b'late', request=request)
        self.assertEqual(self.command('print-doc'), b'second\n<eod>\n')
        self.command('cmd prev_tab')
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')

    def test_incoming_delayed_selection_change(self):
        request = self.delayed_request()
        self.command('key End')
        self.serve_text(b'late', request=request)
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')

    def test_incoming_delayed_edit(self):
        request = self.delayed_request()
        self.command('type changed')
        self.serve_text(b'late', request=request)
        self.assertEqual(self.command('print-doc'), b'changed\n<eod>\n')

    def test_incoming_delayed_close_reopen(self):
        request = self.delayed_request()
        self.command('cmd close_tab')
        self.command('open ' + str(self.document))
        self.serve_text(b'late', request=request)
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')

    def test_incoming_queued_pastes_keep_order(self):
        request = self.delayed_request()
        self.command('cmd paste')
        self.command('cmd paste')
        expected = b''
        for index, data in enumerate((b'first', b'second', b'third')):
            self.serve_text(data, request=request if index == 0 else None)
            expected += data
            self.assertEqual(self.command('print-doc'), expected + b'\n<eod>\n')
        for expected in (b'firstsecond', b'first', b'original'):
            self.command('cmd undo')
            self.assertEqual(self.command('print-doc'), expected + b'\n<eod>\n')
        for expected in (b'first', b'firstsecond', b'firstsecondthird'):
            self.command('cmd redo')
            self.assertEqual(self.command('print-doc'), expected + b'\n<eod>\n')

    def test_incoming_queue_after_invalid_transfer(self):
        request = self.delayed_request()
        self.command('cmd paste')
        self.serve_text(b'\xff', request=request)
        self.assertEqual(self.command('print-doc'), b'original\n<eod>\n')
        self.serve_text(b'valid')
        self.assertEqual(self.command('print-doc'), b'valid\n<eod>\n')

    def test_incoming_empty(self):
        self.check_incoming(b'', b'original')

    def test_incoming_missing(self):
        self.check_incoming(None, b'original')

    def test_incoming_large_properties(self):
        tail = 'é水😀\0suffix\n'.encode()
        for size in (65537, 262145, 2097152):
            with self.subTest(size=size):
                data = b'x' * (size - len(tail)) + tail
                try:
                    self.check_incoming(data, data)
                finally:
                    self.stop_editor()
                    (self.work / 'control').unlink(missing_ok=True)

    def test_incoming_incremental(self):
        data = 'é水😀\0'.encode() + b'x' * 1048576 + '水end'.encode()
        self.check_incoming(data, data, incremental=True)

    def test_incoming_incremental_empty(self):
        self.check_incoming(b'', b'original', incremental=True)

    def test_incoming_oversize_marker(self):
        self.check_incoming(b'', b'original', marker=67108865)

    def test_incoming_invalid_utf8(self):
        self.check_incoming(b'valid-prefix\xff', b'original')

    def test_incoming_incremental_invalid_utf8(self):
        self.check_incoming(b'prefix\xff', b'original', incremental=True)

    def test_incoming_incremental_shorter_than_hint(self):
        self.check_incoming(b'ab', b'original', incremental=True, marker=3)

    def check_incoming(self, data, expected, **transfer):
        self.start_editor(b'original')
        self.x.XSetSelectionOwner(self.display, self.clipboard, self.window, 0)
        self.assertEqual(self.x.XGetSelectionOwner(self.display, self.clipboard), self.window)
        self.command('cmd select_all')
        self.command('cmd paste')
        self.serve_text(data, **transfer)
        self.command('wait 100')
        deadline = time.monotonic() + 10
        while self.command('print-doc') != expected + b'\n<eod>\n':
            self.assertLess(time.monotonic(), deadline, 'clipboard delivery did not finish')
            self.command('wait 25')
        self.command('cmd save')
        self.assertEqual(self.document.read_bytes(), expected)


if __name__ == '__main__':
    unittest.main(verbosity=2)
