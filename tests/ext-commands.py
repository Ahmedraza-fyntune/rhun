#!/usr/bin/env python3
"""Command identity and lifecycle across independently published extensions."""
import json
import unittest

host = __import__('ext-host')

PROGRAM = '''import os
import sys
from pathlib import Path

owner = os.environ['RHUN_EXTENSION'].split('/')[0]
log = Path(os.environ['RHUN_STATE']) / 'commands.log'
next_id = 1
def request(text, body=''):
    global next_id
    sys.stdout.write(str(next_id) + ' ' + text + '\\n' + body)
    sys.stdout.flush()
    next_id += 1
print(HELLO, flush=True)
for line in sys.stdin:
    with log.open('a') as f:
        f.write(line)
    if line.startswith('0 bye'):
        break
    if not line.startswith('0 run '):
        continue
    name = line.split()[2].split('.', 1)[1]
    if name == 'register':
        request('register extra ctrl+alt+9 Extra')
        request('register other ctrl+alt+8 Other')
    elif name == 'remove':
        request('unregister extra')
    elif name == 'manifest':
        request('unregister ping')
    elif name == 'missing':
        request('unregister missing')
    elif name == 'ping' or name == 'extra' or name == 'other':
        text = owner + ':' + name
        request('toast ' + str(len(text)), text)
'''


