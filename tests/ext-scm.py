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
        self.assertIn('commit-provider=rhun-tests/writer asked=0', out)
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

    def test_a_missing_extension_is_named(self):
        out = self.generate(self.work / 'none')
        self.assertIn('The selected commit message extension is not installed.', out)
        self.assertIn('commit-provider=rhun-tests/writer asked=0', out)


if __name__ == '__main__':
    unittest.main()
