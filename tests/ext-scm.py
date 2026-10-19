#!/usr/bin/env python3
"""The source control contract (docs/extensions/v1.1.md, features git-data, commit-message, quickdiff
and scm), driven headlessly with the scripted fake extension tests/ext/scmfake.py in a real git
repository: Git data through rhun under [needs] git = read and the trust pause, commit-message
providers beside the built-in ones, quick-diff bases for the gutter, and a second VCS provider tab."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest
import urllib.parse

host = __import__('ext-host')
ROOT = host.ROOT
FAKE = ROOT / 'tests/ext/scmfake.py'
ZERO = '0' * 40


def parse_blame(body):
    """a git-blame body: ({sha: (author, mail, summary)}, [(sha, l1, l2, orig)])"""
    data = body.encode()
    end = data.index(b'\n')
    nc, nr = map(int, data[:end].split())
    pos, commits, runs = end + 1, {}, []
    for _ in range(nc):
        end = data.index(b'\n', pos)
        sha, time, al, ml, sl = data[pos:end].decode().split(' ')
        pos = end + 1
        fields = []
        for n in (int(al), int(ml), int(sl)):
            fields.append(data[pos:pos + n].decode())
            pos += n
        commits[sha] = tuple(fields)
    for _ in range(nr):
        end = data.index(b'\n', pos)
        runs.append(tuple(data[pos:end].decode().split(' ')))
        pos = end + 1
    assert pos == len(data), (pos, len(data))
    return commits, runs


class Base(unittest.TestCase):
    # the host tests' isolated run without their test methods
    run_editor = host.Host.run_editor
    tearDown = host.Host.tearDown

    def setUp(self):
        host.Host.setUp(self)
        self.env['GIT_CONFIG_NOSYSTEM'] = '1'
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text().replace('[git]\nenabled = false\n', '[git]\nenabled = true\n'))
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Ada')
        self.git('config', 'user.email', 'ada@example.invalid')
        self.git('add', '-A')
        self.git('commit', '-qm', 'First')
        (self.proj / 'a.txt').write_text('hello world\nsecond line\nthird line\n', encoding='utf-8')
        self.git('commit', '-qam', 'Third line')

    def git(self, *args, cwd=None):
        return subprocess.run(['git', '-C', str(cwd or self.proj), *args], env=self.env, check=True,
                              capture_output=True).stdout.decode()

    def ext(self, name='fake', needs='git = read\ndocuments = read', hello='hello 1 git-data',
            commands=None, answers=None, events=None, ini='', folder='exts'):
        root = self.work / folder
        dst = root / 'rhun-tests' / name
        dst.mkdir(parents=True, exist_ok=True)
        cmds = ''.join(f'{c} = {c.title()}\n' for c in (commands or {}))
        (dst / 'extension.ini').write_text(
            f'name = {name}\nowner = rhun-tests\ntitle = {name.title()}\nversion = 1\nprotocol = 1\n'
            f'runtime = python3\nrun = scmfake.py\non = command\n{ini}\n[commands]\n{cmds}'
            f'[needs]\n{needs}\n', encoding='utf-8')
        shutil.copy(FAKE, dst / 'scmfake.py')
        (dst / 'script.json').write_text(json.dumps({
            'hello': hello, 'commands': commands or {}, 'answers': answers or {}, 'events': events or {}}))
        return root

    def fake_log(self, name='fake'):
        path = self.work / f'state/rhun/extensions/rhun-tests--{name}/log.txt'
        return path.read_text(encoding='utf-8').splitlines() if path.exists() else []

    def replies(self, name='fake'):
        """(reply line, body or None) for each ok/error the fake received"""
        log, out = self.fake_log(name), []
        for i, line in enumerate(log):
            if line.startswith('< ok ') or line.startswith('< error '):
                body = None
                if i + 1 < len(log) and log[i + 1].startswith('| '):
                    body = eval(log[i + 1][2:])
                out.append((line[2:], body))
        return out

    def run_cmd(self, cmd, actions=(), name='fake', **kw):
        return self.run_editor([f'cmd {name}.{cmd}', f'wait-ext {name} running', 'wait 300', 'wait-git',
                                'wait 300', *actions], drop_waits=True, **kw)



class GitData(Base):
    """C1: Git data through rhun"""

    def test_repo_and_status_answer_from_rhuns_status(self):
        (self.proj / 'a.txt').write_text('changed\n', encoding='utf-8')
        (self.proj / 'new file.txt').write_text('x\n', encoding='utf-8')
        exts = self.ext(commands={'go': [['git-repo', None], ['git-status', None]]})
        self.run_cmd('go', exts=exts)
        (repo, rbody), (status, sbody) = self.replies()
        head, rest = rbody.split('\n', 1)
        rl, bl, ul, kind, ahead, behind, state = head.split(' ')
        self.assertEqual((kind, ahead, behind, state), ('branch', '0', '0', 'dirty'))
        self.assertEqual(rest, self.proj.as_posix() + 'main')
        self.assertEqual((int(rl), int(bl), int(ul)), (len(self.proj.as_posix()), 4, 0))
        self.assertEqual(sbody, '2\n.M 5\na.txt?? 12\nnew file.txt')

    def test_blame_covers_unsaved_text(self):
        exts = self.ext(commands={'go': [['git-blame $DOC', None]]})
        self.run_editor(['key ctrl+End', 'key Up', 'key End', 'type  (edited)', 'cmd fake.go',
                         'wait-ext fake running', 'wait 300', 'wait-git', 'wait 300'], exts=exts)
        [(reply, body)] = self.replies()
        self.assertTrue(reply.startswith('ok 1 '), reply)
        self.assertEqual(int(reply.split()[2]), len(body.encode()))
        commits, runs = parse_blame(body)
        first = self.git('rev-parse', 'HEAD~1').strip()
        second = self.git('rev-parse', 'HEAD').strip()
        self.assertEqual(commits[first], ('Ada', 'ada@example.invalid', 'First'))
        self.assertNotIn(second, commits)       # its only line is edited and not saved
        self.assertIn(ZERO, commits)
        self.assertEqual(runs, [(first, '1', '2', '1'), (ZERO, '3', '3', '3')])

    def test_blame_of_a_long_document_is_fed_as_git_reads_it(self):
        # 200 KB: more than a pipe holds, so rhun writes it as git takes it
        text = ''.join(f'line {i:06d} of a long file with some words to make it longer\n' for i in range(3000))
        (self.proj / 'big.txt').write_text(text, encoding='utf-8')
        self.git('add', 'big.txt')
        self.git('commit', '-qm', 'Big')
        exts = self.ext(commands={'go': [['git-blame $DOC', None]]})
        self.run_editor(['key ctrl+End', 'key Up', 'type edited ', 'cmd fake.go', 'wait-ext fake running',
                         'wait 300', 'wait-git', 'wait 300'], exts=exts, files=('big.txt',))
        [(reply, body)] = self.replies()
        commits, runs = parse_blame(body)
        big = self.git('rev-parse', 'HEAD').strip()
        self.assertEqual(runs, [(big, '1', '2999', '1'), (ZERO, '3000', '3000', '3000')])

    def test_blame_of_a_crlf_file_compares_its_line_ends(self):
        (self.proj / 'w.txt').write_bytes(b'one\r\ntwo\r\nthree\r\n')
        self.git('add', 'w.txt')
        self.git('commit', '-qm', 'Windows')
        exts = self.ext(commands={'go': [['git-blame $DOC', None]]})
        self.run_editor(['cmd fake.go', 'wait-ext fake running', 'wait 300', 'wait-git', 'wait 300'],
                        exts=exts, files=('w.txt',))
        commits, runs = parse_blame(self.replies()[0][1])
        self.assertEqual(runs, [(self.git('rev-parse', 'HEAD').strip(), '1', '3', '1')])

    def test_show_over_four_megabytes_is_toobig(self):
        (self.proj / 'huge.bin').write_bytes(b'x' * (4 * 1024 * 1024 + 1))
        self.git('add', 'huge.bin')
        self.git('commit', '-qm', 'Huge')
        exts = self.ext(commands={'go': [['git-show HEAD 8', 'huge.bin'], ['git-repo', None]]})
        self.run_cmd('go', exts=exts)
        got = self.replies()
        self.assertTrue(got[0][0].startswith('error 1 toobig'), got)
        self.assertTrue(got[1][0].startswith('ok 2 '), got)

    def test_the_longest_revision_and_path_together(self):
        # review: REV (200 bytes) and PATH (4095) together once overran the copy of REV:PATH
        rev, path = 'a' * 200, 'd/' * 2046 + 'abc'
        exts = self.ext(commands={'go': [[f'git-show {rev} {len(path)}', path], ['git-repo', None]]})
        self.run_cmd('go', exts=exts)
        got = self.replies()
        self.assertTrue(got[0][0].startswith('error 1 nofile'), got)
        self.assertTrue(got[1][0].startswith('ok 2 '), got)
        self.assertEqual(got[1][1].split('\n', 1)[1], self.proj.as_posix() + 'main')

    def test_a_plain_ok_carries_no_old_body(self):
        # review: git-diff-open's "ok ID" once came with the body of the git-show before it
        exts = self.ext(commands={'go': [['git-show HEAD 5', 'a.txt'], ['git-diff-open HEAD~1 HEAD 5', 'a.txt'],
                                         ['git-repo', None]]})
        self.run_cmd('go', exts=exts)
        log = self.fake_log()
        i, j = log.index('< ok 2'), [k for k, l in enumerate(log) if l.startswith('< ok 3 ')][0]
        self.assertTrue(all(l.startswith('< 0 ') for l in log[i + 1:j]), log[i:j + 1])

    def test_ahead_alone_changes_the_signature(self):
        # review: the ahead count was dropped from what decides "0 git changed"
        sigs = []
        self.git('branch', '-f', 'up', 'HEAD~1')
        self.git('branch', '--set-upstream-to=up')
        for ahead in (1, 2):
            out = self.run_editor(['wait-git', 'wait 200', 'print-git', 'print-git-data'], drop_waits=True)
            self.assertIn(f'ahead={ahead}', out[0])
            sigs.append([l for l in out if l.startswith('git-data sig=')][0])
            self.git('commit', '-q', '--allow-empty', '-m', 'Empty')     # the status stays clean
        self.assertNotEqual(sigs[0], sigs[1])

    def test_a_stopped_extension_gets_no_old_answers(self):
        exts = self.ext(commands={'go': [['git-log 1000 0 0 0', None]]})
        out = self.run_editor(['cmd fake.go', 'wait-ext fake running', 'ext-set fake stop', 'wait 300',
                               'wait-git', 'print-git-data'], exts=exts, drop_waits=True)
        self.assertIn('git-data pending=0', out)

    def test_log_of_a_file_of_lines_and_of_the_history(self):
        path = (self.proj / 'a.txt').as_posix()
        exts = self.ext(commands={'go': [['git-log 10 0 0 5', 'a.txt'], [f'git-log 10 3 3 {len(path)}', path],
                                         ['git-log 1 0 0 0', None]]})
        self.run_cmd('go', exts=exts)
        (_, whole), (_, lines), (_, history) = self.replies()
        second, first = self.git('log', '--format=%H').split()
        stamp = self.git('log', '-1', '--format=%at').strip()
        self.assertEqual(whole, f'2\n{second} {first} {stamp} 3 10\nAdaThird line'
                                f'{first} - {self.git("log", "-1", "--format=%at", first).strip()} 3 5\nAdaFirst')
        self.assertEqual(lines.split('\n')[0], '1')
        self.assertTrue(lines.split('\n')[1].startswith(second + ' '))
        self.assertEqual(history.split('\n')[0], '1')

    def test_show_gives_a_file_at_a_revision(self):
        exts = self.ext(commands={'go': [['git-show HEAD~1 5', 'a.txt'], ['git-show nope 5', 'a.txt'],
                                         ['git-show -x 5', 'a.txt'], ['git-show HEAD 8', '../x.txt'],
                                         ['git-show HEAD 9', '/etc/hosts']]})
        self.run_cmd('go', exts=exts)
        got = self.replies()
        self.assertEqual(got[0], ('ok 1 24', 'hello world\nsecond line\n'))
        self.assertTrue(got[1][0].startswith('error 2 nofile'), got)
        self.assertTrue(got[2][0].startswith('error 3 syntax'), got)
        self.assertTrue(got[3][0].startswith('error 4 nofile'), got)
        self.assertTrue(got[4][0].startswith('error 5 nofile'), got)

    def test_diff_open_shows_two_revisions_in_rhuns_diff_view(self):
        exts = self.ext(commands={'go': [['git-diff-open HEAD~1 HEAD 5', 'a.txt']],
                                  'wt': [['git-diff-open HEAD~1 - 5', 'a.txt']]})
        first = self.git('rev-parse', '--short=7', 'HEAD~1').strip()
        second = self.git('rev-parse', '--short=7', 'HEAD').strip()
        out = self.run_cmd('go', ['print-tabs', 'print-doc', 'cmd fake.wt', 'wait 300', 'wait-git',
                                  'print-tabs'], exts=exts)
        self.assertIn(f'a.txt (HEAD~1..HEAD)', out[0])
        self.assertIn('@@ -1,2 +1,3 @@', out)
        self.assertIn('third line', out)
        self.assertIn('a.txt (HEAD~1..changes)', out[-1])
        self.assertEqual(self.replies()[0], ('ok 1', None))

    def test_without_the_feature_or_the_capability(self):
        exts = self.ext(hello='hello 1', commands={'go': [['git-repo', None]]})
        self.run_cmd('go', exts=exts)
        self.assertEqual(self.replies(), [('error 1 unknown no such request', None)])
        exts = self.ext(needs='documents = read', commands={'go': [['git-repo', None]]}, folder='noneeds')
        self.run_cmd('go', exts=exts)
        self.assertEqual(self.replies()[-1], ('error 1 needs git=read', None))

    def test_features_are_agreed(self):
        exts = self.ext(hello='hello 1 git-data nonsense', commands={'go': []})
        self.run_cmd('go', exts=exts)
        self.assertIn('< 0 features git-data', self.fake_log())

    def test_outside_a_repository(self):
        shutil.rmtree(self.proj / '.git')
        exts = self.ext(commands={'go': [['git-repo', None]]})
        self.run_cmd('go', exts=exts)
        self.assertEqual(self.replies(), [('error 1 nofile not in a Git repository', None)])

    def test_git_changed_after_a_save_and_a_commit(self):
        exts = self.ext(commands={'go': []})
        self.run_editor(['cmd fake.go', 'wait-ext fake running', 'wait 300', 'wait-git', 'wait 200',
                         'type x', 'key ctrl+s', 'wait 300', 'wait-git', 'wait 300'], exts=exts)
        log = self.fake_log()
        n = log.count('< 0 git changed')
        self.assertGreaterEqual(n, 1, log)
        # a commit made elsewhere while rhun runs moves HEAD
        later = subprocess.Popen(['sh', '-c', 'sleep 2; git commit -qam More'], cwd=self.proj, env=self.env)
        self.run_editor(['cmd fake.go', 'wait-ext fake running', 'wait 3500', 'wait-git', 'wait 300'],
                        exts=exts)
        later.wait()
        self.assertGreaterEqual(self.fake_log().count('< 0 git changed'), n + 1)

    @unittest.skipIf(os.name == 'nt', 'rhun:// links open folders on Linux and macOS here')
    def test_trust_pause_refuses_git_data(self):
        exts = self.ext(commands={'go': [['git-repo', None], ['git-blame $DOC', None]]})
        link = 'rhun://file' + urllib.parse.quote(self.proj.as_posix())
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', 'open ' + (self.proj / 'a.txt').as_posix(), 'cmd fake.go',
                                     'wait-ext fake running', 'wait 500', 'print-git', 'quit']) + '\n')
        result = subprocess.run([str(host.EXE), link, '--headless', '1000x600', '--scale', '1',
                                 '--extensions', str(exts), '--script', str(script)], env=self.env,
                                capture_output=True, timeout=60, cwd=self.work)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('git paused', result.stdout.decode())
        self.assertEqual([r for r, _ in self.replies()], ['error 1 refused git is paused in this folder',
                                                          'error 2 refused git is paused in this folder'])


class Menus(Base):
    """C2: menus on history and Source Control rows, with their targets and when-clause keys"""

    def test_commit_and_commit_file_menus(self):
        sha = self.git('rev-parse', 'HEAD').strip()
        out = self.run_editor(['wait-git', 'cmd git_history', 'wait-git', 'wait 200', 'click 200 118 right',
                               'wait 100', 'print-menu', 'print-scm-ext', 'print-context scmProvider',
                               'key Escape', 'click 200 118', 'wait-git', 'wait 200', 'click 700 202 right',
                               'wait 100', 'print-menu', 'print-scm-ext', 'print-context scmResourceStatus',
                               'menu-pick Open Changes', 'wait-git', 'print-tabs'], drop_waits=True)
        self.assertEqual(out[0], 'Copy Commit ID')
        self.assertIn('menu=history_commit commit ' + sha, out)
        self.assertIn('scmProvider=git', out)
        self.assertIn('Open Changes', out)
        self.assertIn('menu=history_file commit ' + sha + ' a.txt', out)
        self.assertIn('scmResourceStatus=M', out)
        self.assertIn('a.txt (' + sha[:7] + ')', out[-1])

    def test_changed_file_menu(self):
        (self.proj / 'a.txt').write_text('changed\n', encoding='utf-8')
        (self.proj / 'c.txt').write_text('new\n', encoding='utf-8')
        self.git('add', 'c.txt')
        out = self.run_editor(['wait-git', 'cmd git_history', 'wait-git', 'wait 200', 'click 700 314 right',
                               'wait 100', 'print-scm-ext', 'print-context scmResourceGroup', 'key Escape',
                               'click 700 378 right', 'wait 100', 'print-menu', 'print-scm-ext',
                               'print-context scmResourceGroup', 'menu-pick Open File', 'wait 100',
                               'print-tabs'], drop_waits=True)
        self.assertIn('menu=scm_resource resource staged c.txt', out)
        self.assertIn('scmResourceGroup=staged', out)
        self.assertIn('menu=scm_resource resource changes a.txt', out)
        self.assertIn('scmResourceGroup=changes', out)
        self.assertIn('Open File', out)
        self.assertTrue(out[-1].startswith('tabs=*a.txt'), out)     # it was open: shown again

    def test_git_trusted_key(self):
        out = self.run_editor(['wait-git', 'print-context gitTrusted'], drop_waits=True)
        self.assertIn('gitTrusted=true', out)


class QuickDiff(Base):
    """C3: a quick-diff provider's base text draws the gutter marks"""

    def provider(self, body='hello world\nold line\nthird line\n', **kw):
        answers = {'quickdiff': {'body': body}}
        return self.ext('qd', needs='', hello='hello 1 quickdiff', answers=answers,
                        ini='on = startup\n[provides]\nquickdiff = *.txt', **kw)

    def marks(self, out):
        return [l for l in out if l.startswith('marks ')]

    def test_a_file_outside_git_gets_the_providers_marks(self):
        shutil.rmtree(self.proj / '.git')
        out = self.run_editor(['wait-ext qd running', 'wait 500', 'print-git'], exts=self.provider(),
                              drop_waits=True)
        self.assertEqual(self.marks(out), ['marks .~..'])
        log = self.fake_log('qd')
        asks = [l for l in log if ' quickdiff ' in l]
        self.assertEqual(len(asks), 1, log)
        self.assertRegex(asks[0], r'^< \d+ quickdiff 1 0$')

    def test_saving_asks_again_and_an_empty_base_clears_the_marks(self):
        shutil.rmtree(self.proj / '.git')
        out = self.run_editor(['wait-ext qd running', 'wait 500', 'print-git', 'key ctrl+s', 'wait 500',
                               'print-git'], exts=self.provider(body=''), drop_waits=True)
        self.assertEqual(self.marks(out), [])
        self.assertEqual(len([l for l in self.fake_log('qd') if ' quickdiff ' in l]), 2)

    def test_rhuns_git_keeps_its_files(self):
        (self.proj / 'a.txt').write_text('hello world\nsecond line\nthird line\nfourth\n', encoding='utf-8')
        out = self.run_editor(['wait-ext qd running', 'wait-git', 'wait 500', 'print-git'], exts=self.provider(),
                              drop_waits=True)
        self.assertEqual(self.marks(out), ['marks ...+.'])
        self.assertEqual([l for l in self.fake_log('qd') if ' quickdiff ' in l], [])

    def test_refresh_asks_again(self):
        shutil.rmtree(self.proj / '.git')
        exts = self.provider(commands={'refresh': [['quickdiff-refresh 1', '-']],
                                       'one': [[f'quickdiff-refresh {len(str(self.proj / "a.txt"))}',
                                                str(self.proj / 'a.txt')]]})
        self.run_editor(['wait-ext qd running', 'wait 500', 'cmd qd.refresh', 'wait 500', 'cmd qd.one',
                         'wait 500'], exts=exts, drop_waits=True)
        self.assertEqual(len([l for l in self.fake_log('qd') if ' quickdiff ' in l]), 3)
        self.assertEqual([r for r, _ in self.replies('qd')][-2:], ['ok 1', 'ok 2'])

    def test_a_silent_provider_has_one_request_per_document(self):
        # review: every save added a request that never ended, until language queries had no room
        shutil.rmtree(self.proj / '.git')
        answers = {'quickdiff': {'never': True}}
        exts = self.ext('qd', needs='', hello='hello 1 quickdiff', answers=answers,
                        ini='on = startup\n[provides]\nquickdiff = *.txt')
        saves = []
        for _ in range(70):
            saves += ['type x', 'key ctrl+s', 'wait 20']
        out = self.run_editor(['wait-ext qd running', 'wait 300', *saves, 'wait 300', 'print-scm-ext'],
                              exts=exts, drop_waits=True)
        self.assertIn('quickdiff-pending=1', ' '.join(out))
        self.assertGreaterEqual(len([l for l in self.fake_log('qd') if l.startswith('< 0 cancel ')]), 60)

    def test_a_stopped_provider_takes_its_base_with_it(self):
        # review: a base stayed after its provider stopped
        shutil.rmtree(self.proj / '.git')
        out = self.run_editor(['wait-ext qd running', 'wait 500', 'print-git', 'ext-set qd stop', 'wait 500',
                               'print-git'], exts=self.provider(), drop_waits=True)
        self.assertEqual(self.marks(out), ['marks .~..'])

    def test_refresh_without_the_feature(self):
        exts = self.ext('qd', needs='', hello='hello 1', commands={'refresh': [['quickdiff-refresh 1', '-']]})
        self.run_editor(['cmd qd.refresh', 'wait-ext qd running', 'wait 500'], exts=exts, drop_waits=True)
        self.assertEqual(self.replies('qd'), [('error 1 unknown no such request', None)])


