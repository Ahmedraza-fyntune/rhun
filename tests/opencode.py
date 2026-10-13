#!/usr/bin/env python3
"""OpenCode database discovery, streaming snapshots, paging and provider failures, for OpenCode 1 and 2."""
import json
from contextlib import contextmanager
import os
from pathlib import Path
import shutil
import sqlite3
import struct
import subprocess
import sys
import tempfile
import time
import unittest

import agents

EXE = agents.EXE
ROOT = Path(__file__).resolve().parent.parent


def reader():
    """the reader Rhun runs in OpenCode 2's binary, as its source holds it"""
    line, = [line for line in (ROOT / 'src/app/agent_opencode.s').read_text().splitlines()
             if line.startswith('.Lreader: .asciz "')]
    value = line[len('.Lreader: .asciz "'):-1]
    assert '\\"' not in value
    return value.replace('\\\\', '\\')


def real_bun():
    """a Bun runtime where one is installed: OpenCode's binary as Bun, or bun"""
    for path in (os.path.expanduser('~/.opencode/bin/opencode'), shutil.which('opencode'), shutil.which('bun')):
        if not path or not os.access(path, os.X_OK): continue
        try:
            out = subprocess.run([path, '-e', 'console.log(typeof Bun)'], env=dict(os.environ, BUN_BE_BUN='1'),
                                 capture_output=True, text=True, timeout=30).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            continue
        if out == 'object': return path
    return None


BUN = real_bun() if os.name != 'nt' else None


