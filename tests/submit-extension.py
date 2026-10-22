#!/usr/bin/env python3
"""rhun submit-extension and Extensions: Submit to Index... (docs/guide.md, "Submitting to the
index"), with no network: RHUN_EXT_BASE, RHUN_SUBMIT_API and RHUN_SUBMIT_RAW point at folders laid
out as github.com's releases, its API and raw.githubusercontent.com serve them, a fake `gh` on PATH
records what it is asked (and answers as a logged-in gh does), and a fake browser opener (`open`,
`xdg-open`) records the page. Covered: the entry from a release (its sums and the tag's commit)
against tests/data/submit-extension.expected, an entry already in the index keeping its category,
keywords, maintainer and what only the index sets, the browser page's address (new and edit), a
missing release or commit, the flags without a terminal, the attestation warning, the gh path
(fork, branch, file, pull request), the questions in a terminal, and the GUI's steps."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
WINDOWS = os.name == 'nt'
GOLDEN = ROOT / 'tests/data/submit-extension.expected'
CONFIG = ('[files]\nrestore_session = false\nrestore_project = false\n[updates]\ncheck = false\n'
          'extensions = off\n[git]\nenabled = false\n[ui]\nsidebar = false\nagents_panel = false\n'
          '[editor]\ncursor_blink = false\n')
COMMIT = '50bbdaf4e7d18d2e8cd919f148bfe01c2692cf1f'
SUMS = {'hello-linux-x86_64.tar.gz': '6809fc37b692c950d1e329679712ec3515264ac8967b5f1eb302a61d31d58990',
        'hello-macos-arm64.tar.gz': '2376c4b3080fcf654335cb7716439589a06348defbbcb196b6fdf026c09e5b5b',
        'hello-windows-x64.tar.gz': 'f5f1abed55b3ab6c8065812877aaf3e7db1ed74b9709c34776d7607048b3dc10',
        'other-linux-x86_64.tar.gz': '0' * 64}
FAKE_GH = r'''import json, os, sys
args = sys.argv[1:]
with open(os.environ['FAKE_GH_LOG'], 'a', encoding='utf-8') as f:
    f.write(json.dumps(args) + '\n')
def has(word):
    return any(a == word or a.startswith(word) for a in args)
if args[:2] == ['auth', 'status']:
    sys.exit(0)
if args[:2] == ['api', 'user']:
    print('octo'); sys.exit(0)
if args[:2] == ['api', 'repos/octo/extensions']:
    if os.environ.get('FAKE_GH_FORK') == 'yes':
        print('rhun-editor/extensions'); sys.exit(0)
    print('gh: Not Found (HTTP 404)', file=sys.stderr); sys.exit(1)
if args[:2] == ['repo', 'fork']:
    sys.exit(0)
if has('repos/octo/extensions/merge-upstream'):
    sys.exit(0)
if has('repos/octo/extensions/git/ref/heads/main'):
    print('1234567890123456789012345678901234567890'); sys.exit(0)
if has('repos/octo/extensions/git/refs'):
    print('{}'); sys.exit(0)
if any('/contents/' in a and '?ref=' in a for a in args):
    sha = os.environ.get('FAKE_GH_SHA')
    if sha:
        print(sha); sys.exit(0)
    print('gh: Not Found (HTTP 404)', file=sys.stderr); sys.exit(1)
if 'PUT' in args:
    print('{}'); sys.exit(0)
if args[:2] == ['pr', 'create']:
    print('Creating pull request for octo:x into main in rhun-editor/extensions')
    print('https://github.com/rhun-editor/extensions/pull/7'); sys.exit(0)
print('unexpected', args, file=sys.stderr)
sys.exit(3)
'''


class Base(unittest.TestCase):
    def setUp(self):
        self.work = Path(tempfile.mkdtemp(prefix='rhun-submit-test-')).resolve()
        self.home = self.work / 'home'
        (self.home / 'config/rhun').mkdir(parents=True)
        (self.home / 'config/rhun/config').write_text(CONFIG, encoding='utf-8')
        (self.home / 'tmp').mkdir()
        self.ext = self.work / 'hello'
        (self.ext / '.github/workflows').mkdir(parents=True)
        (self.ext / 'extension.ini').write_text('# the manifest\nname = hello\nowner = demo\ntitle = Hello\n'
                                                'version = 0.2.0\n\n[commands]\nsay = Say\n', encoding='utf-8')
        (self.ext / '.github/workflows/release.yml').write_text(
            'jobs:\n  release:\n    steps:\n      - uses: actions/attest-build-provenance@v2\n', encoding='utf-8')
        self.github = self.work / 'github'
        self.api = self.work / 'api'
        self.raw = self.work / 'raw'
        self.raw.mkdir()
        self.release('v0.2.0')
        self.bin = self.work / 'bin'
        self.bin.mkdir()
        self.opened = self.work / 'opened.txt'
        for opener in ('open', 'xdg-open'):
            p = self.bin / opener
            p.write_text('#!/bin/sh\nprintf "%%s\\n" "$1" >> "%s"\n' % self.opened, encoding='utf-8')
            p.chmod(0o755)
        self.gh_log = self.work / 'gh.log'

    def tearDown(self):
        shutil.rmtree(self.work, ignore_errors=True)

    def release(self, tag, sums=SUMS, commit=COMMIT):
        d = self.github / 'demo/hello/releases/download' / tag
        d.mkdir(parents=True, exist_ok=True)
        (d / 'sha256sums.txt').write_text(''.join('%s  %s\n' % (v, k) for k, v in sorted(sums.items())),
                                          encoding='utf-8')
        c = self.api / 'repos/demo/hello/commits'
        c.mkdir(parents=True, exist_ok=True)
        (c / tag).write_text(json.dumps({'sha': commit, 'node_id': 'x', 'commit': {'tree': {'sha': 'f' * 40}}},
                                        indent=2), encoding='utf-8')

    def entry(self, text):
        p = self.raw / 'rhun-editor/extensions/main/demo/hello.ini'
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding='utf-8')

    def with_gh(self):
        p = self.bin / 'gh'
        p.write_text('#!%s\n%s' % (sys.executable, FAKE_GH), encoding='utf-8')
        p.chmod(0o755)

    def gh_calls(self):
        if not self.gh_log.exists():
            return []
        return [json.loads(l) for l in self.gh_log.read_text(encoding='utf-8').splitlines()]

    def env(self, **extra):
        env = dict(os.environ)
        for k in ('XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'GH_TOKEN', 'GITHUB_TOKEN'):
            env.pop(k, None)
        path = os.pathsep.join([str(self.bin), '/usr/bin', '/bin'])
        if WINDOWS:
            path = os.pathsep.join([str(self.bin), os.environ.get('PATH', '')])
        env.update(HOME=str(self.home), USERPROFILE=str(self.home), XDG_CONFIG_HOME=str(self.home / 'config'),
                   XDG_STATE_HOME=str(self.home / 'state'), TMPDIR=str(self.home / 'tmp'), PATH=path,
                   RHUN_EXT_BASE=self.github.as_uri(), RHUN_SUBMIT_API=self.api.as_uri(),
                   RHUN_SUBMIT_RAW=self.raw.as_uri(), FAKE_GH_LOG=str(self.gh_log), GIT_CONFIG_NOSYSTEM='1')
        if WINDOWS:
            # ShellExecute would open a real browser: a program that is not there gets the address
            env['RHUN_SUBMIT_OPENER'] = str(self.work / 'no-browser.exe')
        env.update(extra)
        return env

    def cli(self, *args, **env):
        r = subprocess.run([str(EXE), 'submit-extension', *map(str, args)], cwd=self.ext, env=self.env(**env),
                           stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        return r.returncode, r.stdout.decode('utf-8', 'replace'), r.stderr.decode('utf-8', 'replace')

    def printed_entry(self, out):
        lines = out.splitlines()
        i = lines.index('# rhun-editor/extensions: demo/hello.ini')
        j = lines.index('', i)
        return '\n'.join(lines[i:j]) + '\n'

    def page(self, timeout=10):
        end = time.time() + timeout
        while time.time() < end:
            if self.opened.exists() and self.opened.read_text(encoding='utf-8').strip():
                return self.opened.read_text(encoding='utf-8').splitlines()[-1]
            time.sleep(0.1)
        return None

    def leftovers(self):
        return [p.name for p in (self.home / 'tmp').iterdir() if p.name.startswith('rhun-submit-')]


class Cli(Base):
    def test_the_entry_and_the_browser_page(self):
        code, out, err = self.cli('--category', 'other', '--keywords', 'charts statistics rust example',
                                  '--maintainer', 'vshvedov')
        self.assertEqual(code, 0, err)
        self.assertEqual(err, '')
        entry = self.printed_entry(out)
        self.assertEqual(entry, GOLDEN.read_text(encoding='utf-8'))
        url = [l for l in out.splitlines() if 'https://github.com/rhun-editor/extensions/new/main' in l][0]
        url = url[url.index('https://'):]
        self.assertTrue(url.startswith('https://github.com/rhun-editor/extensions/new/main?filename=demo/hello.ini'
                                       '&value=%23%20rhun-editor%2Fextensions%3A%20demo%2Fhello.ini%0Acategory%20%3D%20'
                                       'other%0A'), url)
        query = url.split('?', 1)[1]
        self.assertNotIn(' ', query)
        self.assertNotIn('\n', query)
        params = urllib.parse.parse_qs(query, keep_blank_values=True)
        self.assertEqual(params['filename'], ['demo/hello.ini'])
        self.assertEqual(params['value'], [entry])
        self.assertEqual(urllib.parse.quote(entry, safe='-._~'), query.split('&value=')[1])
        if not WINDOWS:
            self.assertEqual(self.page(), url)
        self.assertEqual(self.gh_calls(), [])
        self.assertEqual(self.leftovers(), [])

    def test_an_entry_in_the_index_keeps_its_answers(self):
        self.entry('# rhun-editor/extensions: demo/hello.ini\ncategory = languages\nkeywords = old words\n'
                   'maintainer = someone\nfeatured = yes\nrhun = 0.18.0\n# the reviewed release\ntag = v0.1.0\n'
                   'commit = %s\nsha256.linux-x86_64 = %s\n' % ('1' * 40, '2' * 64))
        code, out, err = self.cli('--yes')
        self.assertEqual(code, 0, err)
        entry = self.printed_entry(out).splitlines()
        self.assertEqual(entry[:7], ['# rhun-editor/extensions: demo/hello.ini', 'category = languages',
                                     'keywords = old words', 'maintainer = someone', 'featured = yes', 'rhun = 0.18.0',
                                     '# the reviewed release; a new version is a new pull request'])
        self.assertEqual(entry[7:9], ['tag = v0.2.0', 'commit = ' + COMMIT])
        # GitHub's editor for the file that is there
        self.assertIn('https://github.com/rhun-editor/extensions/edit/main/demo/hello.ini', out)
        self.assertNotIn('/new/main', out)
        # a flag still wins
        code, out, err = self.cli('--yes', '--category', 'tools', '--maintainer', 'octo', '--keywords', '')
        entry = self.printed_entry(out).splitlines()
        self.assertEqual(entry[1:4], ['category = tools', 'maintainer = octo', 'featured = yes'])

    def test_the_tag_flag_and_a_missing_release(self):
        self.release('v0.3.0', commit='3' * 40)
        code, out, err = self.cli('--tag', 'v0.3.0', '--category', 'tools')
        self.assertEqual(code, 0, err)
        self.assertIn('tag = v0.3.0\ncommit = ' + '3' * 40 + '\n', self.printed_entry(out))
        code, out, err = self.cli('--tag', 'v9.9.9', '--category', 'tools')
        self.assertEqual(code, 1)
        self.assertIn('rhun submit-extension: demo/hello has no release v9.9.9 with a sha256sums.txt (%s'
                      '/demo/hello/releases/download/v9.9.9/sha256sums.txt)' % self.github.as_uri(), err)
        self.assertEqual(self.leftovers(), [])
        (self.api / 'repos/demo/hello/commits/v0.3.0').unlink()
        code, out, err = self.cli('--tag', 'v0.3.0', '--category', 'tools')
        self.assertEqual(code, 1)
        self.assertIn('could not read the commit of v0.3.0', err)
        self.release('v0.4.0', sums={'other.tar.gz': '1' * 64})
        code, out, err = self.cli('--tag', 'v0.4.0', '--category', 'tools')
        self.assertEqual(code, 1)
        self.assertIn("the release's sha256sums.txt lists no hello-TARGET.tar.gz", err)
        self.assertEqual(self.leftovers(), [])

    def test_without_a_terminal_the_category_is_needed(self):
        usage = 'usage: rhun submit-extension [DIR] [--tag vX.Y.Z] [--category C]'
        code, out, err = self.cli()
        self.assertEqual(code, 2)
        self.assertIn('without a terminal it needs --category C', err)
        self.assertIn(usage, err)
        self.assertEqual(self.leftovers(), [])
        code, out, err = self.cli('--category', 'gadgets')
        self.assertEqual(code, 2)
        self.assertIn('the category is one of languages formatters themes testing debugging tools packs other', err)
        code, out, err = self.cli('--category', 'tools', '--keywords', 'Bad Words')
        self.assertEqual(code, 1)
        self.assertIn('keywords are lowercase words', err)
        code, out, err = self.cli('--category', 'tools', '--gh')
        self.assertEqual(code, 1)
        self.assertIn('gh is not installed or not logged in', err)
        code, out, err = self.cli(self.work / 'nothing', '--category', 'tools')
        self.assertEqual(code, 1)
        self.assertIn('has no extension.ini', err)
        code, out, err = self.cli('--help')
        self.assertEqual(code, 0)
        self.assertIn(usage, out)

    def test_a_release_workflow_without_attestation_is_a_warning(self):
        (self.ext / '.github/workflows/release.yml').write_text('jobs: {}\n', encoding='utf-8')
        code, out, err = self.cli('--category', 'tools')
        self.assertEqual(code, 0, err)
        self.assertIn('warning: .github/workflows/release.yml does not attest the archives '
                      '(actions/attest-build-provenance)', err)

    @unittest.skipIf(WINDOWS, 'the fake gh is a script with a #! line')
    def test_the_pull_request_through_gh(self):
        self.with_gh()
        code, out, err = self.cli('--yes', '--category', 'tools', '--keywords', 'demo')
        self.assertEqual(code, 0, err)
        self.assertIn('Pull request: https://github.com/rhun-editor/extensions/pull/7', out)
        entry = self.printed_entry(out)
        self.assertIn('maintainer = octo\n', entry)        # gh's login by default
        calls = self.gh_calls()
        self.assertIn(['repo', 'fork', 'rhun-editor/extensions', '--clone=false', '--default-branch-only'], calls)
        branch = 'submit-demo-hello-v0.2.0'
        self.assertIn(['api', '-X', 'POST', 'repos/octo/extensions/git/refs', '-f', 'ref=refs/heads/' + branch,
                       '-f', 'sha=1234567890123456789012345678901234567890'], calls)
        put = [c for c in calls if 'PUT' in c][0]
        self.assertEqual(put[:4], ['api', '-X', 'PUT', 'repos/octo/extensions/contents/demo/hello.ini'])
        fields = dict(put[i + 1].split('=', 1) for i in range(4, len(put), 2))
        self.assertEqual(fields['message'], 'demo/hello v0.2.0')
        self.assertEqual(fields['branch'], branch)
        self.assertNotIn('sha', fields)
        self.assertEqual(base64.b64decode(fields['content']).decode(), entry)
        pr = [c for c in calls if c[:2] == ['pr', 'create']][0]
        self.assertEqual(pr[2:10], ['-R', 'rhun-editor/extensions', '--base', 'main', '--head', 'octo:' + branch,
                                    '--title', 'demo/hello v0.2.0'])
        body = pr[pr.index('--body') + 1]
        self.assertIn('Release: https://github.com/demo/hello/releases/tag/v0.2.0', body)
        self.assertIn('gh attestation verify', body)
        self.assertIn(COMMIT, body)
        self.assertIsNone(self.page(timeout=0.5))
        self.assertEqual(self.leftovers(), [])

    @unittest.skipIf(WINDOWS, 'the fake gh is a script with a #! line')
    def test_gh_updates_the_file_on_an_existing_fork(self):
        self.with_gh()
        self.entry('category = tools\nmaintainer = someone\ntag = v0.1.0\n')
        code, out, err = self.cli('--gh', FAKE_GH_FORK='yes', FAKE_GH_SHA='abc123')
        self.assertEqual(code, 0, err)
        calls = self.gh_calls()
        self.assertFalse([c for c in calls if c[:2] == ['repo', 'fork']])
        put = [c for c in calls if 'PUT' in c][0]
        self.assertIn('sha=abc123', put)
        self.assertIn('maintainer = someone\n', self.printed_entry(out))
        # without --gh and --yes, no terminal: the browser
        self.gh_log.unlink()
        code, out, err = self.cli('--category', 'tools')
        self.assertEqual(code, 0, err)
        self.assertFalse([c for c in self.gh_calls() if c[:2] == ['pr', 'create']])
        self.assertIn('/edit/main/demo/hello.ini', out)


@unittest.skipIf(WINDOWS, 'a pty is POSIX')
class Terminal(Base):
    def test_the_questions(self):
        import pty
        import select
        self.with_gh()
        master, slave = pty.openpty()
        proc = subprocess.Popen([str(EXE), 'submit-extension'], cwd=self.ext, env=self.env(TERM='xterm'),
                                stdin=slave, stdout=slave, stderr=slave, close_fds=True)
        buf = b''

        def expect(text, timeout=30):
            nonlocal buf
            end = time.time() + timeout
            while text.encode() not in buf:
                if time.time() > end:
                    self.fail('no %r in %r' % (text, buf[-800:]))
                r, _, _ = select.select([master], [], [], 0.2)
                if r:
                    try:
                        buf += os.read(master, 4096)
                    except OSError:
                        break
            buf = buf[buf.index(text.encode()) + len(text):]
        expect('Category:')
        expect('> other')                          # the default without an entry
        os.write(master, b'6')                     # tools
        expect('Category: tools')
        expect('Keywords (space separated): ')
        os.write(master, b'Demo\r')
        expect('keywords are lowercase words')
        os.write(master, b'\x7f' * 4 + b'demo hello\r')
        expect('Maintainer (GitHub user): octo')
        os.write(master, b'\r')
        expect('Open the pull request with gh as octo:')
        os.write(master, b'\x1b[B\r')              # No: the browser
        expect('Open the pull request with gh as octo: No')
        expect('https://github.com/rhun-editor/extensions/new/main?filename=demo/hello.ini')
        proc.wait(timeout=60)
        os.close(slave)
        os.close(master)
        self.assertEqual(proc.returncode, 0)
        page = self.page()
        value = urllib.parse.parse_qs(page.split('?', 1)[1])['value'][0]
        self.assertIn('category = tools\nkeywords = demo hello\nmaintainer = octo\n', value)
        self.assertFalse([c for c in self.gh_calls() if c[:2] == ['pr', 'create']])


class Gui(Base):
    def ui(self, lines, project=None):
        script = self.work / 'script.txt'
        script.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        r = subprocess.run([str(EXE), str(project or self.ext), '--headless', '1200x800', '--scale', '1',
                            '--script', str(script)], env=self.env(), stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        return r.stdout.decode('utf-8', 'replace').splitlines()

    def heads(self, out):
        return [l for l in out if l.startswith('quick ')]

    def test_the_steps_and_the_browser(self):
        out = self.ui(['cmd submit_extension', 'wait 100', 'print-quick', 'key Return', 'wait-submit-extension',
                       'print-quick', 'type tools', 'key Return', 'wait 100', 'print-quick', 'type demo',
                       'key Return', 'wait 100', 'print-quick', 'key Return', 'wait 100', 'print-quick',
                       'key Return', 'wait-submit-extension', 'print-notes', 'print-submit-entry'])
        heads = self.heads(out)
        self.assertIn(' title=Submit to Index step=1/5 mode=input ', heads[0])
        self.assertTrue(heads[0].endswith(' field=' + str(self.ext)), heads[0])
        self.assertIn(' step=2/5 mode=pick ', heads[1])
        self.assertIn(' step=3/5 mode=input ', heads[2])
        self.assertIn(' step=4/5 mode=input ', heads[3])
        self.assertTrue(heads[3].endswith(' field=demo'), heads[3])      # the owner without gh or git
        self.assertIn(' step=5/5 mode=pick ', heads[4])
        rows = [l for l in out if l.startswith('row ')]
        self.assertTrue(any(' id=other label=other' in r and ' active' in r for r in rows), rows)
        self.assertTrue(any(' id=browser ' in r for r in rows), rows)
        self.assertFalse(any(' id=gh ' in r for r in rows), rows)
        self.assertIn('submit-extension=done', out)
        self.assertTrue(any('GitHub opens to propose demo/hello v0.2.0' in l for l in out), out)
        self.assertIn('category = tools', out)
        self.assertIn('keywords = demo', out)
        if WINDOWS:
            return
        page = self.page()
        self.assertIsNotNone(page)
        self.assertTrue(page.startswith('https://github.com/rhun-editor/extensions/new/main?filename=demo/hello.ini&value='))
        self.assertEqual(self.leftovers(), [])

    def test_a_missing_release_shows_under_the_folder(self):
        shutil.rmtree(self.github)
        out = self.ui(['cmd submit_extension', 'wait 100', 'key Return', 'wait-submit-extension', 'print-quick',
                       'key Escape', 'wait-submit-extension'])
        head = self.heads(out)[-1]
        self.assertIn(' step=1/5 ', head)
        self.assertIn(' msg=error:demo/hello has no release v0.2.0 with a sha256sums.txt', head)
        self.assertIn('submit-extension=idle', out)
        self.assertEqual(self.leftovers(), [])

    @unittest.skipIf(WINDOWS, 'the fake gh is a script with a #! line')
    def test_gh_from_the_gui_and_an_entry_that_is_there(self):
        self.with_gh()
        self.entry('category = testing\nkeywords = go tests\nmaintainer = someone\ntag = v0.1.0\n')
        out = self.ui(['cmd submit_extension', 'wait 100', 'key Return', 'wait-submit-extension', 'key Return',
                       'wait 100', 'print-quick', 'key Return', 'wait 100', 'print-quick', 'key Return', 'wait 100',
                       'print-quick', 'key Return', 'wait-submit-extension', 'print-notes'])
        heads = self.heads(out)
        self.assertTrue(heads[0].endswith(' field=go tests'), heads[0])
        self.assertTrue(heads[1].endswith(' field=someone'), heads[1])
        rows = [l for l in out if l.startswith('row ')]
        self.assertTrue(any(' id=gh ' in r and ' active' in r for r in rows), rows)
        self.assertIn('submit-extension=done', out)
        self.assertTrue(any('Opened the pull request for demo/hello v0.2.0: '
                            'https://github.com/rhun-editor/extensions/pull/7' in l for l in out), out)
        put = [c for c in self.gh_calls() if 'PUT' in c][0]
        content = base64.b64decode(dict(put[i + 1].split('=', 1) for i in range(4, len(put), 2))['content']).decode()
        self.assertIn('category = testing\nkeywords = go tests\nmaintainer = someone\n', content)


if __name__ == '__main__':
    unittest.main()
