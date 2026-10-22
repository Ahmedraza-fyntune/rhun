#!/usr/bin/env python3
"""Native extension negotiation and decimal field boundaries."""
import json
import unittest

host = __import__('ext-host')

FEATURES = ('views complete signature definition references symbols actions rename format '
            'commands save-actions snippets snippet-variants snippet-transforms workspace_watch').split()

PROGRAM = r'''
import os
import sys
import time
from pathlib import Path

log = Path(os.environ['RHUN_STATE']) / 'boundaries.log'
print(HELLO, flush=True)
sent = False
for raw in sys.stdin:
    line = raw.rstrip('\n')
    with log.open('a') as stream:
        stream.write(line + '\n')
    if line.startswith('0 bye'):
        break
    if line.startswith('0 ready ') and not sent:
        sent = True
        for frame in FRAMES:
            if isinstance(frame, tuple):
                time.sleep(frame[0])
                frame = frame[1]
            sys.stdout.write(frame)
            sys.stdout.flush()
'''


class Boundaries(host.Host):
    def extension(self, hello='hello 1', frames=()):
        root = self.work / 'boundary-exts'
        folder = root / 'test' / 'boundary'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'extension.ini').write_text(
            'name = boundary\nowner = test\ntitle = Boundary\nversion = 1\n'
            'protocol = 1\nruntime = python3\nrun = main.py\non = startup\n'
            '[needs]\ndocuments = read\nproject = read\n')
        (folder / 'main.py').write_text('HELLO = ' + json.dumps(hello) + '\nFRAMES = ' + repr(list(frames)) + '\n' + PROGRAM)
        (self.work / 'state/rhun/extensions/test--boundary/boundaries.log').unlink(missing_ok=True)
        return root

    def boundary_log(self):
        return (self.work / 'state/rhun/extensions/test--boundary/boundaries.log').read_text().splitlines()

    def test_every_feature_after_unknown_tokens_is_negotiated(self):
        hello = 'hello 1 ' + ' '.join(['future_' + str(i) for i in range(80)] + FEATURES + ['views'])
        self.run_editor(['wait 400'], exts=self.extension(hello))
        lines = self.boundary_log()
        self.assertEqual(lines[0], '0 features ' + ' '.join(FEATURES), lines)
        self.assertTrue(lines[1].startswith('0 ready '), lines)

    def test_feature_tokens_require_exact_spelling(self):
        self.run_editor(['wait 400'], exts=self.extension('hello 1 viewsx xviews Views workspace_watchx views'))
        self.assertEqual(self.boundary_log()[0], '0 features views')

    def test_overflow_request_id_cannot_alias_a_valid_request(self):
        self.run_editor(['wait 400'], exts=self.extension(frames=['18446744073709551617 watch-workspace\n']))
        self.assertTrue(any(line.startswith('error 0 syntax ') for line in self.boundary_log()), self.boundary_log())
        self.assertFalse(any(line.startswith('ok 1') for line in self.boundary_log()), self.boundary_log())

    def test_overflow_document_id_is_syntax_not_a_real_document(self):
        self.run_editor(['wait 400'], exts=self.extension(frames=['1 text 18446744073709551617\n']))
        self.assertTrue(any(line.startswith('error 1 syntax ') for line in self.boundary_log()), self.boundary_log())

    def test_u64_boundary_and_invalid_spellings(self):
        frames = ['1 text 18446744073709551615\n', '2 text 18446744073709551616\n',
                  '3 text 0\n', '4 text +1\n', '5 text 000000000000000000000\n']
        self.run_editor(['wait 400'], exts=self.extension(frames=frames))
        lines = self.boundary_log()
        for request in (1, 3, 5):
            self.assertTrue(any(line.startswith('error ' + str(request) + ' nodoc ') for line in lines), lines)
        for request in (2, 4):
            self.assertTrue(any(line.startswith('error ' + str(request) + ' syntax ') for line in lines), lines)

    def test_overflow_body_length_cannot_consume_a_small_wrapped_body(self):
        # 2^64 + 1 must not wrap to 1 and take the next line's first byte as its body: it is a
        # syntax error (v1), only its line is dropped, and the next line is a request of its own
        self.run_editor(['wait 400', 'print-extensions'], exts=self.extension(frames=['1 toast 18446744073709551617\n2 status 0\n']))
        lines = self.boundary_log()
        self.assertTrue(any(line.startswith('error 1 syntax ') for line in lines), lines)
        self.assertFalse(any(line == 'ok 1' for line in lines), lines)
        self.assertTrue(any(line == 'ok 2' for line in lines), lines)

    def test_invalid_reply_identity_never_executes_its_body(self):
        payload = '2 status 0\n'
        for hello in ('hello 1', 'hello 1 views', 'hello 1 complete'):
            for fragmented in (False, True):
                with self.subTest(hello=hello, fragmented=fragmented):
                    header = 'ok 18446744073709551617 ' + str(len(payload)) + '\n'
                    frames = [header + payload + '3 status 0\n']
                    if fragmented:
                        frames = [header, (0.05, payload[:4]), (0.05, payload[4:]), (0.05, '3 status 0\n')]
                    self.run_editor(['wait 400'], exts=self.extension(hello, frames=frames))
                    lines = self.boundary_log()
                    self.assertNotIn('ok 2', lines)
                    self.assertIn('ok 3', lines)

    def test_zero_length_stray_reply_keeps_following_request(self):
        for hello in ('hello 1', 'hello 1 complete'):
            with self.subTest(hello=hello):
                self.run_editor(['wait 400'], exts=self.extension(hello, frames=['ok 0 0\n3 status 0\n']))
                self.assertIn('ok 3', self.boundary_log())

    def test_invalid_reply_length_ends_stream_even_without_providers(self):
        for hello in ('hello 1', 'hello 1 views', 'hello 1 complete'):
            with self.subTest(hello=hello):
                output = self.run_editor(['wait 400', 'print-extensions'], exts=self.extension(hello, frames=[
                    'ok 1 18446744073709551617\n2 status 0\n']))
                self.assertNotIn('ok 2', self.boundary_log())
                self.assertTrue(any('state=stopped reason=invalid body framing' in line for line in output), output)

    def test_invalid_body_request_identity_never_executes_its_body(self):
        payload = '2 status 0\n'
        self.run_editor(['wait 400'], exts=self.extension(frames=[
            '18446744073709551617 toast ' + str(len(payload)) + '\n' + payload]))
        self.assertFalse(any(line == 'ok 2' for line in self.boundary_log()), self.boundary_log())

    def test_wide_view_id_cannot_close_a_different_view(self):
        self.run_editor(['wait 400'], exts=self.extension('hello 1 views', frames=[
            '1 view Boundary view\n2 unview 4294967297\n3 unview 1\n']))
        lines = self.boundary_log()
        self.assertTrue(any(line.startswith('error 2 noview ') for line in lines), lines)
        self.assertNotIn('ok 2', lines)
        self.assertIn('ok 3', lines)


def load_tests(loader, tests, pattern):
    return unittest.TestSuite(Boundaries(name) for name in Boundaries.__dict__ if name.startswith('test_'))


if __name__ == '__main__':
    unittest.main()
