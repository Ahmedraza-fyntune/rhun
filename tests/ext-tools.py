#!/usr/bin/env python3
"""Tools (feature tools, wider-parity D3): the list of rhun's own tools and the extensions' [tools],
calls routed to a tool's extension (started when idle) and answered back, the user's confirmation
for tools that change anything (Allow once, Allow for this session, Deny), and the rhun.* tools.
Both extensions are Python programs; nothing talks to a real agent."""
import json
import unittest

host = __import__('ext-host')

OWNER = r'''import os, sys
from pathlib import Path
log = Path(os.environ['RHUN_STATE']) / 'owner.log'
out = sys.stdout.buffer
inp = sys.stdin.buffer
out.write(b'hello 1 tools\n'); out.flush()
while True:
    line = inp.readline()
    if not line:
        break
    f = line.decode().rstrip('\n').split(' ')
    body = b''
    if len(f) == 5 and f[1] == 'tool':
        body = inp.read(int(f[4]))
    with log.open('a') as g:
        g.write(line.decode() + (body.decode() + '\n' if body else ''))
    if len(f) == 5 and f[1] == 'tool':
        if body == b'fail':
            out.write(f'error {f[0]} refused nothing found\n'.encode())
        else:
            ans = f'{f[2]} for {f[3]}: '.encode() + body
            out.write(f'ok {f[0]} {len(ans)}\n'.encode() + ans)
        out.flush()
    elif f[0] == '0' and f[1] == 'bye':
        break
'''

CALLER = r'''import os, sys
from pathlib import Path
log = Path(os.environ['RHUN_STATE']) / 'caller.log'
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = 1
verbs = {}
docs = {}
def send(line, body=b''):
    out.write(line.encode() + b'\n' + body); out.flush()
def request(text, body=None):
    global next_id
    i = next_id
    next_id += 1
    verbs[i] = text.split(' ')[0]
    if body is None:
        send(f'{i} {text}')
    else:
        send(f'{i} {text} {len(body)}', body)
    return i
def call(tool, body):
    if isinstance(body, str):
        body = body.encode()
    return request('tool-call ' + tool, body)
def note(text):
    with log.open('a') as g:
        g.write(text + '\n')
send(HELLO)
project = '-'
last = 0
while True:
    line = inp.readline()
    if not line:
        break
    f = line.decode().rstrip('\n').split(' ')
    if f[0] == 'ok' and len(f) == 3 and verbs.get(int(f[1])) in ('tools', 'tool-call'):
        body = inp.read(int(f[2]))
        note(f'ok {f[1]} ' + body.decode(errors='replace').replace('\n', '|'))
        continue
    note(line.decode().rstrip('\n'))
    if f[0] == '0' and f[1] == 'ready':
        project = ' '.join(f[2:])
    elif f[0] == '0' and f[1] == 'opened':
        docs[f[5] if len(f) > 5 else ''] = (int(f[2]), int(f[3]))
    elif f[0] == '0' and f[1] == 'run':
        name = f[2].split('.', 1)[1]
        a = os.path.join(project, 'a.txt')
        if name == 'list':
            request('tools')
        elif name == 'search':
            call('acme/docs.search', 'how to fold')
        elif name == 'fail':
            call('acme/docs.search', 'fail')
        elif name == 'write':
            last = call('acme/docs.write', 'note one\nsecond line')
        elif name == 'cancel':
            request(f'cancel {last}')
        elif name == 'nosuch':
            call('acme/docs.nosuch', '')
            call('rhun.nosuch', '')
        elif name == 'editors':
            call('rhun.editors', '')
        elif name == 'selection':
            call('rhun.selection', '')
        elif name == 'read':
            call('rhun.read', f'path {a}\n')
            call('rhun.read', 'path b.go')
            call('rhun.read', f'path {a}\nfrom 2\nto 2\n')
            call('rhun.read', 'doc 999')
            call('rhun.read', 'path /etc/hosts')
        elif name == 'diag':
            doc, version = docs[a]
            m = b'1 1 1 6 warning loud greeting\n'
            request(f'diagnostics {doc} {version} 1', m)
            call('rhun.diagnostics', '')
        elif name == 'open':
            call('rhun.open', 'path b.go\nline 1\ncol 5\n')
        elif name == 'propose':
            t = b'package b\n\nfunc New() {}\n'
            call('rhun.propose', b'path b.go\nlabel Add New\ntext ' + str(len(t)).encode() + b'\n' + t)
        elif name == 'run':
            call('rhun.run', 'command echo tool-ran-ok')
    elif f[0] == '0' and f[1] == 'bye':
        break
'''


