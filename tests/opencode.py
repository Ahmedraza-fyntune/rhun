#!/usr/bin/env python3
"""OpenCode database discovery, streaming snapshots, paging and provider failures."""
import json
from contextlib import contextmanager
import os
from pathlib import Path
import sqlite3
import struct
import subprocess
import sys
import tempfile
import time
import unittest

import agents

EXE = agents.EXE


@unittest.skipIf(os.name == 'nt', 'the test CLI uses a Unix shebang; Windows needs opencode.exe')
class OpenCodeDiscovery(unittest.TestCase):
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
with open(os.environ['OPENCODE_FIXTURE_DB'] + '.calls', 'a') as log:
    log.write(' '.join([sys.argv[1], sys.argv[2].split()[0]]) + '\\n')
mode = os.environ.get('OPENCODE_FIXTURE_MODE', '')
if mode == 'fail': sys.exit(1)
if mode == 'invalid': print('not TSV'); sys.exit()
if mode == 'slow' and sys.argv[2].startswith('WITH'):
    import time; time.sleep(11)
if mode == 'hang':
    import subprocess, time
    child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
    with open(os.environ['OPENCODE_FIXTURE_DB'] + '.pids', 'a') as log:
        log.write(str(os.getpid()) + ' ' + str(child.pid) + '\\n')
    time.sleep(60)
if sys.argv[1:3] == ['db', 'path']:
    print(os.environ['OPENCODE_FIXTURE_DB']); sys.exit()
assert sys.argv[1] == 'db' and sys.argv[3:] == ['--format', 'tsv'], sys.argv
with open(os.environ['OPENCODE_FIXTURE_DB'] + '.queries', 'a') as log:
    log.write(sys.argv[2] + '\\n')
if os.environ.get('OPENCODE_FIXTURE_WAL'):
    # OpenCode checkpoints its log on every start, also for a read: the database file changes.
    db = sqlite3.connect('file:' + os.environ['OPENCODE_FIXTURE_DB'] + '?mode=rw', uri=True)
    db.execute('PRAGMA wal_checkpoint(PASSIVE)').fetchall()
    os.utime(os.environ['OPENCODE_FIXTURE_DB'])
else:
    db = sqlite3.connect('file:' + os.environ['OPENCODE_FIXTURE_DB'] + '?mode=ro', uri=True)
