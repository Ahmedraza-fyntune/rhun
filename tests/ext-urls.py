#!/usr/bin/env python3
"""Opening URLs and link callbacks (resources group, feature urls): open-url's prompt (Open, Copy
Link, Cancel, Always) and the switch that takes Always back, external-uri, link tokens delivered
once as "0 link ID LEN", unknown and expired links, and the relay from a second rhun process. The
fake extension is tests/ext/res.py; RHUN_OPEN_URL names a fake browser that logs what it opens."""
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time
import unittest

lifecycle = __import__('ext-lifecycle')
host = __import__('ext-host')
RES = lifecycle.RES


class Urls(lifecycle.Base):
    def setUp(self):
        super().setUp()
        self.root = self.work / 'exts'
        folder = self.root / 'rt' / 'auth'
        folder.mkdir(parents=True)
        (folder / 'extension.ini').write_text(
            'name = auth\nowner = rt\ntitle = Auth Demo\nversion = 1\nprotocol = 1\n'
            f'runtime = python3\nrun = {RES.as_posix()}\non = command\nidle = stop\n'
            '[commands]\nrequest = Request\nbatch = Batch\n[needs]\nrun = python3\n', encoding='utf-8')
        self.state = self.work / 'state/rhun/extensions/rt--auth'
        self.state.mkdir(parents=True)
        self.env['RES_ARGS'] = '{state}/args.txt'
        self.env['RES_LOG'] = '{state}/res.log'
        self.env['RES_FEATURES'] = 'urls'
        # the fake browser: appends each URL it is given to opened.txt
        self.opened = self.work / 'opened.txt'
        browser = self.work / 'browser.py'
        browser.write_text(f'import sys\nopen({str(self.opened)!r}, "a").write(sys.argv[1] + "\\n")\n')
        launcher = self.work / 'browser'
        launcher.write_text(f'#!/bin/sh\nexec {sys.executable} {browser} "$1"\n')
        launcher.chmod(0o755)
        self.env['RHUN_OPEN_URL'] = launcher.as_posix()
        # sockets need short paths (sun_path holds 104 bytes): a folder of its own under /tmp
        import tempfile
        self.short = Path(tempfile.mkdtemp(prefix='rr-', dir='/tmp'))
        self.links = self.short / 'links'
        self.env['RHUN_LINK_DIR'] = self.links.as_posix()

    def tearDown(self):
        import shutil
        shutil.rmtree(self.short, ignore_errors=True)
        super().tearDown()

    def run_auth(self, lines, actions, **kw):
        (self.state / 'args.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
        log = self.state / 'res.log'
        if log.exists():
            log.unlink()
        return self.run_editor(actions, exts=self.root, files=(), **kw)

    def reslog(self):
        p = self.state / 'res.log'
        return p.read_text(errors='replace').splitlines() if p.exists() else []

    def answers(self):
        return [x for x in self.reslog() if x.startswith(('ok ', 'error ', 'body ', '0 link'))]

    def opened_urls(self):
        return self.opened.read_text().splitlines() if self.opened.exists() else []

    URL = 'https://example.test/login/oauth?client_id=x&state=y'

    def test_open_url_asks_then_opens(self):
        out = self.run_auth([f'open-url {{LEN}}|{self.URL}'], [
            'cmd rt/auth.request', 'wait-ext auth running', 'wait 300', 'print-palette', 'key Return',
            'wait 500'])
        pal = '\n'.join(out)
        self.assertIn('Auth Demo wants to open example.test in your browser', pal)
        self.assertIn('Copy Link', pal)
        self.assertIn('Always open links from Auth Demo', pal)
        self.assertIn('ok 1 opened', self.answers())
        self.assertEqual(self.opened_urls(), [self.URL])

    def test_copy_cancel_and_escape(self):
        out = self.run_auth([f'open-url {{LEN}}|{self.URL}'] * 3, [
            'cmd rt/auth.request', 'wait-ext auth running', 'wait 300', 'key Down', 'key Return',
            'wait 200', 'cmd rt/auth.request', 'wait 300', 'key Down', 'key Down', 'key Return',
            'wait 200', 'cmd rt/auth.request', 'wait 300', 'key Escape', 'wait 200'])
        a = self.answers()
        self.assertEqual(a, ['ok 1 copied', 'error 2 cancelled', 'error 3 cancelled'], self.reslog())
        self.assertEqual(self.opened_urls(), [])

    def test_always_is_remembered_and_revoked(self):
        self.run_auth([f'open-url {{LEN}}|{self.URL}', f'open-url {{LEN}}|{self.URL}x'], [
            'cmd rt/auth.request', 'wait-ext auth running', 'wait 300', 'key Down', 'key Down',
            'key Down', 'key Return', 'wait 300', 'cmd rt/auth.request', 'wait 400'])
        self.assertEqual(self.answers(), ['ok 1 opened', 'ok 2 opened'])
        self.assertEqual(self.opened_urls(), [self.URL, self.URL + 'x'])
        ini = (self.work / 'config/rhun/extensions.ini').read_text()
        self.assertIn('[rt/auth]\nopen_urls = yes', ini)
        # the next session opens without asking
        self.run_auth([f'open-url {{LEN}}|{self.URL}y'], ['cmd rt/auth.request', 'wait-ext auth running',
                                                          'wait 400', 'print-palette'])
        self.assertEqual(self.answers(), ['ok 1 opened'])

    def test_bad_urls_and_the_feature(self):
        self.run_auth(['open-url {LEN}|file:///etc/passwd', 'open-url {LEN}|https://a b',
                       'open-url {LEN}|javascript:x'], ['cmd rt/auth.batch', 'wait-ext auth running', 'wait 400'])
        a = self.answers()
        self.assertTrue(all(x.startswith(f'error {i} syntax') for i, x in enumerate(a, 1)), a)
        self.env['RES_FEATURES'] = ''
        self.run_auth([f'open-url {{LEN}}|{self.URL}'], ['cmd rt/auth.request', 'wait-ext auth running',
                                                         'wait 300'])
        self.assertEqual(self.answers(), ['error 1 unknown no such request'])

    def test_external_uri(self):
        self.run_auth(['external-uri {LEN}|http://127.0.0.1:43123/callback', 'external-uri {LEN}|rhun://ext/rt/auth/x',
                       'external-uri {LEN}|ftp://x'], ['cmd rt/auth.batch', 'wait-ext auth running', 'wait 400'])
        log = self.reslog()
        self.assertIn('ok 1 31', log)
        self.assertIn('body http://127.0.0.1:43123/callback', log)
        self.assertIn('ok 2 20', log)
        self.assertTrue(any(x.startswith('error 3 syntax') for x in log), log)

    def link_from(self, log):
        i = [n for n, x in enumerate(log) if re.fullmatch(r'ok 1 \d+', x)]
        self.assertTrue(i, log)
        return log[i[0] + 1][5:]

    def test_a_link_and_its_relay_socket(self):
        out = self.run_auth(['link'], ['cmd rt/auth.request', 'wait-ext auth running', 'wait 300',
                                       'print-links'])
        link = self.link_from(self.reslog())
        self.assertRegex(link, r'^rhun://ext/rt/auth/[0-9a-f]{32}$')
        self.assertIn('links=1 listening=1', out)
        if os.name != 'nt':
            self.assertEqual(stat.S_IMODE(self.links.stat().st_mode), 0o700)

    def test_four_links_at_most(self):
        self.run_auth(['link'] * 5, ['cmd rt/auth.batch', 'wait-ext auth running', 'wait 400'])
        log = [x for x in self.reslog() if x.startswith(('ok ', 'error '))]
        self.assertEqual(len(log), 5, log)
        self.assertEqual(log[4], 'error 5 toobig 4 links are pending')

    def test_unknown_link(self):
        out = self.run_auth([], ['link-deliver rhun://ext/rt/auth/' + '0' * 32, 'print-toast'])
        self.assertIn('toast=This link is not expected by any extension (it may have expired)', out)

    def test_link_in_one_session(self):
        # the link is read back from the log by a second script line: run the session in two steps
        # through the control commands, with the token learned from the first run's log
        (self.state / 'args.txt').write_text('link\nlink\n', encoding='utf-8')
        env = dict(self.env)
        script = self.work / 'a.rsc'
        log = self.state / 'res.log'
        proc = subprocess.Popen([str(host.EXE), self.proj.as_posix(), '--headless', '1000x600',
                                 '--extensions', str(self.root), '--control',
                                 str(self.short / 'ctl.sock')], env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, start_new_session=True)
        try:
            self.assertTrue(self.wait_for(lambda: (self.short / 'ctl.sock').exists()))
            self.ctl('cmd rt/auth.request')
            self.assertTrue(self.wait_for(lambda: log.exists() and any(re.fullmatch(r'ok 1 \d+', x)
                                                                       for x in self.reslog())))
            link = self.link_from(self.reslog())
            self.ctl(f'link-deliver {link}/done?code=abc&state=y')
            self.assertTrue(self.wait_for(lambda: any(x.startswith('0 link 1 ') for x in self.reslog())))
            self.assertIn(f'body {link}/done?code=abc&state=y', self.reslog())
            out = self.ctl(f'link-deliver {link}')
            out += self.ctl('print-toast')
            self.assertIn('toast=This link is not expected by any extension (it may have expired)', out)
            self.assertIn('links=0 listening=0', self.ctl('print-links'))
            # a second rhun started for a new link hands it over and quits
            self.ctl('cmd rt/auth.request')
            self.assertTrue(self.wait_for(lambda: sum(1 for x in self.reslog() if re.fullmatch(r'ok \d+ \d+', x)) >= 2))
            links = [self.reslog()[n + 1][5:] for n, x in enumerate(self.reslog()) if re.fullmatch(r'ok \d+ \d+', x)]
            second = subprocess.run([str(host.EXE), '--headless', '640x480', '--extensions', str(self.root),
                                     '--', links[-1] + '?code=2'], env=env, capture_output=True, timeout=20)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertTrue(self.wait_for(lambda: any(x.startswith('0 link 2 ') for x in self.reslog())),
                            self.reslog())
        finally:
            try:
                self.ctl('quit')
            except Exception:
                pass
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, 9)

    def wait_for(self, pred, seconds=8):
        end = time.time() + seconds
        while time.time() < end:
            if pred():
                return True
            time.sleep(0.05)
        return False

    def ctl(self, line):
        import socket
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(str(self.short / 'ctl.sock'))
        s.sendall(line.encode() + b'\n')
        s.shutdown(socket.SHUT_WR)
        data = b''
        s.settimeout(10)
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        s.close()
        return data.decode(errors='replace')


if __name__ == '__main__':
    unittest.main()
