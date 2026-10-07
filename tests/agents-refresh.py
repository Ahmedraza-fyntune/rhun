#!/usr/bin/env python3
"""Routine agent discovery runs quietly: the panel shows its loading state only for a run the user
asked for, a file saved in the folder runs no discovery, and of a repository's activity only a
worktree registered does."""
import glob
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()


@unittest.skipIf(os.name == 'nt', 'the control socket is Unix only')
class AgentsRefresh(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-agents-refresh-')
        self.work = Path(self.tmp.name).resolve()
        self.project = self.work / 'project'
        self.project.mkdir()
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n'
                          '[editor]\ncursor_blink = false\n[ui]\nsidebar = false\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'), GIT_CONFIG_NOSYSTEM='1')
        # a Claude session of the project, so the panel lists a row
        slug = re.sub(r'[^A-Za-z0-9]', '-', self.project.as_posix())
        sessions = self.work / '.claude/projects' / slug
        sessions.mkdir(parents=True)
        self.session = sessions / 's1.jsonl'
        fixture = (ROOT / 'tests/data/agents/claude.jsonl').read_text(encoding='utf-8')
        self.session.write_text(fixture.replace('@PROJECT@', self.project.as_posix()), encoding='utf-8')
        self.process = self.client = self.reader = None

    def tearDown(self):
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=10)
        for closable in (self.reader, self.client):
            if closable is not None:
                closable.close()
        if self.process is not None:
            self.process.stderr.close()
        self.tmp.cleanup()

    def start(self):
        control = self.work / 'control'
        self.process = subprocess.Popen([str(EXE), str(self.project), '--headless', '1280x800',
                                         '--scale', '1', '--control', str(control)], env=self.env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.client.settimeout(15)
        deadline = time.monotonic() + 10
        while True:
            try:
                self.client.connect(str(control))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if self.process.poll() is not None or time.monotonic() > deadline:
                    self.fail('editor did not start')
                time.sleep(0.01)
        self.reader = self.client.makefile('r', encoding='utf-8')
        self.command('cmd focus_agents')
        self.command('wait-agents')
        # macOS can report the session file this test wrote before rhun started once rhun watches its
        # folder (after the first page): one more refresh, 150 ms later. Let it run before measuring.
        self.command('wait 600')
        self.command('wait-agents')
        self.assertEqual(self.command('print-agents-page'), 'shown=1 total=1 loading=0 error=0\n')

    def command(self, line):
        self.client.sendall((line + '\n').encode('utf-8'))
        output = []
        while True:
            reply = self.reader.readline()
            if reply == 'ok\n':
                return ''.join(output)
            self.assertNotIn(reply, ('', 'error\n'), line)
            output.append(reply)

    def runs(self):
        """Discovery runs started so far."""
        reply = self.command('print-agents-runs')
        self.assertTrue(reply.startswith('runs='), reply)
        return int(reply[5:])

    def cache(self):
        """The index worker writes its cache anew when it changed: another inode, a later time."""
        files = glob.glob(str(self.work / 'state/rhun/agents-index-v5-*'))
        self.assertEqual(len(files), 1, files)
        stat = os.stat(files[0])
        return stat.st_ino, stat.st_mtime_ns

    def test_a_routine_refresh_keeps_the_panel_quiet(self):
        self.start()
        before = self.cache()
        # the session gains a custom title: the poll sees the write and discovery runs again
        with self.session.open('ab') as stream:
            stream.write(json.dumps({'type': 'custom-title', 'customTitle': 'Renamed quietly',
                                     'sessionId': 's1'}).encode('utf-8') + b'\n')
        later = time.time_ns() + 60 * 10**9
        os.utime(self.session, ns=(later, later))
        samples = 0
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            # back to back, without waits: the loop still runs its timers between the lines
            page = self.command('print-agents-page')
            samples += 1
            self.assertNotIn('loading=1', page, f'the panel showed loading on sample {samples}')
            if samples % 100 == 0 and 'Renamed quietly' in self.command('print-agents'):
                break
        else:
            self.fail('the session kept its old title: discovery did not run again')
        self.assertEqual(self.command('print-agents-page'), 'shown=1 total=1 loading=0 error=0\n')
        self.assertNotEqual(self.cache(), before, 'the refresh did not write the index')

    def test_a_requested_refresh_shows_loading(self):
        # hidden, the panel keeps a requested run pending, and shows it as loading once it is open
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text(encoding='utf-8') + 'agents_panel = false\n', encoding='utf-8')
        control = self.work / 'control'
        self.process = subprocess.Popen([str(EXE), str(self.project), '--headless', '1280x800',
                                         '--scale', '1', '--control', str(control)], env=self.env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.client.settimeout(15)
        deadline = time.monotonic() + 10
        while True:
            try:
                self.client.connect(str(control))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if self.process.poll() is not None or time.monotonic() > deadline:
                    self.fail('editor did not start')
                time.sleep(0.01)
        self.reader = self.client.makefile('r', encoding='utf-8')
        self.command('wait 300')
        self.assertEqual(self.command('print-agents-page'), 'shown=0 total=0 loading=1 error=0\n')
        self.command('cmd toggle_agents')
        self.command('wait-agents')
        self.assertEqual(self.command('print-agents-page'), 'shown=1 total=1 loading=0 error=0\n')

    def test_saving_in_a_plain_folder_runs_no_discovery(self):
        self.start()
        before = self.runs()
        (self.project / 'note.txt').write_text('saved\n', encoding='utf-8')
        self.command('wait 1500')
        self.assertEqual(self.runs(), before, 'a file saved in the folder ran discovery again')

    def test_a_worktree_registered_runs_discovery_again_other_git_activity_does_not(self):
        # worktree registrations live under .git: one added is followed, the first (which creates
        # .git/worktrees) and the next (inside it); the rest of Git's activity there changes no session.
        # Each must come well before the routine run, 10 s after the last.
        def git(*args):
            subprocess.run(['git', '-C', str(self.project), '-c', 'user.name=t', '-c', 'user.email=t@t',
                            *args], env=self.env, check=True, capture_output=True)
        subprocess.run(['git', 'init', '-q', '-b', 'main', str(self.project)], env=self.env, check=True)
        git('commit', '-q', '--allow-empty', '-m', 'start')
        self.start()
        before = self.runs()
        (self.project / '.git/rhun-probe').write_text('not a registration\n', encoding='utf-8')
        self.command('wait 1500')
        self.assertEqual(self.runs(), before, 'a change under .git that registers nothing ran discovery')
        for name in ('first', 'second'):
            git('worktree', 'add', '-q', str(self.work / name))
            deadline = time.monotonic() + 6
            while self.runs() == before and time.monotonic() < deadline:
                self.command('wait 100')
            self.assertGreater(self.runs(), before, f'the {name} worktree did not run discovery')
            self.command('wait-agents')
            before = self.runs()


if __name__ == '__main__':
    unittest.main(verbosity=2)