@unittest.skipIf(os.name == 'nt', 'the test CLI uses a Unix shebang; Windows needs opencode.exe')
class OpenCodeDiscovery(unittest.TestCase):
    """OpenCode 1: sessions, messages and parts, read with `opencode db`."""
    PATH, SELECT, WITH = 'db path', 'db SELECT', 'db WITH'
    git = agents.CodexDiscovery.git
    init_repo = agents.CodexDiscovery.init_repo
    add_worktree = agents.CodexDiscovery.add_worktree

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-opencode-')
        self.home = Path(self.tmp.name).resolve()
        self.project = self.home / "project café 日本 ' with spaces"
        self.project.mkdir()
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.db = self.home / 'opencode.db'
        (self.home / 'data/opencode').mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / 'config'),
                        XDG_DATA_HOME=str(self.home / 'data'), XDG_STATE_HOME=str(self.home / 'state'),
                        PATH=str(self.bin) + os.pathsep + '/usr/bin:/bin', SHELL='/nonexistent',
                        OPENCODE_FIXTURE_DB=str(self.db))
        self.env.pop('GROK_HOME', None)
        config = self.home / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[updates]\ncheck = false\n[git]\nenabled = false\n')
        # Execute Rhun's actual SQL against the upstream schema, without running a model or server.
        # Parts are stored as OpenCode stores them: compact JSON, its type first.
        cli = self.bin / 'opencode'
        cli.write_text(f'#!{sys.executable}\n' + '''import os, sqlite3, sys
version = os.environ.get('OPENCODE_FIXTURE_VERSION', '1.19.0')
v2 = version[:1].isdigit() and int(version.split('.')[0]) >= 2
args = sys.argv[1:]
# OpenCode 2's binary as Bun, with an empty config and no .env: the reader, the database, the query
bun = args[:1] and args[0].startswith('--config=') and args[1:3] == ['--no-env-file', '-e']
if bun:
    entry = '-e ' + args[5].split()[0]
    config = args[0][len('--config='):]
    assert os.path.isabs(config) and os.path.getsize(config) == 0, config
elif len(args) > 1: entry = args[0] + ' ' + args[1].split()[0]
else: entry = args[0]
with open(os.environ['OPENCODE_FIXTURE_DB'] + '.calls', 'a') as log:
    log.write(entry + '\\n')
with open(os.environ['OPENCODE_FIXTURE_DB'] + '.cwd', 'a') as log:
    log.write(os.getcwd() + '\\n')
assert bun or 'BUN_BE_BUN' not in os.environ, args  # OpenCode itself, not Bun, answers the others
mode = os.environ.get('OPENCODE_FIXTURE_MODE', '')
if mode == 'fail': sys.exit(1)
if mode == 'fail-with' and entry.endswith(' WITH'): sys.exit(1)
if mode == 'invalid': print('not TSV'); sys.exit()
if mode == 'slow' and entry.endswith(' WITH'):
    import time; time.sleep(11)
if mode == 'hang':
    import subprocess, time
    child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
    with open(os.environ['OPENCODE_FIXTURE_DB'] + '.pids', 'a') as log:
        log.write(str(os.getpid()) + ' ' + str(child.pid) + '\\n')
    time.sleep(60)
if args == ['--version']:
    print('opencode v' + version if v2 else version); sys.exit()
if args == ['db', 'path'] and not v2:
    print(os.environ['OPENCODE_FIXTURE_DB']); sys.exit()
if args == ['debug', 'paths'] and v2:
    paths = os.environ.get('OPENCODE_FIXTURE_PATHS', '')
    end, gap = ('\\r\\n' if paths == 'crlf' else '\\n'), ('\\t' if paths == 'tab' else '         ')
    lines = ['home' + gap + os.environ['HOME'], 'data' + gap + os.path.dirname(os.environ['OPENCODE_FIXTURE_DB'])]
    if paths != 'missing': lines.append('db' + gap + os.environ['OPENCODE_FIXTURE_DB'])
    sys.stdout.write(''.join(line + end for line in lines + ['log' + gap + '/nowhere'])); sys.exit()
if v2:
    assert bun and len(args) == 6 and 'bun:sqlite' in args[3] and os.environ.get('BUN_BE_BUN') == '1', args
    assert args[4] == os.environ['OPENCODE_FIXTURE_DB'], args
    if os.environ.get('OPENCODE_FIXTURE_BUN'):  # the reader itself, in a real Bun
        with open(os.environ['OPENCODE_FIXTURE_DB'] + '.queries', 'a') as log:
            log.write(args[5] + '\\n')
        os.execv(os.environ['OPENCODE_FIXTURE_BUN'], [os.environ['OPENCODE_FIXTURE_BUN']] + args)
    sql = args[5]
else:
    assert args[0] == 'db' and args[2:] == ['--format', 'tsv'], args
    sql = args[1]
with open(os.environ['OPENCODE_FIXTURE_DB'] + '.queries', 'a') as log:
    log.write(sql + '\\n')
if os.environ.get('OPENCODE_FIXTURE_WAL') and not v2:
    # OpenCode 1 checkpoints its log on every start, also for a read: the database file changes.
    db = sqlite3.connect('file:' + os.environ['OPENCODE_FIXTURE_DB'] + '?mode=rw', uri=True)
    db.execute('PRAGMA wal_checkpoint(PASSIVE)').fetchall()
    os.utime(os.environ['OPENCODE_FIXTURE_DB'])
else:
    db = sqlite3.connect('file:' + os.environ['OPENCODE_FIXTURE_DB'] + '?mode=ro', uri=True)
rows = db.execute(sql).fetchall()
# OpenCode 1 prints nothing for no rows; rhun's reader for OpenCode 2 prints the header alone
out = ''.join(['line\\n'] + [row[0] + '\\n' for row in rows]).encode() if rows or v2 else b''
import stat
if stat.S_ISFIFO(os.fstat(1).st_mode) and not v2:
    out = out[:65536]  # OpenCode 1.19 exits before a pipe takes the rest, with status 0
sys.stdout.buffer.write(out)
''')
        cli.chmod(0o755)
        with self.connect() as db:
            db.executescript('''
CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, title TEXT, parent_id TEXT,
                      time_created INTEGER, time_updated INTEGER, time_archived INTEGER, revert TEXT);
CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER,
                      time_updated INTEGER, data TEXT);
CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT,
                   time_created INTEGER, time_updated INTEGER, data TEXT);
''')
        self.count = 0

    def tearDown(self):
        self.tmp.cleanup()

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.db)
        try:
            with db:
                yield db
        finally:
            db.close()

    def session(self, title='Local model session', cwd=None, parent=None, archived=None, updated=None):
        self.count += 1
        sid = f'ses_{self.count:05}'
        when = updated if updated is not None else 1791473123000 + self.count
        with self.connect() as db:
            db.execute('INSERT INTO session (id, directory, title, parent_id, time_created, time_updated, '
                       'time_archived) VALUES (?,?,?,?,?,?,?)',
                       (sid, str(cwd or self.project), title, parent, when - 100, when, archived))
        return sid

    def part(self, sid, role, part, index=0, updated=1791473123000):
        mid = sid + '_' + role
        pid = mid + f'_{index:05}'
        with self.connect() as db:
            db.execute('INSERT OR IGNORE INTO message VALUES (?,?,?,?,?)',
                       (mid, sid, 1 if role == 'user' else 2, updated, json.dumps({'role': role})))
            db.execute('INSERT OR REPLACE INTO part VALUES (?,?,?,?,?,?)',
                       (pid, mid, sid, updated, updated, json.dumps(part, ensure_ascii=False, separators=(',', ':'))))

    def exchange(self, sid, mid, role, when, parts, model=None):
        """a message with its parts, ordered by when; model: the reply's, or the one a prompt chose"""
        data = {'role': role}
        if model: data.update({'model': {'providerID': 'x', 'modelID': model}} if role == 'user'
                              else {'providerID': 'x', 'modelID': model})
        with self.connect() as db:
            db.execute('INSERT INTO message VALUES (?,?,?,?,?)', (mid, sid, when, when, json.dumps(data)))
            db.executemany('INSERT INTO part VALUES (?,?,?,?,?,?)', [
                (f'p{mid}_{index:05}', mid, sid, when, when, json.dumps(part, separators=(',', ':')))
                for index, part in enumerate(parts)])

    def failed_reply(self, sid, error):
        with self.connect() as db:
            db.execute('INSERT INTO message VALUES (?,?,?,?,?)', (sid + '_error', sid, 2, 3,
                       json.dumps({'role': 'assistant', 'error': error})))

    def damaged_rows(self, sid):
        with self.connect() as db:
            db.execute('INSERT INTO part VALUES (?,?,?,?,?,?)',
                       ('bad', sid + '_user', sid, 1, 1, 'not JSON {'))
            db.execute('INSERT INTO message VALUES (?,?,?,?,?)', (sid + '_bad', sid, 3, 3, '{broken'))

    def set_session(self, sid, column, value):
        with self.connect() as db: db.execute(f'UPDATE session SET {column}=? WHERE id=?', (value, sid))

    def touch_sessions(self):
        with self.connect() as db: db.execute('UPDATE session SET time_updated=time_updated+1')

    def drop_replies(self, sid):
        with self.connect() as db:
            db.execute('DELETE FROM part WHERE session_id=? AND message_id LIKE ?', (sid, '%assistant'))

    def drop_messages(self, sid):
        with self.connect() as db:
            db.execute('DELETE FROM part WHERE session_id=?', (sid,))
            db.execute('DELETE FROM message WHERE session_id=?', (sid,))

    def drop_session(self, sid):
        self.drop_messages(sid)
        with self.connect() as db: db.execute('DELETE FROM session WHERE id=?', (sid,))

    def forget_state(self):
        for state in (self.home / 'state/rhun').glob('agents-index-v6-*-opencode'): state.unlink()

    def calls(self):
        path = Path(str(self.db) + '.calls')
        return path.read_text().splitlines() if path.exists() else []

    def snapshot(self, sid):
        # src/app/diff.s hash_line, as opencode_session_path names a copy
        value = 0xcbf29ce484222325
        for byte in sid.encode():
            value = ((value ^ byte) * 0x100000001b3) & (2**64 - 1)
        value = ((value ^ len(sid.encode())) * 0x100000001b3) & (2**64 - 1)
        folder, = (self.home / 'state/rhun').glob('opencode-*')
        return folder / f'{value:x}.jsonl'

    def alive(self, pids):
        result = []
        for pid in pids:
            state = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)],
                                   capture_output=True, text=True).stdout.strip()
            if state and not state.startswith('Z'): result.append(pid)
        return result

    def bulk(self, sid, count, size, start=0, kind='text'):
        # count assistant parts of about size characters each, in one transaction
        mid = sid + '_assistant'
        def data(index):
            text = f'{sid} part {start + index} ' + 'w' * size
            if kind == 'tool':  # a field the copy does not shorten
                return {'type': 'tool', 'tool': 'batch', 'state': {
                    'status': 'completed', 'input': {'files': text}, 'output': f'{sid} out {start + index}'}}
            return {'type': kind, 'text': text}
        with self.connect() as db:
            db.execute('INSERT OR IGNORE INTO message VALUES (?,?,?,?,?)',
                       (mid, sid, 2, 1791473123000, json.dumps({'role': 'assistant'})))
            db.executemany('INSERT INTO part VALUES (?,?,?,?,?,?)', [
                (f'{mid}_bulk{start + index:05}', mid, sid, 1791473123000 + start + index,
                 1791473123000 + start + index, json.dumps(data(index), separators=(',', ':')))
                for index in range(count)])

    def worker(self, limit=50, sources='opencode', opened=None, project=None, timeout=20, cwd=None):
        args = [str(EXE), '--agent-index', str(project or self.project), str(limit), sources]
        if opened is not None: args.append(opened)
        result = subprocess.run(args, env=self.env, capture_output=True, timeout=timeout, cwd=cwd)
        self.assertEqual(result.returncode, 0, result.stderr)
        offset, rows, status, total = 0, None, None, None
        while offset < len(result.stdout):
            magic, count, total_, payload = struct.unpack_from('<8sQQQ', result.stdout, offset)
            packet = result.stdout[offset:offset + 32 + payload]
            if magic == b'RAHOPOC1': status = count
            elif magic == b'RAHPREV3': self.provisional = agents.CodexDiscovery.decode_records(packet)
            elif magic == b'RAHPAGE3':
                rows = agents.CodexDiscovery.decode_records(packet)
                total = total_
            offset += 32 + payload
        self.assertEqual(offset, len(result.stdout))
        return rows, status, total

    def editor(self, commands):
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join(commands + ['quit']) + '\n')
        result = subprocess.run([str(EXE), str(self.project), '--headless', '1280x800',
                                 '--scale', '1', '--script', str(script)], env=self.env,
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.decode()

    def test_transcript_title_text_tools_errors_and_hidden_parts(self):
        sid = self.session('A renamed session')
        self.part(sid, 'user', {'type': 'text', 'text': '# Keep the heading\nUnicode café 日本'})
        self.part(sid, 'assistant', {'type': 'reasoning', 'text': 'Not a conversation message'})
        self.part(sid, 'assistant', {'type': 'text', 'text': 'Synthetic', 'synthetic': True}, 1)
        self.part(sid, 'assistant', {'type': 'text', 'text': 'Ignored', 'ignored': True}, 2)
        self.part(sid, 'assistant', {'type': 'text', 'text': 'The function is fixed.'}, 3)
        self.part(sid, 'assistant', {'type': 'tool', 'tool': 'read', 'state': {
            'status': 'completed', 'input': {'filePath': str(self.project / 'calc.py')},
            'output': 'def add(a, b):\n    return a + b'}}, 4)
        self.part(sid, 'assistant', {'type': 'tool', 'tool': 'bash', 'state': {
            'status': 'error', 'input': {'command': 'false'}, 'error': 'Command failed'}}, 5)
        self.assertEqual(self.editor(['print-agents 1']),
                         'OpenCode: A renamed session\nuser # Keep the heading\n'
                         'agent The function is fixed.\ntool(read) calc.py\n'
                         'result def add(a, b):\ntool(bash) false\nresult Command failed\n')
        rows, status, _ = self.worker()
        self.assertEqual(status, 0)
        if os.name != 'nt': self.assertEqual(Path(rows[0]['path']).parent.stat().st_mode & 0o777, 0o700)

    def test_project_filter_subagents_archived_and_source_selection(self):
        self.session('Included')
        self.session('Subagent', parent='ses_00001')
        self.session('Archived', archived=1791473124000)
        other = self.home / 'unrelated'
        other.mkdir()
        self.session('Other project', cwd=other)
        rows, status, total = self.worker()
        self.assertEqual((status, total), (0, 1))
        self.assertEqual([(row['kind'], row['title']) for row in rows], [(4, 'Included')])
        rows, status, total = self.worker(sources='claude,codex,grok')
        self.assertEqual((rows, status, total), ([], None, 0))
        # The quoted project path must remain one SQL literal, with the apostrophe doubled.
        queries = Path(str(self.db) + '.queries').read_text()
        self.assertIn("日本 '' with spaces", queries)

    def test_empty_database_and_damaged_snapshot_rebuild(self):
        self.assertEqual(self.worker(), ([], 0, 0))
        sid = self.session()
        self.part(sid, 'user', {'type': 'text', 'text': 'Restored prompt'})
        rows, _, _ = self.worker()
        path = Path(rows[0]['path'])
        path.write_text('damaged cache\n')
        self.worker()
        self.assertIn('Restored prompt', path.read_text())
        path.unlink()
        self.worker()
        self.assertIn('Restored prompt', path.read_text())

    def test_unused_profile_does_not_initialize_or_query_opencode(self):
        (self.home / 'data/opencode').rmdir()
        self.env['OPENCODE_FIXTURE_MODE'] = 'fail'
        self.assertEqual(self.worker(), ([], 0, 0))
        self.assertFalse(Path(str(self.db) + '.queries').exists())

    def test_changed_data_profile_cannot_restore_another_profiles_cached_rows(self):
        self.session('First profile')
        self.worker()
        self.env['XDG_DATA_HOME'] = str(self.home / 'other-data')
        self.env['OPENCODE_FIXTURE_MODE'] = 'fail'
        self.assertEqual(self.worker(), ([], 0, 0))

    def test_paging_exports_only_visible_rows_and_reuses_unchanged_snapshots(self):
        for index in range(123):
            sid = self.session(f'Session {index:03}')
            self.part(sid, 'user', {'type': 'text', 'text': f'Prompt {index:03}'})
        rows, status, total = self.worker()
        self.assertEqual((len(rows), status, total), (50, 0, 123))
        files = list((self.home / 'state/rhun').glob('opencode-*/*.jsonl'))
        self.assertEqual(sum(len(p.read_text().splitlines()) > 1 for p in files), 50)
        original = {p: p.stat().st_mtime_ns for p in files}
        self.worker()
        self.assertEqual(original, {p: p.stat().st_mtime_ns for p in files})
        rows, _, total = self.worker(limit=100)
        self.assertEqual((len(rows), total), (100, 123))
        files = list((self.home / 'state/rhun').glob('opencode-*/*.jsonl'))
        self.assertEqual(sum(len(p.read_text().splitlines()) > 1 for p in files), 100)
        self.assertEqual(len(files), 100)  # rows nobody can see get no copy

    def test_paging_combines_providers_before_exporting_transcripts(self):
        for index in range(40):
            sid = self.session(f'OpenCode {index:03}')
            self.part(sid, 'user', {'type': 'text', 'text': f'Prompt {index:03}'})
        folder = self.home / '.claude/projects' / agents.claude_slug(str(self.project))
        folder.mkdir(parents=True)
        for index in range(30):
            path = folder / f'{index:03}.jsonl'
            path.write_text(json.dumps({'type': 'user', 'cwd': str(self.project),
                                       'message': {'role': 'user', 'content': f'Claude {index:03}'}}) + '\n')
            os.utime(path, (2000000000, 2000000000))
        rows, status, total = self.worker(sources='claude,opencode')
        self.assertEqual((len(rows), status, total), (50, 0, 70))
        self.assertEqual([row['kind'] for row in rows], [1] * 30 + [4] * 20)
        files = list((self.home / 'state/rhun').glob('opencode-*/*.jsonl'))
        self.assertEqual(sum(len(p.read_text().splitlines()) > 1 for p in files), 20)

    def test_streaming_same_size_changes_rename_reversion_and_delete(self):
        sid = self.session('Initial title')
        self.part(sid, 'user', {'type': 'text', 'text': 'Fix the code'})
        self.part(sid, 'assistant', {'type': 'text', 'text': 'One'})
        rows, _, _ = self.worker()
        path = Path(rows[0]['path'])
        before = path.read_bytes()
        self.part(sid, 'assistant', {'type': 'text', 'text': 'Two'}, updated=1791473123001)
        rows, _, _ = self.worker()
        self.assertNotEqual(path.read_bytes(), before)
        self.assertEqual(len(path.read_bytes()), len(before))
        self.assertTrue(rows[0]['flags'] & 4)
        self.assertEqual(self.editor(['print-agents 1']),
                         'OpenCode: Initial title\nuser Fix the code\nagent Two\n')
        self.set_session(sid, 'title', 'New title')
        self.drop_replies(sid)
        self.assertEqual(self.editor(['print-agents 1']),
                         'OpenCode: New title\nuser Fix the code\n')
        self.drop_session(sid)
        self.assertEqual(self.worker()[0], [])

    def test_worktree_history_and_reused_path_guard(self):
        self.init_repo()
        tree = self.add_worktree("fix café ' 日本")
        self.session('Main')
        sid = self.session('Worktree', cwd=tree)
        self.part(sid, 'user', {'type': 'text', 'text': 'Worktree prompt'})
        rows, _, _ = self.worker()
        self.assertEqual(rows[0]['badge'], tree.name)
        self.git('worktree', 'remove', str(tree))
        self.git('worktree', 'prune')
        rows, _, _ = self.worker()
        self.assertEqual(rows[0]['title'], 'Worktree')
        tree.mkdir()
        subprocess.run(['git', '-C', str(tree), 'init', '-q'], check=True, env=self.env)
        self.session('Foreign', cwd=tree)
        rows, _, _ = self.worker()
        self.assertEqual([r['title'] for r in rows], ['Worktree', 'Main'])

    def test_provider_failure_keeps_cache_and_other_providers_then_recovers(self):
        self.session('Keep this session')
        self.worker()
        claude = self.home / '.claude/projects' / ''.join(c if c.isascii() and c.isalnum() else '-'
                                                       for c in str(self.project)) / 'session.jsonl'
        claude.parent.mkdir(parents=True)
        claude.write_text(json.dumps({'type': 'user', 'cwd': str(self.project),
                                     'message': {'role': 'user', 'content': 'Claude continues'}}) + '\n')
        for mode in ('fail', 'invalid'):
            # a write, so the CLI runs rather than the unchanged database's cached rows standing in
            self.touch_sessions()
            self.env['OPENCODE_FIXTURE_MODE'] = mode
            rows, status, total = self.worker(sources='opencode,claude')
            self.assertEqual((status, total), (2, 2))
            self.assertEqual({r['title'] for r in rows}, {'Keep this session', 'Claude continues'})
        self.env.pop('OPENCODE_FIXTURE_MODE')
        self.assertEqual(self.worker()[1], 0)

    def test_missing_cli_retains_history_and_reports_setup(self):
        if any(os.access(path, os.X_OK) for path in
               ('/opt/homebrew/bin/opencode', '/usr/local/bin/opencode', '/usr/bin/opencode')):
            self.skipTest('a system OpenCode installation is available as a fallback')
        self.session('Saved history')
        self.worker()
        (self.bin / 'opencode').rename(self.bin / 'opencode-disabled')
        rows, status, total = self.worker()
        self.assertEqual((status, total), (1, 1))
        self.assertEqual(rows[0]['title'], 'Saved history')

    def test_open_session_keeps_refreshing_after_it_leaves_the_page(self):
        sid = self.session('Pinned old session', updated=1)
        self.part(sid, 'assistant', {'type': 'text', 'text': 'Before'}, updated=1)
        old, _, _ = self.worker()
        for index in range(51): self.session(f'New {index:03}')
        self.part(sid, 'assistant', {'type': 'text', 'text': 'After'}, updated=2)
        self.worker(opened=old[0]['path'])
        self.assertIn('After', Path(old[0]['path']).read_text())
        self.assertNotIn('Before', Path(old[0]['path']).read_text())

    def test_pinned_open_conversation_updates_in_the_running_editor(self):
        sid = self.session('Pinned', updated=1)
        self.part(sid, 'assistant', {'type': 'text', 'text': 'Before'}, updated=1)
        script = self.home / 'live.rsc'
        script.write_text('print-agents 1\nwait 11000\nprint-agents\nquit\n')
        process = subprocess.Popen([str(EXE), str(self.project), '--headless', '1280x800',
                                    '--script', str(script)], env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.assertEqual(process.stdout.readline(), b'OpenCode: Pinned\n')
            self.assertEqual(process.stdout.readline(), b'agent Before\n')
            for index in range(51): self.session(f'New {index:03}')
            self.part(sid, 'assistant', {'type': 'text', 'text': 'After!'}, updated=2)
            output, errors = process.communicate(timeout=20)
            self.assertEqual(process.returncode, 0, errors)
            self.assertEqual(output.count(b'agent After!\n'), 1)
            self.assertNotIn(b'agent Before\n', output)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_quitting_stops_a_hung_cli_and_its_children(self):
        self.env['OPENCODE_FIXTURE_MODE'] = 'hang'
        self.editor(['wait 1000'])
        pids = [int(p) for p in Path(str(self.db) + '.pids').read_text().split()]
        try:
            for _ in range(20):
                alive = self.alive(pids)
                if not alive: break
                time.sleep(0.1)
            self.assertEqual(alive, [], 'database CLI children must exit with the editor')
        finally:
            for pid in alive:
                try: os.kill(pid, 9)
                except ProcessLookupError: pass

    def test_model_error_is_visible_without_an_assistant_text_part(self):
        sid = self.session('Failed request')
        self.part(sid, 'user', {'type': 'text', 'text': 'Try the local model'})
        self.failed_reply(sid, {'name': 'APIError', 'data': {'message': 'Local model server unavailable'}})
        self.assertEqual(self.editor(['print-agents 1']),
                         'OpenCode: Failed request\nuser Try the local model\n'
                         'result Local model server unavailable\n')

    def test_unchanged_database_is_not_queried_again(self):
        sid = self.session('Quiet')
        self.part(sid, 'user', {'type': 'text', 'text': 'Prompt'})
        self.worker()
        self.assertEqual(self.calls(), ['--version', self.PATH, self.SELECT, self.WITH])
        self.worker()
        rows, status, total = self.worker()
        self.assertEqual((status, total, rows[0]['title']), (0, 1, 'Quiet'))
        self.assertEqual(len(self.calls()), 4)
        self.part(sid, 'assistant', {'type': 'text', 'text': 'Reply'}, 1)
        rows, _, _ = self.worker()
        self.assertEqual(self.calls()[4:], [self.SELECT, self.WITH])  # the path and version are kept
        self.assertIn('Reply', Path(rows[0]['path']).read_text())
        self.assertEqual(self.editor(['print-agents 1']), 'OpenCode: Quiet\nuser Prompt\nagent Reply\n')

    def test_wal_checkpoint_on_every_cli_start_is_not_a_change(self):
        with self.connect() as db: db.execute('PRAGMA journal_mode=WAL').fetchall()
        keeper = sqlite3.connect(self.db)  # a running OpenCode keeps the log
        try:
            keeper.execute('SELECT count(*) FROM session').fetchall()
            self.env['OPENCODE_FIXTURE_WAL'] = '1'
            sid = self.session('Logged')
            self.part(sid, 'user', {'type': 'text', 'text': 'First'})
            rows, status, _ = self.worker()
            self.assertEqual(status, 0)
            self.assertTrue(Path(str(self.db) + '-wal').exists())
            self.worker()  # the database size the first run's checkpoint left
            calls = len(self.calls())
            self.worker()
            self.worker()
            self.assertEqual(len(self.calls()), calls)
            self.part(sid, 'assistant', {'type': 'text', 'text': 'Second'}, 1)
            self.worker()
            self.assertEqual(self.calls()[calls:calls + 2], [self.SELECT, self.WITH])
            self.assertIn('Second', Path(rows[0]['path']).read_text())
        finally:
            keeper.close()

    def test_cli_update_or_database_variable_asks_for_the_path_again(self):
        self.session('Path')
        self.worker()
        os.utime(self.bin / 'opencode', ns=(1, 1))  # an update replaces the CLI
        self.worker()
        self.worker()
        self.env['OPENCODE_DB'] = 'other.db'
        self.worker()
        self.assertEqual(self.calls().count('--version'), 3)
        self.assertEqual(self.calls().count(self.PATH), 3)
        self.assertEqual(self.calls().count(self.SELECT), 3)

    def test_unchanged_database_is_queried_again_after_five_minutes(self):
        self.session('Old')
        self.worker()
        state = next((self.home / 'state/rhun').glob('agents-index-v6-*-opencode'))
        data = bytearray(state.read_bytes())
        struct.pack_into('<q', data, 32, struct.unpack_from('<q', data, 32)[0] - 301)
        state.write_bytes(bytes(data))
        self.worker()
        self.worker()
        self.assertEqual(self.calls().count(self.SELECT), 2)

    def test_opening_an_unexported_conversation_of_an_unchanged_database(self):
        sid = self.session('Old', updated=1)
        self.part(sid, 'assistant', {'type': 'text', 'text': 'Old reply'}, updated=1)
        for index in range(50): self.session(f'New {index:03}')
        rows, _, total = self.worker()
        self.assertEqual((len(rows), total), (50, 51))
        old = self.snapshot(sid)
        self.assertFalse(old.exists())
        self.worker(opened=str(old))
        self.assertIn('Old reply', old.read_text())

    def test_cli_stopped_on_its_timeout_leaves_no_process_behind(self):
        self.env['OPENCODE_FIXTURE_MODE'] = 'hang'
        start = time.time()
        self.editor(['wait 17000'])  # the worker stops the CLI after 15 seconds, then finishes
        self.assertGreater(time.time() - start, 16)
        pids = [int(p) for p in Path(str(self.db) + '.pids').read_text().split()]
        self.assertEqual(len(pids), 2)
        alive = self.alive(pids)
        try:
            self.assertEqual(alive, [], 'the CLI child must not outlive the worker')
        finally:
            for pid in alive:
                try: os.kill(pid, 9)
                except ProcessLookupError: pass

    def test_without_a_data_folder_nothing_asks_to_install_the_cli(self):
        (self.home / 'data/opencode').rmdir()
        (self.bin / 'opencode').unlink()
        self.assertEqual(self.worker(), ([], 0, 0))

    def test_deleted_and_archived_sessions_leave_no_copy(self):
        keep = self.session('Keep')
        self.part(keep, 'user', {'type': 'text', 'text': 'Kept'})
        gone = self.session('Deleted')
        self.part(gone, 'user', {'type': 'text', 'text': 'Private'})
        hidden = self.session('Archived later')
        self.part(hidden, 'user', {'type': 'text', 'text': 'Also private'})
        self.worker()
        self.assertTrue(all(self.snapshot(sid).exists() for sid in (keep, gone, hidden)))
        self.drop_session(gone)
        self.set_session(hidden, 'time_archived', 1)
        rows, _, _ = self.worker()
        self.assertEqual([r['title'] for r in rows], ['Keep'])
        self.assertEqual([self.snapshot(sid).exists() for sid in (keep, gone, hidden)], [True, False, False])

    def test_unreadable_rows_are_left_out_of_the_transcript(self):
        sid = self.session('Damaged rows')
        self.part(sid, 'user', {'type': 'text', 'text': 'Readable prompt'})
        self.damaged_rows(sid)
        self.part(sid, 'assistant', {'type': 'text', 'text': 'Readable reply'})
        rows, status, _ = self.worker()
        self.assertEqual(status, 0)
        self.assertEqual(self.editor(['print-agents 1']),
                         'OpenCode: Damaged rows\nuser Readable prompt\nagent Readable reply\n')

    def test_transcript_past_a_pipe_buffer_arrives_whole(self):
        sid = self.session('Long')
        for index in range(400):
            self.part(sid, 'assistant', {'type': 'text', 'text': f'Reply {index:03} ' + 'x' * 400}, index)
        self.part(sid, 'assistant', {'type': 'text', 'text': 'The last reply'}, 400)
        rows, status, _ = self.worker()
        self.assertEqual(status, 0)
        text = Path(rows[0]['path']).read_text()
        self.assertGreater(len(text), 150000)
        self.assertIn('The last reply', text)

    def test_large_transcripts_are_copied_in_batches(self):
        sids = [self.session(f'Big {index}') for index in range(3)]
        for sid in sids: self.bulk(sid, 60, 60000)  # 3.6 MB each
        rows, status, _ = self.worker()
        self.assertEqual(status, 0)
        self.assertEqual(self.calls().count(self.WITH), 2)  # 8 MB a query
        for sid in sids: self.assertIn(f'{sid} part 59 www', self.snapshot(sid).read_text())

    def test_giant_parts_are_copied_with_their_start(self):
        sid = self.session('Giant parts')
        self.part(sid, 'user', {'type': 'text', 'text': 'Pasted log ' + 'p' * 2000000})
        self.part(sid, 'assistant', {'type': 'reasoning', 'text': 'r' * 2000000}, 1)
        self.part(sid, 'assistant', {'type': 'tool', 'tool': 'read', 'state': {
            'status': 'completed', 'input': {'filePath': str(self.project / 'big.txt')},
            'output': 'File start ' + 'o' * 2000000, 'metadata': {'preview': 'm' * 2000000}}}, 2)
        self.part(sid, 'assistant', {'type': 'text', 'text': 'Summary after the read'}, 3)
        rows, status, _ = self.worker()
        self.assertEqual(status, 0)
        text = self.snapshot(sid).read_text()
        self.assertLess(len(text), 120000)
        self.assertNotIn('rrrr', text)
        lines = self.editor(['print-agents 1']).splitlines()
        self.assertEqual([line[:17] for line in lines],
                         ['OpenCode: Giant p', 'user Pasted log p', 'tool(read) big.tx',
                          'result File start', 'agent Summary aft'])

    def test_conversation_past_the_output_limit_is_listed_and_not_tried_again(self):
        huge = self.session('Huge')
        self.bulk(huge, 650, 66000)  # 43 MB
        small = self.session('Small')
        self.part(small, 'user', {'type': 'text', 'text': 'Small prompt'})
        rows, status, total = self.worker()
        self.assertEqual((status, total), (0, 2))
        self.assertEqual(self.calls().count(self.WITH), 1)
        self.assertIn('Small prompt', self.snapshot(small).read_text())
        self.assertEqual(len(self.snapshot(huge).read_text().splitlines()), 1)  # the title alone
        calls = len(self.calls())
        self.worker()
        self.assertEqual(len(self.calls()), calls)

    def test_conversation_growing_past_the_output_limit_loses_its_old_copy(self):
        sid = self.session('Growing')
        self.part(sid, 'user', {'type': 'text', 'text': 'Early prompt'})
        self.worker()
        self.assertIn('Early prompt', self.snapshot(sid).read_text())
        self.bulk(sid, 650, 66000, start=1)
        rows, status, _ = self.worker()
        self.assertEqual(status, 0)
        self.assertTrue(rows[0]['flags'] & 4)  # replaced: the panel reads the copy again
        self.assertNotIn('Early prompt', self.snapshot(sid).read_text())

    def test_another_database_variable_hides_the_previous_databases_rows(self):
        self.session('First database')
        self.assertEqual(len(self.worker()[0]), 1)
        self.env['OPENCODE_DB'] = 'other.db'
        self.env['OPENCODE_FIXTURE_MODE'] = 'fail'
        self.assertEqual(self.worker()[:2], ([], 2))
        self.assertEqual(self.provisional, [])

    def test_windows_of_one_repository_share_the_unchanged_database(self):
        self.init_repo()
        tree = self.add_worktree('second window')
        main = self.session('Main window')
        self.part(main, 'user', {'type': 'text', 'text': 'Main prompt'})
        other = self.session('Worktree window', cwd=tree)
        self.part(other, 'user', {'type': 'text', 'text': 'Worktree prompt'})
        self.worker()
        self.worker(project=tree)
        calls = len(self.calls())
        for _ in range(2):
            self.assertEqual(len(self.worker()[0]), 2)
            self.assertEqual(len(self.worker(project=tree)[0]), 2)
        self.assertEqual(len(self.calls()), calls)

    def test_copies_past_the_run_time_continue_in_the_next_run(self):
        sids = [self.session(f'Slow {index}') for index in range(3)]
        for sid in sids: self.bulk(sid, 90, 66000)  # each a query of its own
        self.env['OPENCODE_FIXTURE_MODE'] = 'slow'
        start = time.time()
        rows, status, _ = self.worker(timeout=45)
        self.assertLess(time.time() - start, 40)
        self.assertEqual((len(rows), status), (3, 0))  # out of time is not a failure
        copied = [self.snapshot(sid).exists() for sid in sids]
        self.assertEqual(sorted(copied), [False, True, True])
        self.env.pop('OPENCODE_FIXTURE_MODE')
        self.worker()
        self.assertTrue(all(self.snapshot(sid).exists() for sid in sids))

    def test_the_cli_runs_in_rhuns_state_folder_never_the_editors(self):
        # OpenCode 2's binary as Bun reads a bunfig.toml (its preload runs code) and a .env where it starts
        sid = self.session('Folder')
        self.part(sid, 'user', {'type': 'text', 'text': 'Prompt'})
        self.assertEqual(self.worker(cwd=self.project)[1], 0)
        folders = set(Path(str(self.db) + '.cwd').read_text().splitlines())
        self.assertEqual({Path(folder).resolve() for folder in folders}, {(self.home / 'state/rhun').resolve()})

    def test_a_relative_path_entry_finds_the_cli(self):
        sid = self.session('Relative')
        self.part(sid, 'user', {'type': 'text', 'text': 'Prompt'})
        self.env['PATH'] = 'bin' + os.pathsep + '/usr/bin:/bin'
        rows, status, _ = self.worker(cwd=self.home)
        self.assertEqual((status, rows[0]['title']), (0, 'Relative'))

    def test_a_failed_transcript_query_asks_the_cli_again(self):
        sid = self.session('Transcript fails')
        self.part(sid, 'user', {'type': 'text', 'text': 'Prompt'})
        self.env['OPENCODE_FIXTURE_MODE'] = 'fail-with'
        self.assertEqual(self.worker()[1], 2)
        self.env.pop('OPENCODE_FIXTURE_MODE')
        calls = len(self.calls())
        rows, status, _ = self.worker()
        self.assertEqual((status, rows[0]['title']), (0, 'Transcript fails'))
        self.assertEqual(self.calls()[calls:], ['--version', self.PATH, self.SELECT, self.WITH])
        self.assertIn('Prompt', self.snapshot(sid).read_text())

    def test_damaged_state_file_asks_the_cli_again(self):
        self.session('State')
        self.worker()
        state = next((self.home / 'state/rhun').glob('agents-index-v6-*-opencode'))
        saved = state.read_bytes()
        # 0.17.12's state (RAHOCST1) did not know OpenCode's version
        for damage in (b'', b'RAHOCST1', saved[:48], b'x' * 60, b'RAHOCST1' + saved[8:40] + saved[48:],
                       saved[:40] + struct.pack('<Q', 7) + saved[48:]):
            state.write_bytes(damage)
            before = self.calls().count(self.PATH)
            rows, status, _ = self.worker()
            self.assertEqual((status, [r['title'] for r in rows]), (0, ['State']))
            self.assertEqual(self.calls().count(self.PATH), before + 1)

    def test_one_conversation_past_the_output_limit_keeps_its_title_alone(self):
        sid = self.session('Overflowing')
        self.bulk(sid, 70, 1000000, kind='tool')  # estimated small, 70 MB copied
        rows, status, total = self.worker(timeout=60)
        self.assertEqual((status, total, rows[0]['title']), (0, 1, 'Overflowing'))
        self.assertEqual(len(self.snapshot(sid).read_text().splitlines()), 1)
        calls = len(self.calls())
        self.worker()
        self.assertEqual(len(self.calls()), calls)

    def test_batch_past_the_output_limit_is_copied_one_by_one(self):
        sids = [self.session(f'Half {index}') for index in range(2)]
        for sid in sids: self.bulk(sid, 40, 1000000, kind='tool')  # 40 MB each, one batch
        rows, status, _ = self.worker(timeout=60)
        self.assertEqual(status, 0)
        self.assertEqual(self.calls().count(self.WITH), 3)
        for sid in sids: self.assertIn(f'{sid} out 39', self.snapshot(sid).read_text())

    def test_reasoning_does_not_count_toward_the_size_limit(self):
        sid = self.session('Thoughtful')
        self.part(sid, 'user', {'type': 'text', 'text': 'Short question'})
        self.bulk(sid, 400, 66000, start=1, kind='reasoning')  # 26 MB, none of it copied
        self.part(sid, 'assistant', {'type': 'text', 'text': 'Short answer'}, 999)
        rows, status, _ = self.worker()
        self.assertEqual(status, 0)
        text = self.snapshot(sid).read_text()
        self.assertIn('Short question', text)
        self.assertIn('Short answer', text)
        self.assertLess(len(text), 10000)

    def test_undone_messages_are_left_out_until_redone(self):
        sid = self.session('Undo')
        # message IDs that do not sort by time: OpenCode orders by time (OpenCode 2: by seq), then ID
        for mid, role, when, text in (('m9', 'user', 1, 'First prompt'), ('m8', 'assistant', 2, 'First reply'),
                                      ('m7', 'user', 3, 'Second prompt'), ('m6', 'assistant', 4, 'Second reply')):
            self.exchange(sid, mid, role, when, [{'type': 'text', 'text': text}])
        full = 'OpenCode: Undo\nuser First prompt\nagent First reply\nuser Second prompt\nagent Second reply\n'
        self.assertEqual(self.editor(['print-agents 1']), full)
        # /undo: the rows stay, session.revert marks where the conversation ends
        self.set_session(sid, 'revert', json.dumps({'messageID': 'm7'}))
        self.assertEqual(self.editor(['print-agents 1']), 'OpenCode: Undo\nuser First prompt\nagent First reply\n')
        self.set_session(sid, 'revert', json.dumps({'messageID': 'unknown'}))  # as OpenCode: nothing is undone
        self.assertEqual(self.editor(['print-agents 1']), full)
        self.set_session(sid, 'revert', 'not JSON {')
        self.assertEqual(self.editor(['print-agents 1']), full)
        self.set_session(sid, 'revert', None)  # /redo
        self.assertEqual(self.editor(['print-agents 1']), full)

    def test_undone_tail_does_not_count_toward_the_size_limit(self):
        sid = self.session('Undone tail')
        for mid, role, when, text in (('a1', 'user', 1, 'Short prompt'), ('a2', 'assistant', 2, 'Short reply'),
                                      ('a3', 'user', 3, 'Big request')):
            self.exchange(sid, mid, role, when, [{'type': 'text', 'text': text}])
        self.exchange(sid, 'a4', 'assistant', 4, [{'type': 'text', 'text': 'u' * 66000}] * 400)  # 26 MB, past the limit
        self.set_session(sid, 'revert', json.dumps({'messageID': 'a3'}))
        rows, status, _ = self.worker()
        self.assertEqual(status, 0)
        self.assertEqual(self.editor(['print-agents 1']),
                         'OpenCode: Undone tail\nuser Short prompt\nagent Short reply\n')

    def test_reused_worktree_path_keeps_unexported_history_on_an_unchanged_database(self):
        self.init_repo()
        tree = self.add_worktree('reused')
        old = self.session('Old worktree session', cwd=tree, updated=1)
        for index in range(50): self.session(f'Main {index:03}')
        rows, _, total = self.worker()
        self.assertEqual(total, 51)
        self.assertFalse(self.snapshot(old).exists())  # past the page: never copied
        self.git('worktree', 'remove', str(tree))
        self.git('worktree', 'prune')
        tree.mkdir()
        subprocess.run(['git', '-C', str(tree), 'init', '-q'], check=True, env=self.env)
        for _ in range(2): self.assertEqual(self.worker()[2], 51)

    def test_title_only_copy_that_cannot_be_saved_is_a_failure(self):
        sid = self.session('Unsaved')
        self.bulk(sid, 400, 66000)  # past the size limit
        self.worker()  # makes the copies' folder
        self.snapshot(sid).unlink()
        self.snapshot(sid).mkdir()  # nothing can be saved there
        self.set_session(sid, 'title', 'Unsaved again')
        start = time.time()
        rows, status, _ = self.worker()
        self.assertEqual((status, rows[0]['title']), (2, 'Unsaved again'))
        self.assertLess(time.time() - start, 10)

    def test_overflowing_copy_that_cannot_be_saved_does_not_query_again(self):
        sid = self.session('Overflow unsaved')
        self.bulk(sid, 70, 1000000, kind='tool')
        self.worker(timeout=60)
        self.snapshot(sid).unlink()
        self.snapshot(sid).mkdir()
        self.set_session(sid, 'title', 'Changed')
        before = self.calls().count(self.WITH)
        rows, status, _ = self.worker(timeout=60)
        self.assertEqual(status, 2)
        self.assertEqual(self.calls().count(self.WITH), before + 1)

    def test_switches_and_a_config_from_before_them(self):
        self.session('Switched')
        config = self.home / 'config/rhun/config'
        base = '[updates]\ncheck = false\n[git]\nenabled = false\n'
        # 0.17.8 to 0.17.11 saved the default selection, which knew no OpenCode
        config.write_text(base + '[agents]\nsources = claude codex grok\n')
        self.assertEqual(self.editor(['print-agents']), 'OpenCode: Switched\n')
        config.write_text(base + '[agents]\nopencode = false\n')
        self.assertEqual(self.editor(['print-agents']), '')
        config.write_text(base + '[agents]\nsources = codex\n')
        self.editor(['cmd toggle_vim'])  # a change saves the file
        saved = config.read_text()
        self.assertNotIn('sources', saved)
        self.assertIn('[agents]\nclaude = false\ncodex = true\ngrok = false\nopencode = true\n', saved)

    def test_models_in_the_row_and_where_replies_change(self):
        sid = self.session('Models')
        for mid, role, when, model, text in (
                ('n1', 'user', 1, 'qwen3.6', 'Prompt'), ('n2', 'assistant', 2, 'qwen3.6', 'First reply'),
                ('n3', 'assistant', 3, 'qwen3.6', 'Second reply'), ('n4', 'user', 4, 'big-pickle', 'Switch'),
                ('n5', 'assistant', 5, 'big-pickle', 'Third reply')):
            self.exchange(sid, mid, role, when, [{'type': 'text', 'text': text}], model)
        rows, _, _ = self.worker()
        self.assertEqual(rows[0]['model'], 'big-pickle')
        self.assertEqual(self.editor(['print-agents 1']),
                         'OpenCode [model: big-pickle]: Models\nuser Prompt\nagent(qwen3.6) First reply\n'
                         'agent Second reply\nuser Switch\nagent(big-pickle) Third reply\n')

    def test_row_keeps_the_latest_model_also_of_a_reply_of_tools(self):
        sid = self.session('Tools last')
        for mid, when, model, part in (
                ('t1', 1, 'one', {'type': 'text', 'text': 'Text reply'}),
                ('t2', 2, 'two', {'type': 'tool', 'tool': 'bash', 'state': {
                    'status': 'completed', 'input': {'command': 'make'}, 'output': 'ok'}})):
            self.exchange(sid, mid, 'assistant', when, [part], model)
        self.assertEqual(self.worker()[0][0]['model'], 'two')
        output = self.editor(['print-agents 1', 'print-agents'])
        self.assertEqual(output.splitlines()[0], 'OpenCode [model: two]: Tools last')
        self.assertEqual(output.splitlines()[-4], 'OpenCode [model: two]: Tools last')

    def test_row_model_goes_with_the_messages_that_named_it(self):
        sid = self.session('Emptied')
        self.exchange(sid, 'e1', 'assistant', 1, [{'type': 'text', 'text': 'Reply'}], 'gone-model')
        self.assertEqual(self.worker()[0][0]['model'], 'gone-model')
        self.drop_messages(sid)
        self.assertEqual(self.worker()[0][0]['model'], '')
        self.assertEqual(self.editor(['print-agents']), 'OpenCode: Emptied\n')



class OpenCode2Discovery(OpenCodeDiscovery):
    """OpenCode 2: session_v2 and session_message, read by the Bun runtime its binary is built on. The
    database keeps OpenCode 1's tables, which OpenCode 2 no longer writes. Every test above runs on these
    tables too: OpenCode 1's parts are written as OpenCode 2 stores a message's content."""
    PATH, SELECT, WITH = 'debug paths', '-e SELECT', '-e WITH'

    def setUp(self):
        super().setUp()
        self.env['OPENCODE_FIXTURE_VERSION'] = '2.0.28'
        self.items = {}
        with self.connect() as db:
            db.executescript("""
CREATE TABLE session_v2 (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, parent_id TEXT, slug TEXT NOT NULL,
                         directory TEXT NOT NULL, title TEXT, version TEXT NOT NULL, revert TEXT, model TEXT,
                         time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, time_archived INTEGER);
CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL,
                              seq INTEGER NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL,
                              data TEXT NOT NULL);
""")

    @staticmethod
    def content(part, index):
        """an OpenCode 1 part as OpenCode 2 keeps it in a message's content, or None for what it does not"""
        if part.get('synthetic') or part.get('ignored'): return None
        if part['type'] in ('text', 'reasoning'): return {'type': part['type'], 'text': part['text']}
        if part['type'] != 'tool': return None
        state = part['state']
        item = {'status': state['status'], 'input': state.get('input', {})}
        if 'error' in state: item['error'] = {'type': 'tool.execution', 'message': state['error']}
        else: item['content'] = [{'type': 'text', 'text': state['output']}] if 'output' in state else []
        if 'metadata' in state: item['metadata'] = state['metadata']
        return {'type': 'tool', 'id': f'call{index}', 'name': part['tool'], 'state': item}

    def message(self, db, sid, mid, kind, seq, data):
        data = dict({'time': {'created': seq}}, **data)
        db.execute('INSERT OR REPLACE INTO session_message VALUES (?,?,?,?,?,?,?)',
                   (mid, sid, kind, seq, seq, seq, json.dumps(data, ensure_ascii=False, separators=(',', ':'))))

    def items_message(self, db, sid, mid, role, seq, items, model=None, error=None):
        items = [item for item in items if item]
        if role == 'user':
            data = {'text': '\n'.join(i['text'] for i in items if i['type'] == 'text'), 'files': [], 'agents': []}
        else:
            data = {'agent': 'build', 'content': items}
            if model: data['model'] = {'id': model, 'providerID': 'x'}
            if error: data['error'] = error
        self.message(db, sid, mid, role, seq, data)

    def session(self, title='Local model session', cwd=None, parent=None, archived=None, updated=None):
        self.count += 1
        sid = f'ses_{self.count:05}'
        when = updated if updated is not None else 1791473123000 + self.count
        with self.connect() as db:
            db.execute('INSERT INTO session_v2 (id, project_id, parent_id, slug, directory, title, version, '
                       'time_created, time_updated, time_archived) VALUES (?,?,?,?,?,?,?,?,?,?)',
                       (sid, 'global', parent, sid, str(cwd or self.project), title, '2.0.28', when - 100, when,
                        archived))
        return sid

    def part(self, sid, role, part, index=0, updated=1791473123000):
        parts = self.items.setdefault((sid, role), {})
        parts[index] = part
        with self.connect() as db:
            self.items_message(db, sid, sid + '_' + role, role, 1 if role == 'user' else 2,
                               [self.content(parts[i], i) for i in sorted(parts)])
            db.execute('UPDATE session_message SET time_updated=? WHERE id=?', (updated, sid + '_' + role))

    def bulk(self, sid, count, size, start=0, kind='text'):
        parts = self.items.setdefault((sid, 'assistant'), {})
        for index in range(count):
            text = f'{sid} part {start + index} ' + 'w' * size
            parts[100000 + start + index] = ({'type': 'tool', 'tool': 'batch', 'state': {
                'status': 'completed', 'input': {'files': text}, 'output': f'{sid} out {start + index}'}}
                if kind == 'tool' else {'type': kind, 'text': text})
        with self.connect() as db:
            self.items_message(db, sid, sid + '_assistant', 'assistant', 2,
                               [self.content(parts[i], i) for i in sorted(parts)])

    def exchange(self, sid, mid, role, when, parts, model=None):
        with self.connect() as db:
            if role == 'user' and model:  # OpenCode 2 notes the model chosen for a prompt as a switch
                self.message(db, sid, mid + '_switch', 'model-switched', when * 10 - 5,
                             {'model': {'id': model, 'providerID': 'x'}})
            self.items_message(db, sid, mid, role, when * 10,
                               [self.content(part, index) for index, part in enumerate(parts)],
                               None if role == 'user' else model)

    def failed_reply(self, sid, error):
        with self.connect() as db: self.items_message(db, sid, sid + '_error', 'assistant', 3, [], error=error)

    def damaged_rows(self, sid):
        with self.connect() as db:
            for mid, kind, seq, data in (('bad1', 'user', 3, 'not JSON {'), ('bad2', 'assistant', 4, '{broken'),
                                         ('bad3', 'assistant', 5, '{"content":"not a list"}'),
                                         ('bad4', 'assistant', 6, '{"content":["text",7,null,[1]]}')):
                db.execute('INSERT INTO session_message VALUES (?,?,?,?,?,?,?)', (mid, sid, kind, seq, seq, seq, data))

    def set_session(self, sid, column, value):
        with self.connect() as db: db.execute(f'UPDATE session_v2 SET {column}=? WHERE id=?', (value, sid))

    def touch_sessions(self):
        with self.connect() as db: db.execute('UPDATE session_v2 SET time_updated=time_updated+1')

    def drop_replies(self, sid):
        self.items.pop((sid, 'assistant'), None)
        with self.connect() as db:
            db.execute("DELETE FROM session_message WHERE session_id=? AND type='assistant'", (sid,))

    def drop_messages(self, sid):
        self.items = {key: value for key, value in self.items.items() if key[0] != sid}
        with self.connect() as db: db.execute('DELETE FROM session_message WHERE session_id=?', (sid,))

    def drop_session(self, sid):
        self.drop_messages(sid)
        with self.connect() as db: db.execute('DELETE FROM session_v2 WHERE id=?', (sid,))

    def test_opencode_2_is_read_by_its_runtime_never_by_a_db_command(self):
        sid = self.session('Bun')
        self.part(sid, 'user', {'type': 'text', 'text': 'Prompt'})
        rows, status, _ = self.worker()
        self.assertEqual((status, rows[0]['title']), (0, 'Bun'))
        # `opencode db` alone would start OpenCode 2's interface in a folder named db
        self.assertEqual(self.calls(), ['--version', 'debug paths', '-e SELECT', '-e WITH'])

    def test_bookkeeping_rows_and_opencode_2_tools(self):
        sid = self.session('Two')
        project = str(self.project)
        with self.connect() as db:
            for mid, kind, seq, data in (
                    ('u1', 'user', 1, {'text': 'Explain the code', 'files': [], 'agents': []}),
                    ('s1', 'system', 2, {'text': 'The available tools have changed.'}),
                    ('y1', 'synthetic', 3, {'text': 'A synthetic note'}),
                    ('a1', 'assistant', 4, {'agent': 'build', 'model': {'id': 'm1', 'providerID': 'x'}, 'content': [
                        {'type': 'reasoning', 'text': 'Thinking it over'},
                        {'type': 'text', 'text': 'Reading it.'},
                        {'type': 'tool', 'id': 'c1', 'name': 'read', 'state': {
                            'status': 'completed', 'input': {'filePath': project + '/calc.py'},
                            'content': [{'type': 'text', 'text': 'def add(a, b):'},
                                        {'type': 'text', 'text': '    return a + b'}], 'metadata': {}}},
                        {'type': 'tool', 'id': 'c2', 'name': 'shell', 'state': {
                            'status': 'error', 'input': {'command': 'false'},
                            'error': {'type': 'tool.execution', 'message': 'Command failed'}}}]}),
                    ('i1', 'idle', 5, {'outcome': 'succeeded'}),
                    ('w1', 'model-switched', 6, {'model': {'id': 'm2', 'providerID': 'x'},
                                                 'previous': {'id': 'm1', 'providerID': 'x'}}),
                    ('u2', 'user', 7, {'text': 'Stop', 'files': [], 'agents': []}),
                    ('a2', 'assistant', 8, {'agent': 'build', 'model': {'id': 'm2', 'providerID': 'x'},
                                            'content': [], 'error': {'type': 'aborted', 'message': 'Aborted'}}),
                    # a command the user ran (!make test), and more bookkeeping
                    ('h1', 'shell', 9, {'shellID': 'sh1', 'command': 'make test', 'status': 'completed', 'exit': 0,
                                        'output': {'output': 'All tests passed\n3 run', 'cursor': 0, 'size': 23,
                                                   'truncated': False}}),
                    ('h2', 'shell', 10, {'shellID': 'sh2', 'command': 'sleep 9', 'status': 'running'}),
                    ('k1', 'skill', 11, {'skill': {}, 'name': 'review', 'text': 'Skill instructions'}),
                    ('c1', 'compaction', 12, {'status': 'completed', 'reason': 'auto', 'summary': 'A summary',
                                              'recent': ''}),
                    ('g1', 'agent-switched', 13, {'agent': 'plan'}),
                    ('l1', 'location-switched', 14, {'location': {}})):
                self.message(db, sid, mid, kind, seq, data)
        self.assertEqual(self.worker()[0][0]['model'], 'm2')
        self.assertEqual(self.editor(['print-agents 1']),
                         'OpenCode [model: m2]: Two\nuser Explain the code\nagent(m1) Reading it.\n'
                         'tool(read) calc.py\nresult def add(a, b):\ntool(shell) false\nresult Command failed\n'
                         'user Stop\nresult Aborted\ntool(shell) make test\nresult All tests passed\n'
                         'tool(shell) sleep 9\n')  # still running: no output yet

    def test_a_prompt_waiting_for_its_reply_shows_the_sessions_model(self):
        sid = self.session('Waiting')
        self.set_session(sid, 'model', json.dumps({'id': 'session-model', 'providerID': 'x'}))
        self.part(sid, 'user', {'type': 'text', 'text': 'Prompt'})
        self.assertEqual(self.worker()[0][0]['model'], 'session-model')
        self.exchange(sid, 'r1', 'assistant', 2, [{'type': 'text', 'text': 'Reply'}], 'reply-model')
        self.assertEqual(self.worker()[0][0]['model'], 'reply-model')
        with self.connect() as db:
            self.message(db, sid, 'w1', 'model-switched', 30, {'model': {'id': 'next-model', 'providerID': 'x'}})
        self.assertEqual(self.worker()[0][0]['model'], 'next-model')

    def test_after_an_upgrade_from_opencode_1_its_new_tables_are_read(self):
        self.env['OPENCODE_FIXTURE_VERSION'] = '1.19.0'
        old = OpenCodeDiscovery.session(self, 'Before the upgrade')
        OpenCodeDiscovery.part(self, old, 'user', {'type': 'text', 'text': 'Old prompt'})
        stale = OpenCodeDiscovery.session(self, 'Left in the old tables')
        rows, status, _ = self.worker()
        self.assertEqual((status, sorted(r['title'] for r in rows)), (0, ['Before the upgrade', 'Left in the old tables']))
        self.assertTrue(self.snapshot(stale).exists())
        # OpenCode 2 copies the sessions it keeps into its own tables, and writes there alone
        self.env['OPENCODE_FIXTURE_VERSION'] = '2.0.28'
        os.utime(self.bin / 'opencode', ns=(1, 1))  # the update replaces the CLI
        with self.connect() as db:
            db.execute('INSERT INTO session_v2 (id, project_id, slug, directory, title, version, time_created, '
                       'time_updated) VALUES (?,?,?,?,?,?,?,?)',
                       (old, 'global', old, str(self.project), 'Before the upgrade', '1.19.0', 1, 1791473123001))
            self.items_message(db, old, 'migrated', 'user', 1, [{'type': 'text', 'text': 'Migrated prompt'}])
        new = self.session('After the upgrade')
        self.part(new, 'user', {'type': 'text', 'text': 'New prompt'})
        calls = len(self.calls())
        rows, status, _ = self.worker()
        self.assertEqual((status, sorted(r['title'] for r in rows)), (0, ['After the upgrade', 'Before the upgrade']))
        self.assertEqual(self.calls()[calls:calls + 2], ['--version', 'debug paths'])
        self.assertIn('Migrated prompt', self.snapshot(old).read_text())
        self.assertFalse(self.snapshot(stale).exists())

    def test_debug_paths_lines_and_an_unreadable_version(self):
        sid = self.session('Paths')
        self.part(sid, 'user', {'type': 'text', 'text': 'Prompt'})
        spaced = self.home / "data folder café ' with spaces" / 'opencode.db'
        spaced.parent.mkdir()
        self.db.rename(spaced)
        self.db = spaced
        self.env['OPENCODE_FIXTURE_DB'] = str(spaced)
        for paths in ('', 'crlf', 'tab'):
            with self.subTest(paths=paths):
                self.forget_state()
                self.env['OPENCODE_FIXTURE_PATHS'] = paths
                rows, status, _ = self.worker()
                self.assertEqual((status, [r['title'] for r in rows]), (0, ['Paths']))
        self.forget_state()
        self.env['OPENCODE_FIXTURE_PATHS'] = 'missing'  # no line names the database
        self.assertEqual(self.worker()[1], 2)
        self.env.pop('OPENCODE_FIXTURE_PATHS')
        self.forget_state()
        self.env['OPENCODE_FIXTURE_VERSION'] = 'unknown'
        calls = len(self.calls())
        self.assertEqual(self.worker()[1], 2)
        self.assertEqual(self.calls()[calls:], ['--version'])

    def test_a_cli_changed_behind_an_unchanged_file_is_asked_again(self):
        # a script that runs another installation keeps its own stamp across an update
        self.env['OPENCODE_FIXTURE_VERSION'] = '1.19.0'
        OpenCodeDiscovery.session(self, 'Before the update')
        self.assertEqual(self.worker()[1], 0)
        self.env['OPENCODE_FIXTURE_VERSION'] = '2.0.28'
        self.session('After the update')  # a write: the cached rows cannot stand in for a query
        rows, status, _ = self.worker()
        self.assertEqual((status, [r['title'] for r in rows]), (2, ['Before the update']))
        calls = len(self.calls())
        rows, status, _ = self.worker()
        self.assertEqual((status, [r['title'] for r in rows]), (0, ['After the update']))
        self.assertEqual(self.calls()[calls:calls + 2], ['--version', 'debug paths'])

    def test_a_session_before_opencode_names_it(self):
        sid = self.session(None)
        self.part(sid, 'user', {'type': 'text', 'text': 'First prompt\nand more'})
        rows, status, _ = self.worker()
        self.assertEqual((status, rows[0]['title']), (0, 'First prompt'))
        self.set_session(sid, 'title', 'Named')
        self.assertEqual(self.worker()[0][0]['title'], 'Named')
        pasted = self.session(None)
        self.part(pasted, 'user', {'type': 'text', 'text': 'A pasted log ' + 'x' * 2000000})
        rows, status, _ = self.worker()
        self.assertEqual((status, [row['title'][:13] for row in rows]), (0, ['A pasted log ', 'Named']))
        self.assertLess(len(self.snapshot(pasted).read_text().splitlines()[0]), 2000)  # the title's start alone


@unittest.skipIf(BUN is None, 'no Bun runtime: neither OpenCode 2 nor bun is installed')
class OpenCode2RealReader(OpenCode2Discovery):
    """Rhun's reader run by a real Bun, as OpenCode 2's binary runs it, for the tests of what it returns"""
    CHOSEN = {'test_transcript_title_text_tools_errors_and_hidden_parts', 'test_bookkeeping_rows_and_opencode_2_tools',
              'test_undone_messages_are_left_out_until_redone', 'test_giant_parts_are_copied_with_their_start',
              'test_project_filter_subagents_archived_and_source_selection', 'test_empty_database_and_damaged_snapshot_rebuild',
              'test_unreadable_rows_are_left_out_of_the_transcript', 'test_transcript_past_a_pipe_buffer_arrives_whole',
              'test_models_in_the_row_and_where_replies_change', 'test_a_projects_bunfig_and_env_are_not_loaded',
              'test_reader_leaves_the_database_as_it_was', 'test_one_conversation_past_the_output_limit_keeps_its_title_alone',
              'test_a_query_failing_part_way_fails'}

    def setUp(self):
        if self._testMethodName not in self.CHOSEN: self.skipTest('the test reader covers it')
        super().setUp()
        self.env['OPENCODE_FIXTURE_BUN'] = BUN

    def read(self, sql, database=None, cwd=None):
        state = self.home / 'state/rhun'
        state.mkdir(parents=True, exist_ok=True)
        config = state / '.rhun-bunfig.toml'
        config.write_bytes(b'')
        return subprocess.run([BUN, f'--config={config}', '--no-env-file', '-e', reader(), str(database or self.db), sql],
                              cwd=cwd or state, env=dict(os.environ, BUN_BE_BUN='1', HOME=str(self.home)),
                              capture_output=True, timeout=30)

    def test_a_projects_bunfig_and_env_are_not_loaded(self):
        marker = self.home / 'preloaded'
        (self.project / 'preload.js').write_text(f'require("fs").writeFileSync({json.dumps(str(marker))}, "ran")\n')
        (self.project / 'bunfig.toml').write_text('preload = ["./preload.js"]\n')
        subprocess.run([BUN, '-e', '1'], cwd=self.project, env=dict(os.environ, BUN_BE_BUN='1'), timeout=30)
        self.assertTrue(marker.exists(), 'Bun started in the project runs its preload')
        marker.unlink()
        sid = self.session('Project with a bunfig')
        self.part(sid, 'user', {'type': 'text', 'text': 'Prompt'})
        rows, status, _ = self.worker(cwd=self.project)
        self.assertEqual((status, rows[0]['title']), (0, 'Project with a bunfig'))
        self.assertFalse(marker.exists())
        # nor if the reader ever started in the project: its config is Rhun's empty one
        result = self.read("SELECT 'x' AS line", cwd=self.project)
        self.assertEqual((result.returncode, result.stdout), (0, b'line\nx\n'), result.stderr)
        self.assertFalse(marker.exists())

    def test_a_query_failing_part_way_fails(self):
        query = "SELECT CASE WHEN value<3 THEN 'row ' || value ELSE json_extract('not JSON','$') END AS line FROM json_each('[1,2,3]')"
        result = self.read(query)
        self.assertNotEqual(result.returncode, 0)  # its exit fails it, whatever it printed first
        # the rows before the error with iterate(); none with the all() of a Bun without it
        self.assertIn(result.stdout, (b'line\nrow 1\nrow 2\n', b'line\n'))

    def test_reader_leaves_the_database_as_it_was(self):
        sid = self.session('Open')
        with self.connect() as db: db.execute('PRAGMA journal_mode=WAL').fetchall()
        def files():
            return {path.name: (path.stat().st_size, path.stat().st_mtime_ns)
                    for path in self.db.parent.iterdir() if path.name in
                    (self.db.name, self.db.name + '-wal', self.db.name + '-shm')}
        query = "SELECT json_object('id',id,'title',title) AS line FROM session_v2"
        expected = b'line\n{"id":"' + sid.encode() + b'","title":"Open"}\n'
        keeper = sqlite3.connect(self.db)  # OpenCode has the database open
        keeper.execute('SELECT count(*) FROM session_v2').fetchall()
        before = files()
        self.assertEqual(len(before), 3)
        result = self.read(query)
        self.assertEqual((result.returncode, result.stdout), (0, expected), result.stderr)
        self.assertEqual(files(), before)  # read-only: nothing written
        keeper.close()  # OpenCode closed: no -shm, so SQLite cannot read the log read-only
        before = files()
        self.assertEqual(list(before), [self.db.name])
        result = self.read(query)
        self.assertEqual((result.returncode, result.stdout), (0, expected), result.stderr)
        self.assertEqual(files(), before)
        self.assertEqual(self.read('SELECT 1 WHERE 0').stdout, b'line\n')
        missing = self.home / 'missing.db'
        self.assertNotEqual(self.read(query, missing).returncode, 0)
        self.assertFalse(missing.exists())  # never created


if __name__ == '__main__': unittest.main()
