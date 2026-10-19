#!/usr/bin/env python3
"""Native copy/paste must survive a short clipboard lock from another process."""
import ctypes
from ctypes import wintypes
import os
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / 'build/windows/rhun.exe'


@unittest.skipUnless(os.name == 'nt', 'native Windows clipboard')
class Clipboard(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-clipboard-')
        self.work = Path(self.tmp.name).resolve()
        self.user = ctypes.WinDLL('user32', use_last_error=True)
        self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        self.user.CreateWindowExW.argtypes = [wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR,
            wintypes.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
            wintypes.HWND, wintypes.HMENU, wintypes.HINSTANCE, ctypes.c_void_p]
        self.user.CreateWindowExW.restype = wintypes.HWND
        self.user.DestroyWindow.argtypes = [wintypes.HWND]
        self.user.OpenClipboard.argtypes = [wintypes.HWND]
        self.user.SetClipboardData.argtypes = [wintypes.UINT, wintypes.HANDLE]
        self.user.SetClipboardData.restype = wintypes.HANDLE
        self.user.GetClipboardData.argtypes = [wintypes.UINT]
        self.user.GetClipboardData.restype = wintypes.HANDLE
        self.user.RegisterClipboardFormatW.argtypes = [wintypes.LPCWSTR]
        self.user.RegisterClipboardFormatW.restype = wintypes.UINT
        self.native_format = self.user.RegisterClipboardFormatW('com.r13.rhun.clipboard.v1')
        self.assertTrue(self.native_format)
        self.kernel.GlobalAlloc.argtypes = [wintypes.UINT, ctypes.c_size_t]
        self.kernel.GlobalAlloc.restype = wintypes.HANDLE
        self.kernel.GlobalLock.argtypes = [wintypes.HANDLE]
        self.kernel.GlobalLock.restype = ctypes.c_void_p
        self.kernel.GlobalUnlock.argtypes = [wintypes.HANDLE]
        self.kernel.GlobalFree.argtypes = [wintypes.HANDLE]
        self.kernel.GlobalFree.restype = wintypes.HANDLE
        self.kernel.GlobalSize.argtypes = [wintypes.HANDLE]
        self.kernel.GlobalSize.restype = ctypes.c_size_t
        self.window = self.user.CreateWindowExW(0, 'STATIC', 'rhun clipboard fixture', 0,
                                              0, 0, 1, 1, None, None, None, None)
        self.assertTrue(self.window)
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\nfinal_newline = false\n'
                          '[ui]\nagents_panel = false\n[updates]\ncheck = false\n'
                          '[git]\nenabled = false\n', encoding='utf-8')
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'))

    def tearDown(self):
        self.user.DestroyWindow(self.window)
        self.tmp.cleanup()

    def open_clipboard(self):
        for _ in range(100):
            if self.user.OpenClipboard(self.window):
                return
            time.sleep(0.01)
        self.fail('fixture could not acquire the clipboard')

    def seed(self, text):
        data = (text + '\0').encode('utf-16-le')
        handle = self.kernel.GlobalAlloc(2, len(data))
        self.assertTrue(handle)
        try:
            pointer = self.kernel.GlobalLock(handle)
            self.assertTrue(pointer)
            ctypes.memmove(pointer, data, len(data))
            self.kernel.GlobalUnlock(handle)
            self.open_clipboard()
            try:
                self.assertTrue(self.user.EmptyClipboard())
                self.assertTrue(self.user.SetClipboardData(13, handle))
                handle = None
            finally:
                self.user.CloseClipboard()
        finally:
            if handle:
                self.kernel.GlobalFree(handle)

    def text(self):
        self.open_clipboard()
        try:
            handle = self.user.GetClipboardData(13)
            self.assertTrue(handle)
            pointer = self.kernel.GlobalLock(handle)
            self.assertTrue(pointer)
            try:
                return ctypes.wstring_at(pointer)
            finally:
                self.kernel.GlobalUnlock(handle)
        finally:
            self.user.CloseClipboard()

    def seed_native(self, native, plain='fallback'):
        formats = [(self.native_format, native)] if native is not None else []
        if plain is not None:
            formats.append((13, (plain + '\0').encode('utf-16-le')))
        handles = []
        try:
            for kind, data in formats:
                handle = self.kernel.GlobalAlloc(2, len(data) + 7)
                self.assertTrue(handle)
                handles.append([kind, handle])
                pointer = self.kernel.GlobalLock(handle)
                self.assertTrue(pointer)
                try:
                    ctypes.memset(pointer, 0xcc, self.kernel.GlobalSize(handle))
                    ctypes.memmove(pointer, data, len(data))
                finally:
                    self.kernel.GlobalUnlock(handle)
            self.open_clipboard()
            try:
                self.assertTrue(self.user.EmptyClipboard())
                for record in handles:
                    self.assertTrue(self.user.SetClipboardData(*record))
                    record[1] = None
            finally:
                self.user.CloseClipboard()
        finally:
            for _, handle in handles:
                if handle:
                    self.kernel.GlobalFree(handle)

    @staticmethod
    def wire(text, line=False, segments=(), version=1):
        return (struct.pack('<8sIIQQ', b'RHUNCLP\0', version, int(line), len(segments), len(text)) +
                b''.join(struct.pack('<QQ', *pair) for pair in segments) + text)

    def native(self):
        self.open_clipboard()
        try:
            handle = self.user.GetClipboardData(self.native_format)
            self.assertTrue(handle)
            size = self.kernel.GlobalSize(handle)
            self.assertGreaterEqual(size, 32)
            pointer = self.kernel.GlobalLock(handle)
            self.assertTrue(pointer)
            try:
                header = ctypes.string_at(pointer, 32)
                magic, version, flags, count, length = struct.unpack('<8sIIQQ', header)
                self.assertEqual((magic, version), (b'RHUNCLP\0', 1))
                self.assertLessEqual(flags, 1)
                self.assertLessEqual(count, 512)
                self.assertLessEqual(length, 64 << 20)
                total = 32 + count * 16 + length
                self.assertLessEqual(total, size)
                return ctypes.string_at(pointer, total)
            finally:
                self.kernel.GlobalUnlock(handle)
        finally:
            self.user.CloseClipboard()

    def editor(self, initial, actions):
        file = self.work / 'native.txt'
        file.write_bytes(initial)
        script = self.work / 'native.rsc'
        script.write_text('\n'.join([*actions, 'cmd save', 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(self.work), str(file), '--script', str(script)],
                                env=self.env, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return file.read_bytes()

    def test_native_writer_survives_process_exit_and_supplies_plain_text(self):
        for line in (False, True):
            with self.subTest(line=line):
                text = 'copied café Ω😀\n'.encode()
                actions = ['cmd copy'] if line else ['cmd select_all', 'cmd copy']
                self.assertEqual(self.editor(text, actions), text)
                self.assertEqual(self.native(), self.wire(text, line))
                self.assertEqual(self.text(), text.decode())
                # A fresh rhun process has no in-process copy cache.
                actions = ['key Right', 'cmd paste'] if line else ['cmd select_all', 'cmd paste']
                expected = text + b'abc' if line else text
                self.assertEqual(self.editor(b'abc', actions), expected)

    def test_foreign_native_writer_exit_preference_fallback_empty_and_nul(self):
        cases = [
            ('line', self.wire(b'L\n', True), 'fallback', b'abc', ['key Right'], b'L\nabc'),
            ('raw', self.wire(b'raw'), 'fallback', b'', [], b'raw'),
            ('native-only', self.wire(b'raw'), None, b'', [], b'raw'),
            ('unicode-nul', self.wire('é\0水😀'.encode()), 'fallback', b'', [], 'é\0水😀'.encode()),
            ('empty', self.wire(b''), 'fallback', b'abc', ['cmd select_all'], b'abc'),
            ('version', self.wire(b'raw', version=2), 'fallback', b'', [], b'fallback'),
            ('malformed', b'broken', 'fallback', b'', [], b'fallback'),
            ('segments', self.wire('é'.encode(), segments=((0, 1),)), 'fallback', b'', [], b'fallback'),
            ('plain', None, 'plain', b'', [], b'plain'),
        ]
        for name, wire, plain, initial, before, expected in cases:
            with self.subTest(name=name):
                native_file = self.work / 'foreign-wire.bin'
                plain_file = self.work / 'foreign-plain.bin'
                native_file.write_bytes(wire or b'')
                plain_file.write_text(plain or '', encoding='utf-8')
                result = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--seed-native',
                    str(native_file) if wire is not None else '-',
                    str(plain_file) if plain is not None else '-'], capture_output=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.editor(initial, [*before, 'cmd paste']), expected)

    def contend(self, text, before, operation, release_after_operation=False):
        file = self.work / 'document.txt'
        file.write_text(text, encoding='utf-8')
        script = self.work / 'clipboard.rsc'
        script.write_text('\n'.join([*before, 'echo clipboard-ready', 'cmd ' + operation,
            'cmd save', 'quit']) + '\n', encoding='utf-8')
        locked, release = threading.Event(), threading.Event()
        errors = []
        def holder():
            try:
                self.open_clipboard()
                locked.set()
                try:
                    release.wait(10)
                finally:
                    self.user.CloseClipboard()
            except Exception as error:
                errors.append(error)
                locked.set()
        thread = threading.Thread(target=holder)
        thread.start()
        process = None
        try:
            # Creating a thread's first Win32 message queue can be slow on a cold desktop.
            self.assertTrue(locked.wait(10))
            self.assertEqual(errors, [])
            process = subprocess.Popen([str(EXE), str(self.work), str(file), '--script', str(script)],
                env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            first = []
            reader = threading.Thread(target=lambda: first.append(process.stdout.readline()), daemon=True)
            reader.start()
            reader.join(timeout=10)
            self.assertEqual(first, [b'clipboard-ready\n'])
            # The operation starts while the lock is held, then the other app releases it.
            if release_after_operation:
                process.wait(timeout=3)
            else:
                time.sleep(0.15)
            release.set()
            _, error = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, error)
        finally:
            release.set()
            thread.join(timeout=3)
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        return file.read_text(encoding='utf-8')

    def test_copy_waits_for_another_clipboard_user(self):
        self.seed('old clipboard value')
        self.contend('copied café\n', ['cmd select_all'], 'copy')
        self.assertEqual(self.text(), 'copied café\n')

    def test_paste_waits_for_another_clipboard_user(self):
        self.seed('pasted Ω😀\n')
        self.assertEqual(self.contend('', [], 'paste'), 'pasted Ω😀\n')

    def test_unavailable_clipboard_returns_and_preserves_contents(self):
        for operation in ('copy', 'cut', 'paste'):
            with self.subTest(operation=operation):
                self.seed('unchanged clipboard')
                original = 'unchanged document\n' if operation != 'paste' else ''
                before = ['cmd select_all'] if operation != 'paste' else []
                self.assertEqual(self.contend(original, before, operation,
                                             release_after_operation=True), original)
                self.assertEqual(self.text(), 'unchanged clipboard')

    def test_embedded_nul_copy_and_cut_are_rejected(self):
        for operation in ('copy', 'cut'):
            with self.subTest(operation=operation):
                self.seed('unchanged clipboard')
                file = self.work / 'embedded-nul.txt'
                # The file detector samples the first8KiB. Exercise an opened text buffer
                # containing a later NUL, rather than a file rejected as binary on open.
                original = b'x' * 8192 + b'prefix\0suffix\n'
                file.write_bytes(original)
                script = self.work / 'embedded-nul.rsc'
                script.write_text('print-doc\ncmd select_all\ncmd '+operation+
                                  '\nprint-doc\ncmd save\nquit\n',
                                  encoding='utf-8')
                result = subprocess.run([str(EXE), str(self.work), str(file), '--script', str(script)],
                    env=self.env, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.count(original), 2)
                self.assertEqual(file.read_bytes(), original)
                self.assertEqual(self.text(), 'unchanged clipboard')


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--seed-native':
        fixture = Clipboard()
        fixture.setUp()
        try:
            fixture.seed_native(None if sys.argv[2] == '-' else Path(sys.argv[2]).read_bytes(),
                                None if sys.argv[3] == '-' else Path(sys.argv[3]).read_text(encoding='utf-8'))
        finally:
            fixture.tearDown()
    else:
        unittest.main(verbosity=2)