class Tools(unittest.TestCase):
    setUp = host.Host.setUp
    tearDown = host.Host.tearDown
    run_editor = host.Host.run_editor

    def extensions(self, hello='hello 1 tools edit-review', needs='documents = read\nproject = read\nterminal = yes\n'):
        root = self.work / 'tools-exts'
        owner = root / 'acme' / 'docs'
        owner.mkdir(parents=True, exist_ok=True)
        (owner / 'extension.ini').write_text(
            'name = docs\nowner = acme\ntitle = Docs\nversion = 1\nprotocol = 1\n'
            'runtime = python3\nrun = main.py\non = command\n[commands]\nnothing = Nothing\n'
            '[tools]\n# a search\nsearch = Search Docs | Searches the documentation\n'
            'search.input = query=TEXT\nsearch.readonly = yes\nwrite = Write Note | Writes a note\n')
        (owner / 'main.py').write_text(OWNER)
        caller = root / 'acme' / 'agent'
        caller.mkdir(parents=True, exist_ok=True)
        cmds = 'list search fail write cancel nosuch editors selection read diag open propose run'.split()
        (caller / 'extension.ini').write_text(
            'name = agent\nowner = acme\ntitle = Agent\nversion = 1\nprotocol = 1\n'
            'runtime = python3\nrun = main.py\n[commands]\n' + ''.join(f'{c} = {c}\n' for c in cmds)
            + '[subscribe]\nopened = *\n[needs]\n' + needs)
        (caller / 'main.py').write_text(f'HELLO = {json.dumps(hello)}\n' + CALLER)
        return root

    def caller_log(self):
        p = self.work / 'state/rhun/extensions/acme--agent/caller.log'
        return p.read_text().splitlines() if p.exists() else []

    def owner_log(self):
        p = self.work / 'state/rhun/extensions/acme--docs/owner.log'
        return p.read_text().splitlines() if p.exists() else []

    def answers(self):
        return [l for l in self.caller_log() if l.startswith('ok ') or l.startswith('error ')]

    def go(self, actions, **kw):
        return self.run_editor(exts=self.extensions(**kw), drop_waits=True,
                               actions=['wait-ext acme/agent running', 'wait 200'] + actions)

    def test_the_list_has_rhuns_tools_and_the_extensions(self):
        self.go(['cmd acme/agent.list', 'wait 300'])
        listing = self.answers()[0].split('|')
        self.assertEqual(listing[0], 'ok 1 9')
        self.assertTrue(listing[1].startswith('rhun.editors ro 12 '), listing)
        self.assertIn('rhun.propose rw', '|'.join(listing))
        self.assertIn('rhun.run rw', '|'.join(listing))
        self.assertIn('acme/docs.search ro 11 26 10', '|'.join(listing))
        self.assertIn('Search DocsSearches the documentationquery=TEXT', '|'.join(listing))
        self.assertIn('acme/docs.write rw 10 13 0', '|'.join(listing))

    def test_a_readonly_tool_starts_its_extension_and_answers(self):
        self.go(['cmd acme/agent.search', 'wait 500', 'wait 500'])
        self.assertIn('ok 1 search for acme/agent: how to fold', self.answers())
        self.assertIn('1 tool search acme/agent 11', self.owner_log())

    def test_a_tool_error_comes_back(self):
        self.go(['cmd acme/agent.fail', 'wait 500', 'wait 500'])
        self.assertIn('error 1 refused nothing found', self.answers())

    def test_a_changing_tool_asks_and_deny_refuses(self):
        out = self.go(['cmd acme/agent.write', 'wait 300', 'print-dialog', 'tool-confirm deny', 'wait 300',
                       'print-dialog'])
        self.assertEqual(out[:3], ['dialog=Allow Agent to use acme/docs.write?',
                                   'text=Write Note: note one', 'button=Allow once'])
        self.assertEqual(out[3], 'dialog=none')
        self.assertIn('error 1 refused denied by the user', self.answers())
        self.assertEqual(self.owner_log(), [])

    def test_allow_once_asks_again_allow_for_the_session_does_not(self):
        out = self.go(['cmd acme/agent.write', 'wait 300', 'tool-confirm once', 'wait 500', 'wait 300',
                       'cmd acme/agent.write', 'wait 300', 'print-dialog', 'tool-confirm session', 'wait 300',
                       'cmd acme/agent.write', 'wait 300', 'print-dialog', 'wait 300'])
        self.assertEqual(out[0], 'dialog=Allow Agent to use acme/docs.write?')
        self.assertEqual(out[3], 'dialog=none')
        self.assertEqual([a for a in self.answers() if a.startswith('ok ')],
                         ['ok 1 write for acme/agent: note one|second line',
                          'ok 2 write for acme/agent: note one|second line',
                          'ok 3 write for acme/agent: note one|second line'])

    def test_a_call_waiting_for_the_user_can_be_cancelled(self):
        out = self.go(['cmd acme/agent.write', 'wait 300', 'cmd acme/agent.cancel', 'wait 300', 'print-dialog',
                       'print-tools'])
        self.assertIn('dialog=none', out)
        self.assertIn('error 1 cancelled', self.answers())
        self.assertIn('ok 2', self.caller_log())
        self.assertFalse(any(l.startswith('call ') for l in out), out)

    def test_calls_for_a_tool_whose_extension_stops_fail(self):
        # Codex review: a call waiting for the user's answer when its tool's extension stops is
        # answered cancelled and its dialog closes; one queued behind it too
        out = self.go(['cmd acme/agent.search', 'wait 500', 'wait 500', 'cmd acme/agent.write', 'wait 300',
                       'cmd acme/agent.write', 'wait 300', 'print-dialog', 'ext-set acme/docs stop',
                       'wait 1000', 'print-dialog', 'print-tools'])
        self.assertEqual(out[0], 'dialog=Allow Agent to use acme/docs.write?')
        self.assertIn('dialog=none', out)
        self.assertIn('error 2 cancelled the tool\'s extension stopped', self.answers())
        self.assertIn('error 3 cancelled the tool\'s extension stopped', self.answers())
        self.assertFalse(any(l.startswith('call ') for l in out), out)

    def test_unknown_tools(self):
        self.go(['cmd acme/agent.nosuch', 'wait 300'])
        self.assertEqual(self.answers(), ['error 1 refused no such tool', 'error 2 refused no such tool'])

    def test_rhun_editors_and_selection(self):
        a = (self.proj / 'a.txt').as_posix()
        self.go(['open ' + a, 'key shift+Right', 'key shift+Right', 'cmd acme/agent.editors',
                 'cmd acme/agent.selection', 'wait 300'])
        answers = self.answers()
        self.assertEqual(answers[0], f'ok 1 1 0 - {a}|active 1|')
        self.assertEqual(answers[1], 'ok 2 1 1 1 1 3|he')

    def test_rhun_read(self):
        a = (self.proj / 'a.txt').as_posix()
        self.go(['open ' + a, 'type X', 'cmd acme/agent.read', 'wait 300'])
        self.assertEqual(self.answers(), [
            'ok 1 Xhello world|second line|',
            'ok 2 package b|',
            'ok 3 second line|',
            'error 4 nodoc no such document',
            'error 5 needs file=read'])

    def test_rhun_diagnostics(self):
        a = (self.proj / 'a.txt').as_posix()
        self.go(['cmd acme/agent.diag', 'wait 300'])
        self.assertIn(f'ok 2 {a} 1 1 1 6 warning acme/agent loud greeting|', self.answers())

    def test_rhun_open(self):
        out = self.go(['cmd acme/agent.open', 'wait 300', 'print-tabs', 'print-cursor'])
        self.assertTrue(any(a.startswith('ok 1 ') for a in self.answers()), self.answers())
        self.assertTrue(any('b.go' in l for l in out if l.startswith('tabs=')), out)

    def test_rhun_propose_answers_after_the_review(self):
        out = self.go(['cmd acme/agent.propose', 'wait 300', 'print-review', 'review accept all', 'wait 300'])
        self.assertIn('proposal=1 label=Add New done=0', out)
        self.assertIn('ok 1 accepted 1 rejected 0', self.answers())

    def test_rhun_run_waits_for_enter(self):
        out = self.go(['cmd acme/agent.run', 'wait 300', 'print-palette', 'wait 600', 'key Return',
                       'wait-term tool-ran-ok', 'wait 300'])
        self.assertEqual(out[:2], ['prompt=Run in the terminal: Enter, or Esc', 'field=echo tool-ran-ok'])
        self.assertIn('ok 1 ok', self.answers())

    def test_rhun_run_escape_cancels(self):
        self.go(['cmd acme/agent.run', 'wait 300', 'key Escape', 'wait 300'])
        self.assertIn('error 1 cancelled', self.answers())

    def test_capabilities_and_feature(self):
        self.go(['cmd acme/agent.editors', 'cmd acme/agent.run', 'wait 300'], needs='project = read\n')
        self.assertEqual(self.answers(), ['error 1 needs documents=read', 'error 2 needs terminal=yes'])
        import shutil
        shutil.rmtree(self.work / 'tools-exts')
        (self.work / 'state/rhun/extensions/acme--agent/caller.log').unlink()
        self.go(['cmd acme/agent.list', 'wait 300'], hello='hello 1')
        self.assertEqual(self.answers(), ['error 1 unknown no such request'])


if __name__ == '__main__':
    unittest.main()
