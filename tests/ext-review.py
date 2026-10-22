#!/usr/bin/env python3
"""Edit proposals and the Review tab (feature edit-review, wider-parity D2 and D2b): a proposal is
checked as apply is and answered at once; the user accepts or rejects files and hunks; accepted
changes are applied unsaved as one undo step per decision; a file changed since it was proposed is
not touched; the proposer hears every file's outcome. The proposer is a Python program."""
import json
import unittest

host = __import__('ext-host')

C_TXT = ''.join(f'line {i}\n' for i in range(1, 13))

PROGRAM = r'''import os, sys
from pathlib import Path
log = Path(os.environ['RHUN_STATE']) / 'review.log'
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = 1
project = '-'
def send(line, body=b''):
    out.write(line.encode() + b'\n' + body)
    out.flush()
def request(text, body=None):
    global next_id
    i = next_id
    next_id += 1
    if body is None:
        send(f'{i} {text}')
    else:
        send(f'{i} {text} {len(body)}', body)
def group(path, version, edits):
    p = path.encode()
    b = f'{len(p)} {version} {len(edits)}\n'.encode() + p
    for (l1, c1, l2, c2, text) in edits:
        t = text.encode()
        b += f'{l1} {c1} {l2} {c2} {len(t)}\n'.encode() + t
    return b
def propose(label, sid, groups):
    l, s = label.encode(), sid.encode()
    body = f'{len(l)} {len(s)}\n'.encode() + l + s + f'{len(groups)}\n'.encode() + b''.join(groups)
    request('propose', body)
send(HELLO)
while True:
    line = inp.readline()
    if not line:
        break
    with log.open('a') as f:
        f.write(line.decode(errors='replace'))
    f = line.decode().rstrip('\n').split(' ')
    if f[0] == '0' and f[1] == 'ready':
        project = ' '.join(f[2:])
    elif f[0] == '0' and f[1] == 'run':
        name = f[2].split('.', 1)[1]
        a, b, c = (os.path.join(project, n) for n in ('a.txt', 'b.go', 'c.txt'))
        if name == 'propose':
            propose('Rename things', 's1', [
                group(c, '-', [(2, 1, 2, 7, 'LINE 2'), (10, 6, 10, 8, '10 and more\nnew line')]),
                group(b, '-', [(1, 9, 1, 10, 'beta')])])
        elif name == 'longer':
            propose('Longer', '', [
                group(c, '-', [(2, 1, 2, 7, 'LONG LINE 2'), (10, 6, 10, 8, '10 and more\nnew line')])])
        elif name == 'many':
            for i in range(9):
                propose(f'p{i}', '', [group(c, '-', [(1, 1, 1, 1, f'{i}')])])
        elif name == 'bad':
            propose('x', '', [group('relative.txt', '-', [(1, 1, 1, 1, 'x')])])
            propose('x', '', [group('/etc/hosts', '-', [(1, 1, 1, 1, 'x')])])
            propose('x', '', [group(c, '-', [(99, 1, 99, 1, 'x')])])
            propose('x', '', [group(c, '-', [(1, 1, 1, 5, 'x'), (1, 3, 1, 6, 'y')])])
            propose('x', '', [group(c, '-', [(1, 1, 1, 5, 'line')])])
            propose('x', '', [group(c, '-', [(1, 1, 1, 1, 'x')]), group(c, '-', [(2, 1, 2, 1, 'y')])])
            propose('x', 'a b', [group(c, '-', [(1, 1, 1, 1, 'x')])])
            propose('x', '', [group('#999', '3', [(1, 1, 1, 1, 'x')])])
            propose('x', '', [group(a, '999', [(1, 1, 1, 1, 'x')])])
            request('unpropose 77')
        elif name == 'open':
            propose('Open doc', '', [group(a, OPEN_VERSION, [(1, 1, 1, 6, 'HELLO')])])
        elif name == 'withdraw':
            request('unpropose 1')
    elif f[0] == '0' and f[1] == 'bye':
        break
'''