def act(icon, name, args='', label=''):
    return f'action {icon} {name} {len(args.encode())} {len(label.encode())}\n{args}{label}'


def scm_body(status, placeholder, actions, groups):
    """an scm-update body: groups are (id, label, actions, resources), a resource (code, color, path,
    records)"""
    out = f'{len(status)} {len(placeholder)} {len(actions)} {len(groups)}\n{status}{placeholder}'
    out += ''.join(actions)
    for gid, label, gacts, res in groups:
        out += f'group {gid} {len(label)} {len(gacts)} {len(res)}\n{label}' + ''.join(gacts)
        for code, color, path, recs in res:
            out += f'res {code} {color} {len(path.encode())} {len(recs)}\n{path}' + ''.join(recs)
    return out


class ScmPanel(Base):
    """C4: a second version control system's panel, its colors and its quick-diff root"""

    def provider(self, body, root=None, extra=(), hello='hello 1 scm command-args'):
        root = str(root or self.proj)
        reg = f'{len(root.encode())} 9\n{root}Mercurial'
        cmds = {'start': [[f'scm-register {len(reg.encode())}', reg],
                          [f'scm-update $SCM {len(body.encode())}', body], *extra],
                'commit': [], 'open': [], 'stage': [], 'forget': [], 'input': [['scm-input $SCM', None]],
                'set': [['scm-input-set $SCM 5', 'hello']]}
        return self.ext('hg', needs='project = read', hello=hello, commands=cmds,
                        ini='[provides]\nscm = yes')

    def body(self):
        return scm_body('3 changes on default', 'Message (Ctrl+Enter to commit)',
                        [act('check', 'commit', 'go', 'Commit'), act('refresh', 'stage')],
                        [('changes', 'Changes', [act('plus', 'stage', 'all', 'Add All')],
                          [('M', 'modified', 'a.txt', ['command open 5\na.txt', act('plus', 'stage', 'a.txt', 'Add'),
                                                        act('minus', 'forget', 'a.txt', 'Forget')]),
                           ('?', 'untracked', 'src/new.txt', ['strike 0\n', 'tip 3\nnew']),
                           ('!', 'deleted', 'gone.txt', [])])])

    def start(self, exts, *actions):
        return self.run_editor(['cmd hg.start', 'wait-ext hg running', 'wait 400', *actions, 'print-scm-ext'],
                               exts=exts, drop_waits=True)

    def test_the_panel_shows_status_buttons_and_groups(self):
        out = self.start(self.provider(self.body()), 'cmd toggle_sidebar', 'wait 300', 'move 80 509', 'wait 700',
                         'print-tip')
        self.assertIn('tip=new', out)                               # src/new.txt's tip record
        line = [l for l in out if l.startswith('scm 1 rhun-tests/hg ')]
        self.assertEqual(line, [f'scm 1 rhun-tests/hg {self.proj.as_posix()} label=Mercurial '
                                'status=3 changes on default input= actions=Commit,Stage'], out)
        rows = [l for l in out if l.startswith('row ')]
        self.assertEqual(len(rows), 4, out)
        self.assertIn('label=Changes', rows[0])
        self.assertIn('badge=3', rows[0])
        self.assertIn('label=a.txt desc=M', rows[1])
        self.assertIn('label=new.txt desc=?  src', rows[2])
        self.assertEqual([r for r, _ in self.replies('hg')], ['ok 1 1', 'ok 2'])

    def test_clicks_buttons_and_menus_run_its_commands(self):
        out = self.start(self.provider(self.body()), 'scm-click 1 changes a.txt', 'wait 200', 'scm-action 1 0',
                         'wait 200', 'scm-menu 1 changes a.txt', 'print-menu', 'print-scm-ext',
                         'print-context scmProvider', 'print-context scmResourceStatus', 'menu-pick Forget', 'wait 200',
                         'scm-menu 1 changes', 'print-menu', 'menu-pick Add All', 'wait 200',
                         'scm-click 1 changes gone.txt', 'wait 200', 'print-tabs')
        self.assertIn('Add', out)
        self.assertIn('Forget', out)
        self.assertIn('Open File', out)
        self.assertIn('Add All', out)
        self.assertIn('menu=scm_resource resource changes a.txt', out)
        self.assertIn('scmProvider=rhun-tests/hg', out)
        self.assertIn('scmResourceStatus=M', out)
        self.assertIn('menu=scm_group group changes', out)
        log = self.fake_log('hg')
        # "< 0 run hg.NAME DOC ref LEN", then "| BODY"
        runs = [(l.split()[3], log[i + 1]) for i, l in enumerate(log) if l.startswith('< 0 run hg.') and ' ref ' in l]
        self.assertEqual(runs, [('hg.open', "| 'a.txt'"), ('hg.commit', "| 'go'"), ('hg.forget', "| 'a.txt'"),
                                ('hg.stage', "| 'all'")])
        tabs = [l for l in out if l.startswith('tabs=')]
        self.assertTrue(tabs[-1].endswith('*gone.txt'), out)     # a resource without a command opens its file

    def test_the_message_box(self):
        out = self.start(self.provider(self.body()), 'scm-focus 1', 'type fix it', 'cmd hg.input', 'wait 200',
                         'key ctrl+Return', 'wait 200', 'cmd hg.set', 'wait 200')
        self.assertIn(('ok 3 6', 'fix it'), self.replies('hg'))
        self.assertIn('input=hello', [l for l in out if l.startswith('scm 1 ')][0])
        log = self.fake_log('hg')
        # Ctrl+Enter in the message box runs the first button: Commit, its ARGS "go"
        self.assertIn(("< 0 run hg.commit 1 ref 2", "| 'go'"),
                      [(l, log[i + 1]) for i, l in enumerate(log) if l.startswith('< 0 run hg.commit')])

    def test_explorer_colors_and_letters(self):
        shutil.rmtree(self.proj / '.git')
        out = self.start(self.provider(self.body()), f'print-vcs {self.proj / "a.txt"}',
                         f'print-vcs {self.proj / "src/new.txt"}', f'print-vcs {self.proj / "src"}',
                         f'print-vcs {self.proj / "b.go"}')
        vcs = [l for l in out if l.startswith('vcs=')]
        self.assertTrue(vcs[0].startswith('vcs=M dir=0 color='), vcs)
        self.assertTrue(vcs[1].startswith('vcs=? dir=0 color='), vcs)
        self.assertTrue(vcs[2].startswith('vcs=? dir=1 color='), vcs)
        self.assertEqual(vcs[3], 'vcs=- dir=0 color=000000')
        self.assertNotEqual(vcs[0].split('color=')[1], vcs[1].split('color=')[1])

    def test_a_registered_root_takes_quick_diff_inside_git(self):
        reg = f'{len(str(self.proj).encode())} 2\n{self.proj}hg'
        exts = self.ext('hg', needs='project = read', hello='hello 1 scm quickdiff',
                        ini='on = startup\n[provides]\nscm = yes\nquickdiff = *.txt',
                        answers={'quickdiff': {'body': 'hello world\nold line\nthird line\n'}},
                        events={'0 ready': [[f'scm-register {len(reg.encode())}', reg]]})
        out = self.run_editor(['wait-ext hg running', 'wait 500', 'cmd save', 'wait 500', 'print-git'],
                              exts=exts, drop_waits=True)
        self.assertIn('marks .~..', out)

    def test_stopping_removes_its_panels(self):
        out = self.start(self.provider(self.body()), 'ext-set hg stop', 'wait 400')
        self.assertFalse([l for l in out if l.startswith('scm 1 ')], out)

    def test_bad_updates_and_handles(self):
        bad = '1 0 0 1\nxgroup g 1 0 1\nGres M nocolor 1 0\na'
        exts = self.provider(self.body(), extra=[[f'scm-update $SCM {len(bad)}', bad], ['scm-input 99', None]])
        out = self.start(exts)
        got = [r for r, _ in self.replies('hg')]
        self.assertTrue(got[2].startswith('error 3 syntax'), got)
        self.assertEqual(got[3], 'error 4 refused no such provider')
        self.assertIn('label=a.txt desc=M', ' '.join(out))       # the bad update changed nothing
        n = len(got)                                                # the log goes on in the same folder
        exts = self.provider(self.body(), hello='hello 1')
        self.start(exts)
        self.assertTrue(self.replies('hg')[n][0].startswith('error 1 unknown'), self.replies('hg'))


