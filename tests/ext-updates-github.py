#!/usr/bin/env python3
"""Extension updates against github.com itself (network): rhun-editor/showcase installed at v0.1.0,
the update check finding showcase's latest (from the rhun extensions index, or GitHub's
/releases/latest redirect without one), the update, Roll back to 0.1.0 (automatic updates then
leave that version alone) and the update again. A second test serves an index
pinning showcase v0.1.2 (its digests taken from the release's sha256sums.txt) on 127.0.0.1 and
sends every other request on to github.com: the reviewed version installs by itself, its archive
checked against the index. Each run gets its own HOME. SHOTS=DIR keeps screenshots of the details
page with its Update and Roll back buttons, and of Browse."""
import hashlib
import http.server
import threading
import urllib.request
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\nextensions = check\n[git]\nenabled = false\n')


class GitHubUpdates(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-updates-github-')
        self.work = Path(self.tmp.name).resolve()
        (self.work / 'proj').mkdir()
        (self.work / 'proj/a.txt').write_text('hello\n', encoding='utf-8')
        cfg = self.work / 'config/rhun'
        cfg.mkdir(parents=True)
        (cfg / 'config').write_text(CONFIG, encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(), XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix())
        self.env.pop('RHUN_EXT_BASE', None)
        self.shots = os.environ.get('SHOTS')

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, lines, env=None):
        script = self.work / 'script.rsc'
        script.write_text('\n'.join(['wait 100', *lines, 'quit']) + '\n', encoding='utf-8')
        r = subprocess.run([str(EXE), (self.work / 'proj').as_posix(), '--headless', '1100x800', '--scale', '1',
                            '--script', script.as_posix()], env=env or self.env, capture_output=True, timeout=600)
        self.assertEqual(r.returncode, 0, r.stderr.decode(errors='replace')[-2000:])
        return [l for l in r.stdout.decode('utf-8', errors='replace').splitlines() if not l.startswith('ext=')]

    def shot(self, name):
        return ['shot ' + (Path(self.shots) / name).as_posix()] if self.shots else []

    def test_install_update_roll_back_and_update_again(self):
        out = self.run_editor(['ext-install rhun-editor/showcase@0.1.0', 'wait-install', 'print-dialog', 'dialog yes',
                               'wait-ext showcase running', 'print-ext-versions showcase'])
        self.assertEqual(out[0], 'install=asking')
        self.assertEqual(out[1], 'dialog=Add “Showcase”?')
        self.assertTrue(out[2].startswith('text=Version 0.1.0 from github.com/rhun-editor/showcase. It can '), out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=- link=no fresh=0', out)

        out = self.run_editor(['wait-ext showcase running', 'ext-check-updates', 'wait-ext-updates',
                               'print-ext-updates', 'cmd extensions', 'ext-page showcase', 'wait 300',
                               *self.shot('showcase-update.ppm')])
        line = [l for l in out if l.startswith('rhun-editor/showcase ')][0]
        m = re.match(r'^rhun-editor/showcase installed=0\.1\.0 latest=(\d+\.\d+\.\d+) state=available '
                     r'from=(github|index)$', line)
        self.assertTrue(m, line)
        latest, reviewed = m.group(1), m.group(2) == 'index'
        print('update source:', 'the rhun extensions index' if reviewed else "GitHub's latest-release redirect",
              file=sys.stderr)

        # the latest is whatever showcase has released (and the index reviewed): an unreviewed version, or one
        # asking for new access, asks first
        steps = ['wait-ext showcase running', 'ext-update showcase', 'wait-ext-updates', 'print-dialog',
                 'dialog yes', 'wait-ext-updates']
        out = self.run_editor(steps + ['wait-ext showcase running', 'print-ext-versions showcase', 'print-toast'])
        if not reviewed:
            self.assertIn(f'dialog=Update “Showcase” to {latest}?', out)
            self.assertIn('text=Not in the rhun extensions index: nobody has reviewed this version.', out)
        self.assertIn(f'version={latest} source=github tag=v{latest} previous=0.1.0 link=no fresh=0', out)

        out = self.run_editor(['wait-ext showcase running', 'cmd extensions', 'ext-page showcase', 'wait 300',
                               *self.shot('showcase-rollback.ppm'), 'ext-rollback showcase',
                               'wait-ext showcase running', 'print-toast', 'print-ext-versions showcase'])
        self.assertIn('toast=Rolled back Showcase to 0.1.0', out)
        self.assertIn(f'version=0.1.0 source=github tag=v0.1.0 previous={latest} link=no fresh=0', out)
        state = (self.work / 'state/rhun/extension-updates').read_text(encoding='utf-8')
        self.assertIn(f'skip = v{latest}', state)

        # automatic updates (install mode, checking every half second) leave the version rolled back from
        # the steps above only check (extensions = check), so a reviewed version is not installed by
        # itself before the test asks for it; this one installs as the default does
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text(encoding='utf-8').replace('extensions = check', 'extensions = install'),
                          encoding='utf-8')
        env = dict(self.env, RHUN_EXT_UPDATE_EVERY='500')
        out = self.run_editor(['wait-ext showcase running', 'wait 2000', 'wait-ext-updates', 'print-ext-updates',
                               'print-ext-versions showcase'], env=env)
        self.assertIn(f'version=0.1.0 source=github tag=v0.1.0 previous={latest} link=no fresh=0', out)
        self.assertTrue(any(l.startswith(f'rhun-editor/showcase installed=0.1.0 latest={latest} state=skipped')
                            for l in out), out)

        out = self.run_editor(steps + ['wait-ext showcase running', 'print-ext-versions showcase'])
        self.assertIn(f'version={latest} source=github tag=v{latest} previous=0.1.0 link=no fresh=0', out)

    def test_an_index_pinned_release_installs_by_itself_checked_against_the_index(self):
        config = self.work / 'config/rhun/config'     # automatic updates install, as by default
        config.write_text(config.read_text(encoding='utf-8').replace('extensions = check', 'extensions = install'),
                          encoding='utf-8')
        target = 'windows-x64' if os.name == 'nt' else 'macos-arm64' if sys.platform == 'darwin' else 'linux-x86_64'
        sums = urllib.request.urlopen('https://github.com/rhun-editor/showcase/releases/download/v0.1.2/'
                                      'sha256sums.txt', timeout=60).read().decode()
        digest = dict(reversed(l.split()) for l in sums.splitlines() if l.strip())['showcase-%s.tar.gz' % target]
        index = ('format = 1\n\n[rhun-editor/showcase]\ntitle = Showcase\nversion = 0.1.2\ntag = v0.1.2\n'
                 'description = A tour of everything an extension can do in rhun.\nsha256.%s = %s\n'
                 'needs = documents=write project=read terminal=yes\nfeatured = yes\n' % (target, digest)).encode()
        files = {'/rhun-editor/extensions/releases/latest/download/index.ini': index,
                 '/rhun-editor/extensions/releases/latest/download/sha256sums.txt':
                     ('%s  index.ini\n' % hashlib.sha256(index).hexdigest()).encode()}

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                if self.path in files:
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(files[self.path])))
                    self.end_headers()
                    self.wfile.write(files[self.path])
                    return
                self.send_response(302)
                self.send_header('Location', 'https://github.com' + self.path)
                self.send_header('Content-Length', '0')
                self.end_headers()

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        env = dict(self.env, RHUN_EXT_BASE='http://127.0.0.1:%d' % server.server_address[1])
        out = self.run_editor(['ext-install rhun-editor/showcase@0.1.0', 'wait-install', 'print-dialog', 'dialog yes',
                               'wait-ext showcase running', 'ext-check-updates', 'wait-ext-updates',
                               'wait-ext showcase running', 'print-ext-updates', 'print-ext-versions showcase',
                               'print-toast', 'ext-browse', 'wait-index', 'wait 300',
                               *self.shot('showcase-browse.ppm'), 'print-ext-browse'], env=env)
        self.assertIn('Not in the rhun extensions index: nobody has reviewed it.', out)    # 0.1.0 is not the pin
        self.assertIn('rhun-editor/showcase installed=0.1.2 latest=0.1.2 state=current from=index', out)
        self.assertIn('version=0.1.2 source=github tag=v0.1.2 previous=0.1.0 link=no fresh=0', out)
        self.assertIn('toast=Updated Showcase to 0.1.2', out)
        self.assertIn('rhun-editor/showcase 0.1.2 button=installed', out)
        record = (self.work / 'config/rhun/extensions/rhun-editor/showcase/.rhun-install').read_text(encoding='utf-8')
        self.assertIn('reviewed = yes', record)
        self.assertIn('sha256 = ' + digest, record)


if __name__ == '__main__':
    unittest.main()