rows = db.execute(sys.argv[2]).fetchall()
out = ''.join(['line\\n'] + [row[0] + '\\n' for row in rows]).encode() if rows else b''
import stat
if stat.S_ISFIFO(os.fstat(1).st_mode):
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

    def worker(self, limit=50, sources='opencode', opened=None, project=None, timeout=20):
        args = [str(EXE), '--agent-index', str(project or self.project), str(limit), sources]
        if opened is not None: args.append(opened)
        result = subprocess.run(args, env=self.env, capture_output=True, timeout=timeout)
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
        with self.connect() as db:
            db.execute('UPDATE session SET title=? WHERE id=?', ('New title', sid))
            db.execute('DELETE FROM part WHERE session_id=? AND message_id LIKE ?', (sid, '%assistant'))
        self.assertEqual(self.editor(['print-agents 1']),
                         'OpenCode: New title\nuser Fix the code\n')
        with self.connect() as db: db.execute('DELETE FROM session WHERE id=?', (sid,))
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
            with self.connect() as db: db.execute('UPDATE session SET time_updated=time_updated+1')
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
        with self.connect() as db:
            db.execute('INSERT INTO message VALUES (?,?,?,?,?)', (sid + '_error', sid, 2, 3,
                       json.dumps({'role': 'assistant', 'error': {
                           'name': 'APIError', 'data': {'message': 'Local model server unavailable'}}})))
        self.assertEqual(self.editor(['print-agents 1']),
                         'OpenCode: Failed request\nuser Try the local model\n'
                         'result Local model server unavailable\n')

    def test_unchanged_database_is_not_queried_again(self):
        sid = self.session('Quiet')
        self.part(sid, 'user', {'type': 'text', 'text': 'Prompt'})
        self.worker()
        self.assertEqual(self.calls(), ['db path', 'db SELECT', 'db WITH'])
        self.worker()
        rows, status, total = self.worker()
        self.assertEqual((status, total, rows[0]['title']), (0, 1, 'Quiet'))
        self.assertEqual(len(self.calls()), 3)
        self.part(sid, 'assistant', {'type': 'text', 'text': 'Reply'}, 1)
        rows, _, _ = self.worker()
        self.assertEqual(self.calls()[3:], ['db SELECT', 'db WITH'])  # the path is kept
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
            self.assertEqual(self.calls()[calls:calls + 2], ['db SELECT', 'db WITH'])
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
        self.assertEqual(self.calls().count('db path'), 3)
        self.assertEqual(self.calls().count('db SELECT'), 3)

    def test_unchanged_database_is_queried_again_after_five_minutes(self):
        self.session('Old')
        self.worker()
        state = next((self.home / 'state/rhun').glob('agents-index-v5-*-opencode'))
        data = bytearray(state.read_bytes())
        struct.pack_into('<q', data, 32, struct.unpack_from('<q', data, 32)[0] - 301)
        state.write_bytes(bytes(data))
        self.worker()
        self.worker()
        self.assertEqual(self.calls().count('db SELECT'), 2)

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
        with self.connect() as db:
            db.execute('DELETE FROM part WHERE session_id=?', (gone,))
            db.execute('DELETE FROM session WHERE id=?', (gone,))
            db.execute('UPDATE session SET time_archived=1 WHERE id=?', (hidden,))
        rows, _, _ = self.worker()
        self.assertEqual([r['title'] for r in rows], ['Keep'])
        self.assertEqual([self.snapshot(sid).exists() for sid in (keep, gone, hidden)], [True, False, False])

    def test_unreadable_rows_are_left_out_of_the_transcript(self):
        sid = self.session('Damaged rows')
        self.part(sid, 'user', {'type': 'text', 'text': 'Readable prompt'})
        with self.connect() as db:
            db.execute('INSERT INTO part VALUES (?,?,?,?,?,?)',
                       ('bad', sid + '_user', sid, 1, 1, 'not JSON {'))
            db.execute('INSERT INTO message VALUES (?,?,?,?,?)', (sid + '_bad', sid, 3, 3, '{broken'))
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
        self.assertEqual(self.calls().count('db WITH'), 2)  # 8 MB a query
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
        self.assertEqual(self.calls().count('db WITH'), 1)
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

    def test_damaged_state_file_asks_the_cli_again(self):
        self.session('State')
        self.worker()
        state = next((self.home / 'state/rhun').glob('agents-index-v5-*-opencode'))
        for damage in (b'', b'RAHOCST1', state.read_bytes()[:40] + b'', b'x' * 60):
            state.write_bytes(damage)
            before = self.calls().count('db path')
            rows, status, _ = self.worker()
            self.assertEqual((status, [r['title'] for r in rows]), (0, ['State']))
            self.assertEqual(self.calls().count('db path'), before + 1)

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
        self.assertEqual(self.calls().count('db WITH'), 3)
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
        with self.connect() as db:
            # message IDs that do not sort by time: OpenCode orders by time, then ID
            for mid, role, when, text in (('m9', 'user', 1, 'First prompt'), ('m8', 'assistant', 2, 'First reply'),
                                          ('m7', 'user', 3, 'Second prompt'), ('m6', 'assistant', 4, 'Second reply')):
                db.execute('INSERT INTO message VALUES (?,?,?,?,?)', (mid, sid, when, when, json.dumps({'role': role})))
                db.execute('INSERT INTO part VALUES (?,?,?,?,?,?)', ('p' + mid, mid, sid, when, when,
                           json.dumps({'type': 'text', 'text': text}, separators=(',', ':'))))
        full = 'OpenCode: Undo\nuser First prompt\nagent First reply\nuser Second prompt\nagent Second reply\n'
        self.assertEqual(self.editor(['print-agents 1']), full)
        with self.connect() as db:  # /undo: the rows stay, session.revert marks where the conversation ends
            db.execute('UPDATE session SET revert=? WHERE id=?', (json.dumps({'messageID': 'm7'}), sid))
        self.assertEqual(self.editor(['print-agents 1']), 'OpenCode: Undo\nuser First prompt\nagent First reply\n')
        with self.connect() as db:  # /redo
            db.execute('UPDATE session SET revert=NULL WHERE id=?', (sid,))
        self.assertEqual(self.editor(['print-agents 1']), full)

    def test_undone_tail_does_not_count_toward_the_size_limit(self):
        sid = self.session('Undone tail')
        with self.connect() as db:
            for mid, role, when, text in (('a1', 'user', 1, 'Short prompt'), ('a2', 'assistant', 2, 'Short reply'),
                                          ('a3', 'user', 3, 'Big request')):
                db.execute('INSERT INTO message VALUES (?,?,?,?,?)', (mid, sid, when, when, json.dumps({'role': role})))
                db.execute('INSERT INTO part VALUES (?,?,?,?,?,?)', ('p' + mid, mid, sid, when, when,
                           json.dumps({'type': 'text', 'text': text}, separators=(',', ':'))))
            db.execute('INSERT INTO message VALUES (?,?,?,?,?)', ('a4', sid, 4, 4, json.dumps({'role': 'assistant'})))
            db.executemany('INSERT INTO part VALUES (?,?,?,?,?,?)', [
                (f'q{index:04}', 'a4', sid, 4, 4, json.dumps({'type': 'text', 'text': 'u' * 66000}, separators=(',', ':')))
                for index in range(400)])  # 26 MB, past the limit
            db.execute('UPDATE session SET revert=? WHERE id=?', (json.dumps({'messageID': 'a3'}), sid))
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
        with self.connect() as db: db.execute('UPDATE session SET title=? WHERE id=?', ('Unsaved again', sid))
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
        with self.connect() as db: db.execute('UPDATE session SET title=? WHERE id=?', ('Changed', sid))
        before = self.calls().count('db WITH')
        rows, status, _ = self.worker(timeout=60)
        self.assertEqual(status, 2)
        self.assertEqual(self.calls().count('db WITH'), before + 1)

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


if __name__ == '__main__': unittest.main()
