#!/usr/bin/env python3
"""Extension capacity and shared scheduling, using small native peers when a compiler exists."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

host = __import__('ext-host')

NATIVE = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    char line[8192];
    unsigned long id = 1;
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("hello 1 format");
    while (fgets(line, sizeof line, stdin)) {
        if (!strncmp(line, "0 bye", 5)) break;
        if (!strncmp(line, "0 run ", 6)) {
            if (strstr(line, ".burst ")) {
                for (int i = 0; i < 1500; ++i)
                    printf("%lu status 4\nbusy", id++);
                printf("%lu status 4\ndone", id++);
            } else printf("%lu toast 5\nready", id++);
        } else if (strstr(line, " format ")) {
            unsigned long request = strtoul(line, NULL, 10);
            printf("ok %lu 2\n0\n", request);
        }
    }
    return 0;
}
'''
FALLBACK = '''import sys
next_id = 1
print('hello 1 format', flush=True)
for line in sys.stdin:
    if line.startswith('0 bye'):
        break
    if line.startswith('0 run '):
        if '.burst ' in line:
            for i in range(1500):
                sys.stdout.write(str(next_id) + ' status 4\\nbusy')
                next_id += 1
            sys.stdout.write(str(next_id) + ' status 4\\ndone')
            next_id += 1
        else:
            sys.stdout.write(str(next_id) + ' toast 5\\nready')
            next_id += 1
        sys.stdout.flush()
    elif ' format ' in line:
        print('ok ' + line.split()[0] + ' 2', flush=True)
        sys.stdout.write('0\\n')
        sys.stdout.flush()
'''


class Scheduling(host.Host):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory(prefix='rhun-scheduler-peer-')
        cls.binary = None
        compiler = next((shutil.which(x) for x in ('cc', 'clang', 'gcc') if shutil.which(x)), None)
        if compiler:
            source = Path(cls.fixture.name) / 'peer.c'
            source.write_text(NATIVE)
            cls.binary = source.with_suffix('.exe' if os.name == 'nt' else '')
            subprocess.run([compiler, '-std=c99', '-O2', '-Wall', '-Wextra', '-Werror', str(source),
                            '-o', str(cls.binary)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.fixture.cleanup()

    def extensions(self, count, startup=True, hello_delays=None):
        hello_delays = hello_delays or {}
        root = self.work / 'scheduling'
        for i in range(count):
            name = f'p{i:03}'
            folder = root / 'scheduling' / name
            folder.mkdir(parents=True)
            if self.binary and i not in hello_delays:
                target = folder / self.binary.name
                shutil.copy2(self.binary, target)
                runtime = ''.join(f'run.{platform} = {target.name}\n' for platform in
                                  ('linux-x86_64', 'linux-arm64', 'macos-arm64', 'windows-x64'))
            else:
                target = folder / 'main.py'
                delay = (f'import time\ntime.sleep({hello_delays[i]!r})\n'
                         if i in hello_delays else '')
                target.write_text(delay + FALLBACK)
                runtime = f'run = {target.name}\nruntime = python3\n'
            (folder / 'extension.ini').write_text(
                f'name = {name}\nowner = scheduling\ntitle = Peer {i}\nversion = 1\nprotocol = 1\n'
                f'{runtime}on = {"startup" if startup else "command"}\n'
                '[commands]\nping = Ping\nburst = Burst\n'
                '[needs]\ndocuments = write\n[provides]\nformat = *.go\n')
        return root

    def all_slots_can_run(self, count=None, hello_delays=None):
        if count is None:
            count = 128 if self.binary else 64
        root = self.extensions(count, hello_delays=hello_delays)
        # Startup is paced across frames; each peer must finish its own handshake before the snapshot.
        actions = [f'wait-ext scheduling/p{i:03} running' for i in range(count)]
        out = self.run_editor(exts=root, files=(), actions=actions + [
            'print-extensions', f'cmd scheduling/p{count - 1:03}.ping',
            'wait 600', 'print-toast'])
        rows = [x for x in out if x.startswith('scheduling/')]
        self.assertEqual(len(rows), count, out)
        self.assertTrue(all('state=running' in x for x in rows), rows)
        self.assertEqual(out[-1], 'toast=ready')

    def test_all_extension_slots_can_handshake_and_handle_commands(self):
        self.all_slots_can_run()

    def test_capacity_waits_for_a_delayed_first_handshake(self):
        self.all_slots_can_run(hello_delays={0: 3})

    def test_capacity_waits_for_a_delayed_last_handshake(self):
        last = (128 if self.binary else 64) - 1
        self.all_slots_can_run(hello_delays={last: 3})

    def test_capacity_rejects_a_missing_handshake(self):
        with self.assertRaisesRegex(AssertionError, 'no hello within 5 s'):
            self.all_slots_can_run(count=3, hello_delays={1: 60})

    @unittest.skipIf(os.name == 'nt', 'POSIX descriptor limits')
    def test_all_slots_run_with_inherited_descriptor_limit_of_256(self):
        import resource
        from unittest.mock import patch
        if self.binary is None:
            self.skipTest('128-peer descriptor test needs a native compiler')
        hard = resource.getrlimit(resource.RLIMIT_NOFILE)[1]
        if hard != resource.RLIM_INFINITY and hard < 512:
            self.skipTest('hard descriptor limit cannot support 128 peers')
        run = subprocess.run

        def limited_run(*args, **kwargs):
            kwargs['preexec_fn'] = lambda: resource.setrlimit(resource.RLIMIT_NOFILE, (256, hard))
            return run(*args, **kwargs)

        with patch.object(host.subprocess, 'run', limited_run):
            self.all_slots_can_run()

    def test_late_provider_can_serve_an_explicit_action(self):
        root = self.extensions(24)
        self.prefs_path = self.work / 'config/rhun/extensions.ini'
        self.prefs_path.write_text('[providers]\nformat.Go = scheduling/p023\n')
        out = self.run_editor(exts=root, files=('b.go',), actions=[
            'wait 900', 'cmd format_document', 'wait 600', 'print-toast', 'print-extensions'])
        self.assertFalse(any('Provider unavailable' in x for x in out), out)
        self.assertTrue(any('scheduling/p023 state=running' in x for x in out), out)

    def test_stop_before_first_activation_keeps_extension_stopped(self):
        out = self.run_editor(exts=self.extensions(1, startup=False), files=(), actions=[
            'ext-set scheduling/p000 stop', 'cmd scheduling/p000.ping', 'wait 600',
            'print-extensions', 'print-toast'])
        self.assertIn('state=stopped', out[0])
        self.assertNotIn('toast=ready', out)

    def test_stop_cancels_restart_queued_while_stopping(self):
        out = self.run_editor(exts=self.extensions(1), files=(), actions=[
            'wait 300', 'ext-set scheduling/p000 disabled 1',
            'ext-set scheduling/p000 disabled 0', 'ext-set scheduling/p000 stop',
            'wait 900', 'print-extensions', 'cmd scheduling/p000.ping',
            'wait 300', 'print-extensions', 'print-toast'])
        rows = [line for line in out if line.startswith('scheduling/p000 ')]
        self.assertEqual(len(rows), 2, out)
        self.assertTrue(all('state=stopped' in row for row in rows), out)
        self.assertNotIn('toast=ready', out)

    def test_shared_budget_yields_and_quiet_peer_and_input_progress(self):
        root = self.extensions(20)
        actions = ['wait 900'] + [f'cmd scheduling/p{i:03}.burst' for i in range(16)]
        # every burst finishing is the end state checked below; Windows pipes and process
        # switches move the same messages more slowly, so it gets longer to get there
        settle = 4000 if os.name == 'nt' else 1600
        # the ping's toast lasts 2.2 s, less than Windows' settle: it is looked for along the way
        actions += ['cmd scheduling/p019.ping', 'type ok']
        step = settle // 3
        for _ in range(3):
            actions += [f'wait {step}', 'print-toast']
        actions += [f'wait {settle - 3 * step}', 'print-doc', 'print-ext-budget', 'print-extensions']
        out = self.run_editor(exts=root, actions=actions)
        self.assertIn('toast=ready', out)
        self.assertIn('okhello world', out)
        budget = next(x for x in out if x.startswith('budget '))
        stats = dict(part.split('=') for part in budget.split()[1:])
        self.assertGreater(int(stats['yields']), 0, budget)
        self.assertGreater(int(stats['windows']), 1, budget)
        self.assertLessEqual(int(stats['max_messages']), 2000, budget)
        self.assertFalse(any('reason=flooding' in x for x in out), out)
        for i in range(16):
            row = next(x for x in out if x.startswith(f'scheduling/p{i:03} '))
            self.assertIn('status=done', row, out)
        self.assertLessEqual(int(stats['max_bytes']), 1048576 + 65536, budget)


for name in dir(host.Host):
    if name.startswith('test_'):
        setattr(Scheduling, name, None)

if __name__ == '__main__':
    unittest.main()
