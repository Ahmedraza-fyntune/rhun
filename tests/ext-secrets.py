#!/usr/bin/env python3
"""Extension secrets (resources group): secret-get/set/delete/keys on the memory and file stores,
the limits, needs and feature checks, the page's keys with Forget, removal, and the system store
where one is reachable: the macOS login keychain (a service of the test's own, cleaned up), the
Linux Secret Service (gnome-keyring under dbus-run-session) and its absence (memory and a toast).
The fake extension is tests/ext/res.py; RES_ARGS feeds its request command."""
import os
from pathlib import Path
import re
import secrets as pysecrets
import shutil
import stat
import subprocess
import sys
import unittest

host = __import__('ext-host')
lifecycle = __import__('ext-lifecycle')


class Secrets(lifecycle.Base):
    def setUp(self):
        super().setUp()
        # in the extension's state folder: the only place a confined extension may read and write
        self.args = self.work / 'state/rhun/extensions/rt--res/args.txt'
        self.args.parent.mkdir(parents=True)
        self.env['RES_ARGS'] = self.args.as_posix()

    def root(self, needs='secrets = yes\n', features='secrets'):
        root = self.work / 'exts'
        folder = root / 'rt' / 'res'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'extension.ini').write_text(
            'name = res\nowner = rt\ntitle = Res\nversion = 1\nprotocol = 1\n'
            f'runtime = python3\nrun = {lifecycle.RES.as_posix()}\non = command\n'
            '[commands]\nrequest = Request\nbatch = Batch\nping = Ping\n'
            f'[needs]\nrun = python3\n{needs}', encoding='utf-8')
        self.env['RES_FEATURES'] = features
        self.reslog = self.work / 'state/rhun/extensions/rt--res/res.log'
        self.env['RES_LOG'] = self.reslog.as_posix()
        return root

    def requests(self, *lines, extra=(), backend='memory', root=None, batch=False):
        """Each line is a request for res.py; returns rhun's output and res.py's log."""
        root = root or self.root()
        self.args.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        if self.reslog.exists():
            self.reslog.unlink()
        actions = []
        if backend:
            actions.append('secret-backend ' + backend)
        if batch:
            actions += ['cmd rt/res.batch', 'wait-ext res running', 'wait 1500']
        for _ in ([] if batch else lines):
            actions += ['cmd rt/res.request', 'wait-ext res running', 'wait 150']
        out = self.run_editor([*actions, *extra], exts=root, files=())
        log = self.reslog.read_text(errors='replace').splitlines() if self.reslog.exists() else []
        return out, log

    def answers(self, log):
        return [x for x in log if x.startswith(('ok ', 'error ', 'body '))]

    def test_memory_store_round_trip(self):
        out, log = self.requests('secret-set token {LEN}|abc def', 'secret-get token',
                                 'secret-get missing', 'secret-set other {LEN}|', 'secret-keys',
                                 'secret-delete token', 'secret-keys', 'secret-delete never',
                                 extra=['secrets-refresh rt/res', 'wait 100', 'print-secrets rt/res'])
        self.assertEqual(self.answers(log), [
            'ok 1', 'ok 2 1 7', 'body abc def', 'ok 3 0 0', 'ok 4', 'ok 5 12',
            'body token', 'ok 6', 'ok 7 6', 'body other', 'ok 8'], log)
        self.assertIn('backend=memory keys=other', out)

    def test_limits_and_checks(self):
        # three unparsable requests in a row would end the program: valid ones go between
        lines = ['secret-get Bad', 'secret-get fine', 'secret-get ' + 'k' * 65, 'secret-get fine',
                 'secret-get a b', 'secret-set big {LEN}|' + 'x' * 8193, 'secret-set ok8192 {LEN}|' + 'y' * 8192]
        lines += [f'secret-set k{i} 1|v' for i in range(63)]
        lines += ['secret-set k63 1|v', 'secret-set one-more 1|v', 'secret-set k1 2|vv']
        out, log = self.requests(*lines, batch=True)
        a = {int(x.split()[1]): x for x in self.answers(log) if not x.startswith('body')}
        self.assertTrue(a[1].startswith('error 1 syntax'), a[1])
        self.assertEqual(a[2], 'ok 2 0 0')
        self.assertTrue(a[3].startswith('error 3 syntax'), a[3])
        self.assertTrue(a[5].startswith('error 5 syntax'), a[5])
        self.assertEqual(a[6], 'error 6 toobig a value is at most 8192 bytes')
        self.assertEqual(a[7], 'ok 7')
        for i in range(8, 71):                                       # k0..k62: 64 keys with ok8192
            self.assertEqual(a[i], f'ok {i}')
        self.assertEqual(a[71], 'error 71 toobig 64 keys')           # k63
        self.assertEqual(a[72], 'error 72 toobig 64 keys')
        self.assertEqual(a[73], 'ok 73')                             # an existing key changes

    def test_needs_and_feature(self):
        out, log = self.requests('secret-get a', root=self.root(needs=''))
        self.assertIn('error 1 needs secrets=yes', log)
        out, log = self.requests('secret-get a', root=self.root(features=''))
        self.assertIn('error 1 unknown no such request', log)

    def test_file_store_is_private_and_lasts(self):
        out, log = self.requests('secret-set token {LEN}|s3cret\\nline', backend='file')
        self.assertIn('ok 1', log)
        path = self.work / 'state/rhun/secrets/rt--res'
        self.assertTrue(path.exists())
        if os.name != 'nt':
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
        self.assertEqual(path.read_bytes(), b'token 11\ns3cret\nline\n')
        out, log = self.requests('secret-get token', 'secret-keys', backend='file')
        self.assertEqual(self.answers(log)[:2], ['ok 1 1 11', 'body s3cret'], log)
        self.assertIn('ok 2 6', log)
        out, log = self.requests('secret-delete token', backend='file')
        self.assertFalse(path.exists())

    def test_page_lists_keys_and_forgets(self):
        root = self.root()
        self.args.write_text('secret-set alpha 1|a\nsecret-set beta 1|b\n', encoding='utf-8')
        shot = self.work / 'secrets.ppm'
        out = self.run_editor(['secret-backend memory', 'cmd rt/res.request', 'wait-ext res running',
                               'wait 150', 'cmd rt/res.request', 'wait 150', 'ext-page rt/res',
                               'wait 200', f'shot {shot.as_posix()}', 'print-secrets rt/res',
                               'secret-forget rt/res alpha', 'wait 100', 'secrets-refresh rt/res',
                               'wait 100', 'print-secrets rt/res', 'secret-forget rt/res',
                               'secrets-refresh rt/res', 'wait 100', 'print-secrets rt/res'],
                              exts=root)
        rows = [x for x in out if x.startswith('backend=')]
        self.assertEqual(rows, ['backend=memory keys=alpha,beta', 'backend=memory keys=beta',
                                'backend=memory keys='], out)
        if os.environ.get('RES_SHOTS'):
            shutil.copy(shot, os.environ['RES_SHOTS'] + '/secrets-page.ppm')

    def test_removal_deletes_secrets(self):
        out, log = self.requests('secret-set token 1|x', backend='file',
                                 extra=['ext-remove rt/res', 'dialog yes', 'wait 300'])
        self.assertFalse((self.work / 'state/rhun/secrets/rt--res').exists())

    @unittest.skipUnless(sys.platform == 'darwin', 'the macOS keychain')
    def test_macos_no_keychain_in_a_test_home(self):
        out, log = self.requests('secret-get token', backend='system')
        self.assertEqual(self.answers(log), ['error 1 refused no keychain is available'], log)

    @unittest.skipUnless(sys.platform == 'darwin', 'the macOS login keychain')
    def test_macos_keychain(self):
        # Never read the value with security(1): another program reading rhun's item makes the
        # keychain ask the user in a dialog. Its attributes and its removal ask nothing.
        def security(*args):
            p = subprocess.Popen(['security', *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 start_new_session=True)
            try:
                out, _ = p.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, 9)
                self.fail('security(1) waited for the user')
            return p.returncode, out.decode(errors='replace')
        service = 'rhun-test-' + pysecrets.token_hex(6)
        self.env['RHUN_SECRETS_SERVICE'] = service
        # the login keychain belongs to the real home (a test's own HOME has none: rhun then does
        # not ask, and says no keychain is available); config and state stay in the test's folders
        self.env['HOME'] = os.path.expanduser('~' + os.environ.get('USER', ''))
        full = service + ' rt/res'
        try:
            out, log = self.requests('secret-set token {LEN}|keychain value', 'secret-keys',
                                     backend='system')
            self.assertEqual(self.answers(log)[:3], ['ok 1', 'ok 2 6', 'body token'], log)
            code, attrs = security('find-generic-password', '-s', full, '-a', 'token')
            self.assertEqual(code, 0)
            self.assertIn('"acct"<blob>="token"', attrs)
            out, log = self.requests('secret-get token', 'secret-delete token', 'secret-get token',
                                     backend='system')
            self.assertEqual(self.answers(log), ['ok 1 1 14', 'body keychain value', 'ok 2', 'ok 3 0 0'], log)
            code, _ = security('find-generic-password', '-s', full, '-a', 'token')
            self.assertNotEqual(code, 0)
        finally:
            security('delete-generic-password', '-s', full, '-a', 'token')

    @unittest.skipUnless(sys.platform.startswith('linux') and os.environ.get('DBUS_SESSION_BUS_ADDRESS')
                         and shutil.which('secret-tool'), 'a Linux Secret Service')
    def test_linux_secret_service(self):
        service = 'rhun-test-' + pysecrets.token_hex(6)
        self.env['RHUN_SECRETS_SERVICE'] = service
        full = service + ' rt/res'
        out, log = self.requests('secret-set token {LEN}|keyring value', 'secret-set other 1|x',
                                 'secret-keys', backend='system', extra=['print-secrets rt/res'])
        a = self.answers(log)
        self.assertEqual(a[:3], ['ok 1', 'ok 2', 'ok 3 12'], log)
        i = log.index('ok 3 12')
        self.assertEqual(sorted([log[i + 1][5:], log[i + 2]]), ['other', 'token'], log)
        found = subprocess.run(['secret-tool', 'lookup', 'service', full, 'account', 'token'],
                               capture_output=True, text=True, env=dict(os.environ))
        self.assertEqual(found.stdout, 'keyring value')
        out, log = self.requests('secret-get token', 'secret-delete token', 'secret-get token',
                                 'secret-set other 2|yz', 'secret-get other', backend='system')
        self.assertEqual(self.answers(log), ['ok 1 1 13', 'body keyring value', 'ok 2', 'ok 3 0 0',
                                             'ok 4', 'ok 5 1 2', 'body yz'], log)
        out, log = self.requests('secret-set a 1|1', backend='system', extra=['secret-forget rt/res', 'wait 300'])
        found = subprocess.run(['secret-tool', 'search', '--all', 'service', full],
                               capture_output=True, text=True, env=dict(os.environ))
        self.assertNotIn('attribute.account', found.stdout + found.stderr)

    @unittest.skipUnless(sys.platform.startswith('linux') and not os.environ.get('DBUS_SESSION_BUS_ADDRESS'),
                         'Linux without a session bus')
    def test_linux_without_keyring_keeps_secrets_in_memory(self):
        self.env.pop('DBUS_SESSION_BUS_ADDRESS', None)
        self.env['XDG_RUNTIME_DIR'] = (self.work / 'run').as_posix()
        out, log = self.requests('secret-set token 1|x', 'secret-get token', backend='system',
                                 extra=['print-toast', 'print-secrets rt/res'])
        self.assertEqual(self.answers(log), ['ok 1', 'ok 2 1 1', 'body x'], log)
        self.assertIn("toast=No keyring is running: Res's sign-in lasts until rhun quits", out)
        self.assertTrue(any(x.startswith('backend=memory-fallback') for x in out), out)


if __name__ == '__main__':
    unittest.main()