class Commands(host.Host):
    def extensions(self, owners=('alice', 'bob'), features=True):
        root = self.work / 'commands'
        for owner in owners:
            folder = root / owner / 'demo'
            folder.mkdir(parents=True)
            (folder / 'extension.ini').write_text(
                f'name = demo\nowner = {owner}\ntitle = Demo\nversion = 1\nprotocol = 1\n'
                'runtime = python3\nrun = main.py\non = command\n[commands]\n'
                'ping = Ping\nregister = Register\nremove = Remove\nmanifest = Manifest\nmissing = Missing\n')
            hello = 'hello 1 commands' if features else 'hello 1'
            (folder / 'main.py').write_text('HELLO = ' + json.dumps(hello) + '\n' + PROGRAM)
        return root

    def command_log(self, owner):
        return (self.work / f'state/rhun/extensions/{owner}--demo/commands.log').read_text()

    def test_qualified_commands_route_to_their_owner(self):
        out = self.run_editor(exts=self.extensions(), drop_waits=True, actions=[
            'cmd alice/demo.ping', 'wait 300', 'wait 300', 'print-toast',
            'cmd bob/demo.ping', 'wait 300', 'wait 300', 'print-toast'])
        self.assertEqual(out, ['toast=alice:ping', 'toast=bob:ping'])
        self.assertIn('0 run demo.ping 1', self.command_log('alice'))
        self.assertIn('0 run demo.ping 1', self.command_log('bob'))

    def test_ambiguous_short_commands_do_not_start_either_extension(self):
        out = self.run_editor(exts=self.extensions(), drop_waits=True, actions=[
            'cmd demo.ping', 'wait 300', 'print-extensions'])
        self.assertEqual(len(out), 2)
        self.assertTrue(all('state=idle' in line for line in out), out)

    def test_ambiguous_short_extension_name_does_not_disable_either(self):
        out = self.run_editor(exts=self.extensions(), drop_waits=True, actions=[
            'ext-set demo disabled 1', 'print-extensions',
            'ext-set alice/demo disabled 1', 'print-extensions'])
        self.assertTrue(all('state=idle' in line for line in out[:2]), out)
        self.assertTrue(any('alice/demo state=disabled' in line for line in out[2:]), out)
        self.assertTrue(any('bob/demo state=idle' in line for line in out[2:]), out)

    def test_unique_legacy_alias_still_runs(self):
        out = self.run_editor(exts=self.extensions(('alice',)), drop_waits=True, actions=[
            'cmd demo.ping', 'wait 300', 'wait 300', 'print-toast'])
        self.assertEqual(out, ['toast=alice:ping'])

    def test_exact_qualified_palette_query_selects_only_its_owner(self):
        out = self.run_editor(exts=self.extensions(('a', 'ba')), drop_waits=True, actions=[
            'cmd command_palette', 'type a/demo.ping', 'print-palette',
            'key Return', 'wait 300', 'wait 300', 'print-toast'])
        rows = [line for line in out if 'Ping (Demo)' in line]
        self.assertEqual(len(rows), 1, out)
        self.assertEqual(out[-1], 'toast=a:ping')

    def test_qualified_user_keybinding_selects_its_owner(self):
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[keys]\nctrl+alt+7 = alice/demo.ping\n')
        out = self.run_editor(exts=self.extensions(), drop_waits=True, actions=[
            'key ctrl+alt+7', 'wait 300', 'wait 300', 'print-toast'])
        self.assertEqual(out, ['toast=alice:ping'])

    def test_runtime_registration_is_scoped_to_its_owner(self):
        out = self.run_editor(exts=self.extensions(), drop_waits=True, actions=[
            'cmd alice/demo.register', 'wait 300', 'wait 300',
            'cmd bob/demo.register', 'wait 300', 'wait 300',
            'cmd alice/demo.extra', 'wait 300', 'print-toast',
            'cmd bob/demo.extra', 'wait 300', 'print-toast'])
        self.assertEqual(out, ['toast=alice:extra', 'toast=bob:extra'])

    def test_unregister_removes_only_own_runtime_command_and_shortcut(self):
        out = self.run_editor(exts=self.extensions(('alice',)), drop_waits=True, actions=[
            'cmd demo.register', 'wait 300', 'wait 300',
            'cmd demo.remove', 'wait 300', 'print-extensions',
            'key ctrl+alt+9', 'wait 300', 'print-toast',
            'key ctrl+alt+8', 'wait 300', 'print-toast',
            'cmd demo.register', 'wait 300', 'key ctrl+alt+9', 'wait 300', 'print-toast'])
        self.assertNotIn('demo.extra', out[0])
        self.assertIn('demo.other', out[0])
        self.assertEqual(out[1:], ['toast=', 'toast=alice:other', 'toast=alice:extra'])

    def test_disabled_owner_keeps_runtime_alias_ambiguous(self):
        out = self.run_editor(exts=self.extensions(), drop_waits=True, actions=[
            'cmd alice/demo.register', 'wait 300', 'wait 300',
            'cmd bob/demo.register', 'wait 300', 'wait 300',
            'cmd bob/demo.other', 'wait 300',
            'ext-set alice/demo disabled 1', 'wait 500',
            'cmd demo.extra', 'wait 300', 'print-toast',
            'cmd bob/demo.extra', 'wait 300', 'print-toast'])
        self.assertEqual(out, ['toast=bob:other', 'toast=bob:extra'])

    def test_one_runtime_command_is_not_a_unique_extension_alias(self):
        out = self.run_editor(exts=self.extensions(), drop_waits=True, actions=[
            'cmd alice/demo.register', 'wait 300', 'wait 300',
            'cmd demo.extra', 'wait 300', 'print-toast',
            'cmd alice/demo.extra', 'wait 300', 'print-toast'])
        self.assertEqual(out, ['toast=', 'toast=alice:extra'])

    def test_unnegotiated_unregister_leaves_runtime_command_and_key(self):
        out = self.run_editor(exts=self.extensions(('alice',), features=False), drop_waits=True, actions=[
            'cmd demo.register', 'wait 300', 'wait 300',
            'cmd demo.remove', 'wait 300', 'key ctrl+alt+9', 'wait 300', 'print-toast'])
        self.assertEqual(out, ['toast=alice:extra'])
        self.assertIn('error 3 unknown', self.command_log('alice'))

    def test_manifest_and_missing_commands_cannot_be_unregistered(self):
        out = self.run_editor(exts=self.extensions(('alice',)), drop_waits=True, actions=[
            'cmd demo.manifest', 'wait 300', 'wait 300',
            'cmd demo.missing', 'wait 300', 'cmd demo.ping', 'wait 300', 'print-toast'])
        self.assertEqual(out, ['toast=alice:ping'])
        self.assertIn('error 1 refused', self.command_log('alice'))
        self.assertIn('error 2 refused', self.command_log('alice'))


for name in dir(host.Host):
    if name.startswith('test_'):
        setattr(Commands, name, None)

if __name__ == '__main__':
    unittest.main()