class CommitMessage(Base):
    """C2: a commit-message extension beside the built-in providers"""

    def setUp(self):
        super().setUp()
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[git]\ncommit_ai = ext:rhun-tests/writer\n')
        (self.proj / 'a.txt').write_text('hello world\nsecond line\nthird line\nfourth line\n', encoding='utf-8')
        self.git('add', 'a.txt')

    def writer(self, **answer):
        return self.ext('writer', needs='', hello='hello 1 commit-message',
                        ini='\n[provides]\ncommit_message = yes', answers={'commit-message': answer})

    def generate(self, exts, *more):
        return self.run_editor(['wait-git', 'cmd git_history', 'wait-git', 'cmd git_generate_message', *more,
                                'wait-ai', 'print-scm', 'print-ai', 'print-scm-ext'], exts=exts, drop_waits=True)

    def test_generate_asks_the_extension_with_the_staged_diff(self):
        out = self.generate(self.writer(body='Add a fourth line\n\nIt was missing.'))
        self.assertIn('message=Add a fourth line||It was missing.', out)
        self.assertIn('Ready. Review the generated message before committing.', out)
        self.assertIn('commit-provider=rhun-tests/writer asked=0 quickdiff-pending=0', out)
        log = self.fake_log('writer')
        request = [l for l in log if ' commit-message ' in l]
        self.assertEqual(len(request), 1, log)
        body = eval(log[log.index(request[0]) + 1][2:])
        head, rest = body.split('\n', 1)
        bl, dl = map(int, head.split())
        self.assertEqual(rest[:bl], 'main')
        self.assertEqual(len(rest[bl:].encode()), dl)
        self.assertIn('+fourth line', rest[bl:])
        self.assertIn('a.txt', rest[bl:])

    def test_cancel_sends_cancel_and_keeps_the_draft(self):
        out = self.generate(self.writer(body='Too late', delay=3), 'wait 1500', 'cmd git_generate_message')
        self.assertIn('Cancelled. Your draft was kept.', out)
        self.assertNotIn('message=Too late', out)
        self.assertTrue(any(l.startswith('< 0 cancel ') for l in self.fake_log('writer')), self.fake_log('writer'))

    def test_an_error_is_shown(self):
        out = self.generate(self.writer(error='refused no model is configured'))
        self.assertIn('Writer: refused no model is configured', out)

    def test_control_characters_are_refused(self):
        out = self.generate(self.writer(body='\x1b[31mred'))
        self.assertIn('The extension returned an empty, oversized or invalid message. Your draft was kept.', out)

    def test_an_extension_without_the_feature(self):
        exts = self.ext('writer', needs='', hello='hello 1', ini='\n[provides]\ncommit_message = yes')
        out = self.generate(exts)
        self.assertIn('The extension does not provide commit messages (it did not agree commit-message).', out)

    def test_settings_lists_it_and_saves_its_name(self):
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text().replace('commit_ai = ext:rhun-tests/writer\n', ''))
        exts = self.writer(body='x')
        out = self.run_editor(['cmd settings', 'wait 200', 'type message ai', 'wait 200', 'click 812 348',
                               'wait 200', 'print-scm-ext', 'print-ai'], exts=exts, drop_waits=True)
        self.assertIn('commit-provider=rhun-tests/writer asked=0 quickdiff-pending=0', out)
        self.assertIn('An extension writes the messages.', out)
        self.assertIn('commit_ai = ext:rhun-tests/writer', config.read_text())

    def test_a_missing_extension_is_named(self):
        out = self.generate(self.work / 'none')
        self.assertIn('The selected commit message extension is not installed.', out)
        self.assertIn('commit-provider=rhun-tests/writer asked=0 quickdiff-pending=0', out)


if __name__ == '__main__':
    unittest.main()