class Review(unittest.TestCase):
    setUp = host.Host.setUp
    tearDown = host.Host.tearDown
    run_editor = host.Host.run_editor

    def extension(self, hello='hello 1 edit-review', needs='documents = read\nproject = read\n', version='-'):
        (self.proj / 'c.txt').write_text(C_TXT)
        root = self.work / 'review-exts'
        folder = root / 'acme' / 'prop'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'extension.ini').write_text(
            'name = prop\nowner = acme\ntitle = Proposer\nversion = 1\nprotocol = 1\n'
            'runtime = python3\nrun = main.py\n[commands]\npropose = Propose\nmany = Many\nbad = Bad\nlonger = Longer\n'
            'open = Open\nwithdraw = Withdraw\n[needs]\n' + needs)
        (folder / 'main.py').write_text(f'HELLO = {json.dumps(hello)}\nOPEN_VERSION = {json.dumps(version)}\n'
                                        + PROGRAM)
        return root

    def plog(self):
        p = self.work / 'state/rhun/extensions/acme--prop/review.log'
        return p.read_text().splitlines() if p.exists() else []

    def events(self):
        return [l for l in self.plog() if l.startswith('0 proposal ')]

    def go(self, actions, **kw):
        return self.run_editor(exts=self.extension(**kw), drop_waits=True,
                               actions=['wait-ext acme/prop running', 'wait 200'] + actions)

    def test_a_proposal_is_answered_at_once_and_shown(self):
        out = self.go(['cmd acme/prop.propose', 'wait 300', 'print-review', 'print-tabs'])
        self.assertIn('ok 1 1', self.plog())
        self.assertEqual(out[:6], [
            'proposal=1 label=Rename things done=0',
            'proposal=1 file=1 path=c.txt +3 -2 state=pending',
            '  hunk=1 -2,1 +2,1 state=pending',
            '  hunk=2 -10,1 +10,2 state=pending',
            'proposal=1 file=2 path=b.go +1 -1 state=pending',
            '  hunk=1 -1,1 +1,1 state=pending'])
        self.assertIn('Review: Rename things', out[6])
        self.assertEqual((self.proj / 'c.txt').read_text(), C_TXT)

    def test_accept_all_applies_unsaved_and_reports(self):
        out = self.go(['cmd acme/prop.propose', 'wait 300', 'review accept all', 'wait 200',
                       'print-review', 'open ' + (self.proj / 'c.txt').as_posix(), 'print-doc', 'print-tabs',
                       'open ' + (self.proj / 'b.go').as_posix(), 'print-doc'])
        self.assertIn('package beta', out)
        self.assertEqual(self.events(), ['0 proposal 1 1 accepted', '0 proposal 1 2 accepted',
                                         '0 proposal 1 done 2 0'])
        self.assertIn('proposal=1 label=Rename things done=1', out)
        doc = '\n'.join(out)
        self.assertIn('LINE 2\nline 3', doc)
        self.assertIn('line 10 and more\nnew line\nline 11', doc)
        self.assertEqual((self.proj / 'c.txt').read_text(), C_TXT)    # unsaved: the user saves
        self.assertTrue(any('c.txt' in l and 'b.go' in l for l in out if l.startswith('tabs=')), out)
        self.assertEqual((self.proj / 'b.go').read_text(), 'package b\n')

    def test_hunks_accepted_together_refer_to_the_same_text(self):
        # the first hunk grows the text: the second must still land on line 10 (Codex review)
        c = (self.proj / 'c.txt').as_posix()
        out = self.go(['cmd acme/prop.longer', 'wait 300', 'review accept 1', 'wait 200', 'open ' + c,
                       'print-doc'])
        want = C_TXT.replace('line 2\n', 'LONG LINE 2\n').replace('line 10\n', 'line 10 and more\nnew line\n')
        self.assertEqual('\n'.join(out[out.index('<eod>') - 14:out.index('<eod>')]), want)
        self.assertEqual(self.events(), ['0 proposal 1 1 accepted', '0 proposal 1 done 1 0'])

    def test_git_open_changes_with_a_review_tab_open(self):
        # Git: Open Changes looks through the diff views; a Review tab has no file (Codex review)
        import subprocess
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text().replace('[git]\nenabled = false\n', '[git]\nenabled = true\n'))
        subprocess.run(['git', 'init', '-q', str(self.proj)], check=True, env=self.env)
        c = (self.proj / 'c.txt').as_posix()
        out = self.go(['cmd acme/prop.propose', 'wait 300', 'open ' + c, 'cmd git_changes', 'wait 300',
                       'print-tabs'])
        self.assertTrue(any('Review: Rename things' in l for l in out), out)

    def test_hunks_are_decided_one_by_one(self):
        out = self.go(['cmd acme/prop.propose', 'wait 300', 'review accept 1 2', 'review reject 1 1',
                       'review reject 2', 'wait 200', 'print-review',
                       'open ' + (self.proj / 'c.txt').as_posix(), 'print-doc'])
        self.assertEqual(self.events(), ['0 proposal 1 1 partial 1 2', '0 proposal 1 2 rejected',
                                         '0 proposal 1 done 1 1'])
        self.assertIn('proposal=1 file=1 path=c.txt +3 -2 state=partial', out)
        self.assertIn('  hunk=1 -2,1 +2,1 state=rejected', out)
        self.assertIn('  hunk=2 -10,1 +10,2 state=accepted', out)
        doc = '\n'.join(out)
        self.assertIn('line 2\nline 3', doc)
        self.assertIn('line 10 and more\nnew line', doc)

    def test_review_keys(self):
        # the cursor starts on the first file: A accepts its hunk under the cursor (the first), ] goes to
        # the next file, r rejects it, a accepts what is left of the first, Ctrl+Enter accepts the rest
        out = self.go(['cmd acme/prop.propose', 'wait 300', 'type A', 'type ]', 'type r', 'type [',
                       'type a', 'wait 200', 'print-review'])
        self.assertIn('proposal=1 file=1 path=c.txt +3 -2 state=accepted', out)
        self.assertIn('proposal=1 file=2 path=b.go +1 -1 state=rejected', out)
        self.assertEqual(self.events()[-1], '0 proposal 1 done 1 1')

    def test_buttons(self):
        # in a 1000x600 window: b.go's Reject, the second hunk's Accept, then Accept all
        out = self.go(['cmd acme/prop.propose', 'wait 300', 'click 953 485', 'wait 100', 'click 895 297',
                       'wait 100', 'click 860 86', 'wait 200', 'print-review'])
        self.assertIn('proposal=1 file=2 path=b.go +1 -1 state=rejected', out)
        self.assertIn('proposal=1 file=1 path=c.txt +3 -2 state=accepted', out)

    def test_an_accepted_file_is_one_undo_step(self):
        c = (self.proj / 'c.txt').as_posix()
        out = self.go(['cmd acme/prop.propose', 'wait 300', 'review accept 1', 'wait 100', 'open ' + c,
                       'cmd undo', 'print-doc'])
        self.assertEqual('\n'.join(out[out.index('<eod>') - 13:out.index('<eod>')]), C_TXT)

    def test_ctrl_enter_accepts_everything(self):
        out = self.go(['cmd acme/prop.propose', 'wait 300', 'key ctrl+Return', 'wait 200', 'print-review'])
        self.assertEqual(self.events()[-1], '0 proposal 1 done 2 0')

    def test_a_file_changed_since_is_not_touched(self):
        c = (self.proj / 'c.txt').as_posix()
        out = self.go(['open ' + c, 'cmd acme/prop.propose', 'wait 300', 'open ' + c, 'type X',
                       'review accept all', 'wait 200', 'print-review', 'open ' + c, 'print-doc'])
        self.assertEqual(self.events(), ['0 proposal 1 1 stale', '0 proposal 1 2 accepted',
                                         '0 proposal 1 done 1 1'])
        self.assertIn('proposal=1 file=1 path=c.txt +3 -2 state=stale', out)
        doc = '\n'.join(out)
        self.assertIn('Xline 1\nline 2\n', doc)

    def test_closing_the_tab_rejects_what_is_left(self):
        self.go(['cmd acme/prop.propose', 'wait 300', 'review accept 2', 'cmd close_tab', 'wait 200',
                 'print-review'])
        self.assertEqual(self.events(), ['0 proposal 1 2 accepted', '0 proposal 1 1 rejected',
                                         '0 proposal 1 done 1 1'])

    def test_withdrawn_proposals_close_quietly(self):
        out = self.go(['cmd acme/prop.propose', 'wait 300', 'cmd acme/prop.withdraw', 'wait 300',
                       'print-review', 'print-tabs'])
        self.assertNotIn('Review', '\n'.join(out))
        self.assertEqual(self.events(), [])
        self.assertIn('ok 2', self.plog())

    def test_open_document_at_its_version(self):
        out = self.go(['cmd acme/prop.open', 'wait 300', 'print-review'], version='77')
        self.assertTrue(any(l.startswith('error 1 stale') for l in self.plog()), self.plog())
        self.assertEqual(out, [])

    def test_eight_proposals_wait_at_most(self):
        self.go(['cmd acme/prop.many', 'wait 500'])
        oks = [l for l in self.plog() if l.startswith('ok ')]
        self.assertEqual(len(oks), 8)
        self.assertIn('error 9 toobig 8 proposals are waiting for the user', self.plog())

    def test_bad_proposals_change_nothing(self):
        out = self.go(['cmd acme/prop.bad', 'wait 500', 'print-review'])
        errors = [l for l in self.plog() if l.startswith('error ')]
        self.assertEqual(errors, [
            'error 1 nofile no such text file',
            'error 2 needs file=read',
            'error 3 badpos a position is outside the text or inside a character',
            'error 4 badpos two edits overlap',
            'error 5 refused the edit changes nothing',
            'error 6 syntax a file appears twice',
            'error 7 syntax the proposal cannot be read',
            'error 8 nodoc no such document',
            'error 9 stale the document changed since the edit was made',
            'error 10 refused no such proposal'])
        self.assertEqual(out, [])

    def test_feature_and_permission(self):
        self.go(['cmd acme/prop.propose', 'wait 300'], hello='hello 1')
        self.assertIn('error 1 unknown no such request', self.plog())
        import shutil
        shutil.rmtree(self.work / 'review-exts')
        (self.work / 'state/rhun/extensions/acme--prop/review.log').unlink()
        self.go(['cmd acme/prop.propose', 'wait 300'], needs='project = read\n')
        self.assertIn('error 1 needs documents=read', self.plog())


if __name__ == '__main__':
    unittest.main()
