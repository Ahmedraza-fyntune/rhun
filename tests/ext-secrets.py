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
            '[commands]\nrequest = Request\nping = Ping\n'
            f'[needs]\nrun = python3\n{needs}', encoding='utf-8')
        self.env['RES_FEATURES'] = features
        self.reslog = self.work / 'state/rhun/extensions/rt--res/res.log'
        self.env['RES_LOG'] = self.reslog.as_posix()
        return root

    def requests(self, *lines, extra=(), backend='memory', root=None):
        """Each line is a request for res.py; returns rhun's output and res.py's log."""
        root = root or self.root()
        self.args.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        if self.reslog.exists():
            self.reslog.unlink()
        actions = []
        if backend:
            actions.append('secret-backend ' + backend)
        for _ in lines:
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
                                 extra=['print-secrets rt/res'])
        self.assertEqual(self.answers(log), [
            'ok 1', 'ok 2 1 7', 'body abc def', 'ok 3 0 0', 'ok 4', 'ok 5 12',
            'body token', 'ok 6', 'ok 7 6', 'body other', 'ok 8'], log)
        self.assertIn('backend=memory keys=other', out)

    def test_limits_and_checks(self):
        lines = ['secret-get Bad', 'secret-get ' + 'k' * 65, 'secret-get a b',
                 'secret-set big {LEN}|' + 'x' * 8193, 'secret-set ok8192 {LEN}|' + 'y' * 8192]
        lines += [f'secret-set k{i} 1|v' for i in range(63)] + ['secret-set k63 1|v', 'secret-set one-more 1|v',
                                                                  'secret-set k1 2|vv']
        out, log = self.requests(*lines)
        a = [x for x in self.answers(log) if not x.startswith('body')]
        self.assertTrue(a[0].startswith('error 1 syntax'), a)
        self.assertTrue(a[1].startswith('error 2 syntax'), a)
        self.assertTrue(a[2].startswith('error 3 syntax'), a)
        self.assertEqual(a[3], 'error 4 toobig a value is at most 8192 bytes')
        self.assertEqual(a[4], 'ok 5')
        self.assertEqual(a[5:68], [f'ok {i}' for i in range(6, 69)])      # ok8192 and k0..k62: 64 keys
        self.assertEqual(a[68], 'error 69 toobig 64 keys')                # k63
        self.assertEqual(a[69], 'error 70 toobig 64 keys')
        self.assertEqual(a[70], 'ok 71')                                  # an existing key changes

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
                                 extra=['ext-remove rt/res', 'wait 200'])
        self.assertFalse((self.work / 'state/rhun/secrets/rt--res').exists())

    @unittest.skipUnless(sys.platform == 'darwin', 'the macOS login keychain')
    def test_macos_keychain(self):
        service = 'rhun-test-' + pysecrets.token_hex(6)
        self.env['RHUN_SECRETS_SERVICE'] = service
        full = service + ' rt/res'
        try:
            out, log = self.requests('secret-set token {LEN}|keychain value', 'secret-keys',
                                     backend='system')
            self.assertEqual(self.answers(log)[:3], ['ok 1', 'ok 2 6', 'body token'], log)
            found = subprocess.run(['security', 'find-generic-password', '-s', full, '-a', 'token', '-w'],
                                   capture_output=True, text=True)
            self.assertEqual(found.stdout.strip(), 'keychain value')
            out, log = self.requests('secret-get token', 'secret-delete token', 'secret-get token',
                                     backend='system')
            self.assertEqual(self.answers(log), ['ok 1 1 14', 'body keychain value', 'ok 2', 'ok 3 0 0'], log)
        finally:
            subprocess.run(['security', 'delete-generic-password', '-s', full, '-a', 'token'],
                           capture_output=True)


if __name__ == '__main__':
    unittest.main()
