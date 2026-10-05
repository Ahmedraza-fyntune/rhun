#!/usr/bin/env python3
"""Agent session discovery handles large metadata and Unicode project paths."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
META_LIMIT = 1 << 20


def claude_slug(path):
    # Claude's JS regex replaces UTF-16 code units, including both halves of an emoji.
    encoded = path.encode('utf-16-le')
    units = [int.from_bytes(encoded[i:i + 2], 'little') for i in range(0, len(encoded), 2)]
    return ''.join(chr(unit) if (ord('0') <= unit <= ord('9') or
                                 ord('A') <= unit <= ord('Z') or
                                 ord('a') <= unit <= ord('z')) else '-' for unit in units)


class CodexDiscovery(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-agents-')
        self.home = Path(self.tmp.name).resolve()
        self.project = self.home / 'project café with spaces'
        self.project.mkdir()
        self.session = self.home / '.codex/sessions/2026/10/02/rollout-test.jsonl'
        self.session.parent.mkdir(parents=True)
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix(), SHELL='/nonexistent')
        config = self.home / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def metadata(self, size=None, cwd=None):
        # Include UTF-8 and escaped newlines; put cwd after the long instructions.
        record = {'type': 'session_meta', 'payload': {
            'base_instructions': 'café\n日本\n',
            'cwd': cwd if cwd is not None else self.project.as_posix()}}
        data = json.dumps(record, ensure_ascii=False).encode('utf-8')
        if size is not None:
            record['payload']['base_instructions'] += 'x' * (size - len(data))
            data = json.dumps(record, ensure_ascii=False).encode('utf-8')
            self.assertEqual(len(data), size)
        return data

    def message(self, role, text):
        record = {'type': 'response_item', 'payload': {
            'type': 'message', 'role': role,
            'content': [{'type': 'input_text' if role == 'user' else 'output_text', 'text': text}]}}
        return json.dumps(record).encode('utf-8') + b'\n'

    def run_editor(self, data, open_thread=False):
        self.session.write_bytes(data)
        script = self.home / 'commands.rsc'
        script.write_text('print-agents' + (' 1' if open_thread else '') + '\nquit\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.project.as_posix(), '--headless', '1000x700',
                                 '--script', script.as_posix()], env=self.env,
                                capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', errors='replace'))
        return result.stdout.decode('utf-8')

    def test_reported_large_record_and_thread(self):
        data = self.metadata(20197) + b'\n'
        data += self.message('user', 'Read the large session')
        data += self.message('assistant', 'The session is visible')
        self.assertEqual(self.run_editor(data, open_thread=True),
                         'Codex: Read the large session\n'
                         'user Read the large session\nagent The session is visible\n')

    def test_large_session_updates_while_open(self):
        self.session.write_bytes(self.metadata(20197) + b'\n' + self.message('user', 'Live session'))
        script = self.home / 'commands.rsc'
        script.write_text('print-agents 1\nwait 2000\nprint-agents 1\nquit\n', encoding='utf-8')
        process = subprocess.Popen([str(EXE), self.project.as_posix(), '--headless', '1000x700',
                                    '--script', script.as_posix()], env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            # Append only after discovery and the initial thread load have finished.
            self.assertEqual(process.stdout.readline(), b'Codex: Live session\n')
            self.assertEqual(process.stdout.readline(), b'user Live session\n')
            with self.session.open('ab') as session:
                session.write(self.message('assistant', 'A live update'))
            output, errors = process.communicate(timeout=20)
            self.assertEqual(process.returncode, 0, errors)
            self.assertEqual(output, b'Codex: Live session\nuser Live session\nagent A live update\n')
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS read interposition')
    def test_interrupted_short_and_failed_reads(self):
        library = self.home / 'faults.dylib'
        subprocess.run(['cc', '-Wall', '-Wextra', '-Werror', '-dynamiclib',
                        str(ROOT / 'tests/file_faults.c'), '-o', str(library)], check=True)
        self.env.update(DYLD_INSERT_LIBRARIES=str(library), RHUN_TEST_PATH=str(self.session))
        for fault, errno, expected in (('read', '4', 'Codex: Untitled session\n'),
                                        ('short-read', '5', 'Codex: Untitled session\n'),
                                        ('read', '5', '')):
            with self.subTest(fault=fault, errno=errno):
                self.env.update(RHUN_TEST_FAULT=fault, RHUN_TEST_ERRNO=errno)
                self.assertEqual(self.run_editor(self.metadata(20197) + b'\n'), expected)

    def test_read_and_growth_boundaries(self):
        for size in (4095, 4096, 4097, 16383, 16384, 16385, 32768, 65536,
                     262145, META_LIMIT - 1, META_LIMIT):
            with self.subTest(size=size):
                self.assertEqual(self.run_editor(self.metadata(size) + b'\n'), 'Codex: Untitled session\n')

    def test_large_metadata_still_allows_thread_loading(self):
        for size in (262145, META_LIMIT):
            with self.subTest(size=size):
                data = self.metadata(size) + b'\n' + self.message('user', 'After large metadata')
                self.assertEqual(self.run_editor(data, open_thread=True),
                                 'Codex: After large metadata\nuser After large metadata\n')

    def test_claude_large_metadata_does_not_block_discovery_or_loading(self):
        slug = claude_slug(self.project.as_posix())
        session = self.home / '.claude/projects' / slug / 'claude-test.jsonl'
        session.parent.mkdir(parents=True)
        user = json.dumps({'type': 'user', 'message': {
            'role': 'user', 'content': 'After Claude metadata'}}).encode('utf-8') + b'\n'
        for size in (20197, 262145, META_LIMIT, 2 * META_LIMIT):
            with self.subTest(size=size):
                record = {'type': 'user', 'isMeta': True,
                          'message': {'role': 'user', 'content': 'café\n日本\n'}}
                overhead = len(json.dumps(record, ensure_ascii=False).encode('utf-8'))
                record['message']['content'] += 'x' * (size - overhead)
                metadata = json.dumps(record, ensure_ascii=False).encode('utf-8')
                self.assertEqual(len(metadata), size)
                session.write_bytes(metadata + b'\n' + user)
                listed_title = 'After Claude metadata' if size == 20197 else 'Untitled session'
                self.assertEqual(self.run_editor(b''), 'Claude Code: ' + listed_title + '\n')
                self.assertEqual(self.run_editor(b'', open_thread=True),
                                 'Claude Code: After Claude metadata\nuser After Claude metadata\n')

    def test_claude_unicode_project_paths(self):
        for index, (name, suffix) in enumerate((('café', '-caf-'), ('日本', '---'), ('cafe\u0301', '-cafe-'),
                                                ('emoji 🦉', '-emoji---'), ('é日本🦉Z', '------Z'))):
            with self.subTest(name=name):
                self.project = self.home / f'case{index}' / name
                self.project.mkdir(parents=True)
                slug = claude_slug(self.project.as_posix())
                self.assertTrue(slug.endswith(suffix), slug)
                session = self.home / '.claude/projects' / slug / 'claude-test.jsonl'
                session.parent.mkdir(parents=True)
                record = {'type': 'user', 'message': {'role': 'user', 'content': 'Unicode project'}}
                session.write_bytes(json.dumps(record).encode('utf-8') + b'\n')
                self.assertEqual(self.run_editor(b'', open_thread=True),
                                 'Claude Code: Unicode project\nuser Unicode project\n')

    def test_eof_without_newline(self):
        for size in (None, 20197, META_LIMIT):
            with self.subTest(size=size):
                self.assertEqual(self.run_editor(self.metadata(size)), 'Codex: Untitled session\n')

    def test_crlf(self):
        data = self.metadata(20197) + b'\r\n' + self.message('user', 'CRLF session')
        self.assertEqual(self.run_editor(data), 'Codex: CRLF session\n')

    def test_other_project_is_excluded(self):
        self.assertEqual(self.run_editor(self.metadata(20197, (self.home / 'other').as_posix()) + b'\n'), '')

    def test_invalid_or_oversized_records_are_excluded(self):
        for data in (b'', b'\n', self.metadata(20197)[:-1] + b'\n',
                     self.metadata(META_LIMIT + 1), self.metadata(META_LIMIT + 1) + b'\n',
                     self.metadata() + b' ' * META_LIMIT + b'\n'):
            with self.subTest(size=len(data)):
                self.assertEqual(self.run_editor(data), '')

    def test_only_first_line_controls_project_matching(self):
        data = self.metadata(cwd=(self.home / 'other').as_posix()) + b'\n'
        data += self.metadata() + b'\n'
        self.assertEqual(self.run_editor(data), '')

    def test_large_later_record_does_not_block_discovery(self):
        data = self.metadata() + b'\n' + b'x' * (META_LIMIT + 1) + b'\n'
        self.assertEqual(self.run_editor(data), 'Codex: Untitled session\n')

    def test_refresh_without_a_project(self):
        # An empty window, or one waiting on a file (--wait), has no project to match codex sessions
        # against. The panel's refresh button still scans; the matcher must not read a null project.
        # A file opened by itself brings in its folder as the project.
        self.session.write_bytes(self.metadata() + b'\n' + self.message('user', 'Codex session'))
        file = self.project / 'standalone.txt'
        file.write_text('standalone\n', encoding='utf-8')
        script = self.home / 'commands.rsc'
        # 1280x800 at scale 1: the refresh button sits in the 40-point panel header, 8 points
        # from the right edge, 28 points square.
        script.write_text('print-project\nclick 1258 60\nwait 300\nprint-agents\nquit\n', encoding='utf-8')
        for name, paths, expected in (('project', [self.project.as_posix()], 'Codex: Codex session\n'),
                                      ('file', [file.as_posix()], 'Codex: Codex session\n'),
                                      ('wait', ['--wait', file.as_posix()], ''),
                                      ('empty', ['--empty'], '')):
            with self.subTest(window=name):
                result = subprocess.run([str(EXE), *paths, '--headless', '1280x800', '--scale', '1',
                                         '--script', script.as_posix()], env=self.env,
                                        capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', errors='replace'))
                output = result.stdout.decode('utf-8')
                project = 'project=~/' + self.project.name + '\n' if name in ('project', 'file') else 'project=\n'
                self.assertEqual(output, project + expected)


if __name__ == '__main__':
    unittest.main()
