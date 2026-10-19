#!/usr/bin/env python3
"""Native workspace watcher negotiation, sharing and runtime ownership."""
import json
import unittest

host = __import__('ext-host')

PROGRAM = r'''import os
import sys
from pathlib import Path

log = Path(os.environ['RHUN_STATE']) / 'watch.log'
project = Path(os.environ['RHUN_PROJECT'])
handle = 0
next_id = 1
pending = {}
def record(text):
    with log.open('a') as f:
        f.write(text + '\n')
def request(verb):
    global next_id
    pending[next_id] = verb.split()[0]
    print(str(next_id) + ' ' + verb, flush=True)
    next_id += 1
record('START')
print(HELLO, flush=True)
for line in sys.stdin:
    line = line.rstrip('\n')
    record(line)
    fields = line.split()
    if fields[:2] == ['0', 'bye']:
        break
    if fields[:2] == ['0', 'ready']:
        request('watch-workspace')
    elif fields[:1] == ['ok'] and len(fields) > 2:
        if pending.get(int(fields[1])) == 'watch-workspace':
            handle = int(fields[2])
    elif fields[:2] == ['0', 'run']:
        name = fields[2].split('.')[-1]
        if name == 'watch':
            request('watch-workspace')
        elif name == 'unwatch':
            request('unwatch-workspace ' + str(handle))
        elif name == 'steal':
            request('unwatch-workspace ' + ('1' if handle != 1 else '2'))
        elif name == 'mutate':
            record('MARK mutate')
            target = project / '.hidden' / 'nested' / 'changed.go'
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(target.read_text() + 'x' if target.exists() else 'x')
'''


class Watches(host.Host):
    def extensions(self, owners=('a',), feature=True, permission=True):
        root = self.work / 'watchers'
        for owner in owners:
            folder = root / owner / 'watcher'
            folder.mkdir(parents=True, exist_ok=True)
            manifest = (f'name = watcher\nowner = {owner}\ntitle = Watcher\nversion = 1\n'
                        'protocol = 1\nruntime = python3\nrun = main.py\non = startup\n'
                        '[commands]\nwatch = Watch\nunwatch = Unwatch\nsteal = Steal\nmutate = Mutate\n')
            if permission:
                manifest += '[needs]\nproject = write\n'
            (self.work / f'state/rhun/extensions/{owner}--watcher/watch.log').unlink(missing_ok=True)
            (folder / 'extension.ini').write_text(manifest)
            hello = 'hello 1 workspace_watch' if feature else 'hello 1'
            (folder / 'main.py').write_text('HELLO = ' + json.dumps(hello) + '\n' + PROGRAM)
        # Existing hidden directories must be enrolled independently of explorer visibility.
        (self.proj / '.hidden' / 'nested').mkdir(parents=True, exist_ok=True)
        return root

    def watch_log(self, owner='a'):
        return (self.work / f'state/rhun/extensions/{owner}--watcher/watch.log').read_text().splitlines()

    def test_negotiation_and_permission_are_required(self):
        for feature, permission in ((False, True), (True, False)):
            with self.subTest(feature=feature, permission=permission):
                self.run_editor(['wait 300'], exts=self.extensions(feature=feature, permission=permission), drop_waits=True)
                code = 'unknown' if not feature else 'needs'
                self.assertTrue(any(line.startswith('error 1 ' + code + ' ') for line in self.watch_log()), self.watch_log())

    def test_subscription_is_idempotent_and_covers_hidden_descendants(self):
        self.run_editor(['wait 500', 'cmd a/watcher.watch', 'wait 200',
                         'cmd a/watcher.mutate', 'wait 500'], exts=self.extensions(), drop_waits=True)
        log = self.watch_log()
        handles = [line.split()[2] for line in log if line.startswith('ok ') and len(line.split()) == 3]
        self.assertEqual(handles, ['1', '1'], log)
        marker = log.index('MARK mutate')
        self.assertTrue(any(line == '0 watch 1 changed' for line in log[marker + 1:]), log)

    def test_one_extension_cannot_remove_another_subscription(self):
        self.run_editor(['wait 500', 'cmd b/watcher.steal', 'wait 200',
                         'cmd a/watcher.mutate', 'wait 500'], exts=self.extensions(('a', 'b')), drop_waits=True)
        self.assertIn('error 2 unknown workspace watch', self.watch_log('b'))
        for owner in ('a', 'b'):
            log = self.watch_log(owner)
            self.assertTrue(any(line.endswith(' changed') and line.startswith('0 watch ') for line in log), log)

    def test_unsubscribe_removes_only_the_owners_listener(self):
        self.run_editor(['wait 500', 'cmd a/watcher.unwatch', 'wait 200',
                         'cmd b/watcher.mutate', 'wait 500'], exts=self.extensions(('a', 'b')), drop_waits=True)
        log = self.watch_log('a')
        acknowledged = log.index('ok 2')
        self.assertFalse(any(line.startswith('0 watch ') for line in log[acknowledged + 1:]), log)
        self.assertTrue(any(line.endswith(' changed') for line in self.watch_log('b')), self.watch_log('b'))

    def test_restart_retires_old_handle(self):
        self.run_editor(['wait 400', 'ext-set a/watcher stop', 'wait 300', 'ext-set a/watcher restart', 'wait 600',
                         'cmd a/watcher.mutate', 'wait 500'], exts=self.extensions(), drop_waits=True)
        log = self.watch_log()
        starts = [i for i, line in enumerate(log) if line == 'START']
        self.assertEqual(len(starts), 2, log)
        self.assertIn('ok 1 2', log[starts[1]:])
        self.assertFalse(any(line.startswith('0 watch 1 ') for line in log[starts[1]:]), log)


    def test_periodic_reconciliation_recovers_backend_loss(self):
        self.run_editor(['wait 2300'], exts=self.extensions(), drop_waits=True)
        rescans = [line for line in self.watch_log() if line == '0 watch 1 rescan']
        self.assertGreaterEqual(len(rescans), 2, self.watch_log())

    def test_project_switch_retires_every_old_handle(self):
        other = self.work / 'next'
        other.mkdir()
        self.run_editor(['wait 400', 'cmd open_folder', 'key ctrl+a',
                         'type ' + other.as_posix(), 'key ctrl+Return', 'wait 900',
                         'cmd a/watcher.mutate', 'wait 500'], exts=self.extensions(), drop_waits=True)
        log = self.watch_log()
        starts = [i for i, line in enumerate(log) if line == 'START']
        self.assertEqual(len(starts), 2, log)
        self.assertIn('ok 1 2', log[starts[1]:])
        self.assertFalse(any(line.startswith('0 watch 1 ') for line in log[starts[1]:]), log)


def load_tests(loader, tests, pattern):
    return unittest.TestSuite(Watches(name) for name in Watches.__dict__ if name.startswith('test_'))


if __name__ == '__main__':
    unittest.main()
