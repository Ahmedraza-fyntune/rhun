#!/usr/bin/env python3
"""Agent sessions from extensions (feature agents, wider-parity D1): rows in the agents panel, their
transcripts asked for when a session opens, growth while it is open, and the rows going with their
extension. The fake source is a Python program; nothing talks to a real agent."""
import json
import unittest

host = __import__('ext-host')

PROGRAM = r'''import os, sys, time
from pathlib import Path
log = Path(os.environ['RHUN_STATE']) / 'agent.log'
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = 1
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
def row(updated, state, sid, title, model, cwd):
    s, t, m, c = (x.encode() for x in (sid, title, model, cwd))
    return f'{updated} {state} {len(s)} {len(t)} {len(m)} {len(c)}\n'.encode() + s + t + m + c
def msg(role, name, text, model=''):
    n, t, m = name.encode(), text.encode(), model.encode()
    return f'{role} {len(n)} {len(t)} {len(m)}\n'.encode() + n + t + m
messages = {
    's1': [msg('user', '', 'fix the bug'), msg('assistant', '', 'Looking at it', 'gemini-2.5-pro'),
           msg('tool', 'read_file', 'src/main.rs'), msg('result', '', 'fn main() {}')],
    's2': [msg('user', '', 'old question')],
}
now = int(time.time())
project = '-'
def rows():
    return (b'3\n' + row(now, 'working', 's1', 'Fix the bug\nsecond line', 'gemini-2.5-pro', project)
            + row(now - 7200, 'idle', 's2', 'Old talk', '', '')
            + row(now - 60, 'waiting', 's3', 'Elsewhere', '', '/somewhere/else'))
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
        request('agent-sessions', rows())
    elif f[0] == '0' and f[1] == 'run':
        name = f[2].split('.', 1)[1]
        if name == 'grow':
            messages['s1'].append(msg('assistant', '', 'Fixed it', 'gemini-2.5-pro'))
            messages['s1'].append(msg('error', '', 'quota reached'))
            n = len(messages['s1'])
            request(f'agent-changed s1 {n} {n - 2}')
        elif name == 'drop':
            now += 5
            request('agent-sessions', b'1\n' + row(now, 'idle', 's2', 'Old talk', '', ''))
        elif name == 'bad':
            request('agent-sessions', b'1\n12 idle 2 0 0 0\ns')
            request('agent-sessions', b'1\n12 sleeping 2 0 0 0\ns1')
            request('agent-sessions', b'2\n' + row(1, 'idle', 'x', '', '', '') + row(2, 'idle', 'x', '', '', ''))
            request('agent-sessions', b'1\n' + row(1, 'idle', 'a b', '', '', ''))
            request('agent-sessions', b'1\n' + row(1, 'idle', 'r', '', '', 'relative/dir'))
            request('agent-changed nosuch 1 0')
            request('agent-changed s1 x 0')
    elif len(f) > 2 and f[1] == 'agent-transcript':
        sid, frm = f[2], int(f[3])
        part = messages.get(sid, [])[frm:frm + PAGE]
        body = f'{len(messages.get(sid, []))} {len(part)}\n'.encode() + b''.join(part)
        send(f'ok {f[0]} {len(body)}', body)
    elif f[0] == '0' and f[1] == 'bye':
        break
'''


class Agents(unittest.TestCase):
    setUp = host.Host.setUp
    tearDown = host.Host.tearDown
    run_editor = host.Host.run_editor

    def extension(self, hello='hello 1 agents', provides=True, page=100):
        root = self.work / 'agents-exts'
        folder = root / 'acme' / 'gem'
        folder.mkdir(parents=True, exist_ok=True)
        ini = ('name = gem\nowner = acme\ntitle = Gem Bridge\nversion = 1\nprotocol = 1\n'
               'runtime = python3\nrun = main.py\n[commands]\ngrow = Grow\ndrop = Drop\nbad = Bad\n')
        if provides:
            ini += '[provides]\nagents = yes\nagents.title = Gemini CLI\n'
        (folder / 'extension.ini').write_text(ini)
        (folder / 'main.py').write_text(f'HELLO = {json.dumps(hello)}\nPAGE = {page}\n' + PROGRAM)
        return root

    def agent_log(self):
        p = self.work / 'state/rhun/extensions/acme--gem/agent.log'
        return p.read_text() if p.exists() else ''

    def rows(self, out):
        return [line for line in out if line.startswith('Gemini CLI')]

    def test_rows_join_the_panel_for_this_project(self):
        out = self.run_editor(exts=self.extension(), drop_waits=True, actions=[
            'wait-ext acme/gem running', 'wait 300', 'print-agents'])
        self.assertEqual(self.rows(out), ['Gemini CLI [model: gemini-2.5-pro]: Fix the bug',
                                          'Gemini CLI: Old talk'])
        self.assertNotIn('Elsewhere', '\n'.join(out))

    def test_opening_a_session_asks_for_its_transcript(self):
        out = self.run_editor(exts=self.extension(), drop_waits=True, actions=[
            'wait-ext acme/gem running', 'wait 300', 'print-agents 1', 'wait 300', 'print-agents'])
        thread = out[out.index('Gemini CLI: Old talk', 3) + 1:]
        self.assertEqual(thread, ['user fix the bug', 'agent(gemini-2.5-pro) Looking at it',
                                  'tool(read_file) src/main.rs', 'result fn main() {}'])
        self.assertIn('agent-transcript s1 0', self.agent_log())

    def test_transcripts_come_in_pages(self):
        out = self.run_editor(exts=self.extension(page=1), drop_waits=True, actions=[
            'wait-ext acme/gem running', 'wait 300', 'print-agents 1', 'wait 500', 'print-agents'])
        self.assertEqual(out[-4:], ['user fix the bug', 'agent(gemini-2.5-pro) Looking at it',
                                    'tool(read_file) src/main.rs', 'result fn main() {}'])
        log = self.agent_log()
        for frm in range(4):
            self.assertIn(f'agent-transcript s1 {frm}\n', log)

    def test_growth_of_the_open_session_is_fetched_from_the_first_change(self):
        out = self.run_editor(exts=self.extension(), drop_waits=True, actions=[
            'wait-ext acme/gem running', 'wait 300', 'print-agents 1', 'wait 300',
            'cmd acme/gem.grow', 'wait 300', 'wait 300', 'print-agents'])
        self.assertEqual(out[-3:], ['result fn main() {}', 'agent Fixed it', 'error quota reached'])
        self.assertIn('agent-transcript s1 4', self.agent_log())

    def test_a_new_list_replaces_the_rows_and_closes_a_vanished_session(self):
        out = self.run_editor(exts=self.extension(), drop_waits=True, actions=[
            'wait-ext acme/gem running', 'wait 300', 'print-agents 1', 'wait 300',
            'cmd acme/gem.drop', 'wait 300', 'wait 300', 'print-agents'])
        self.assertEqual(out[-1], 'Gemini CLI: Old talk')

    def test_rows_go_with_their_extension(self):
        out = self.run_editor(exts=self.extension(), drop_waits=True, actions=[
            'wait-ext acme/gem running', 'wait 300', 'ext-set acme/gem stop', 'wait 1500', 'print-agents'])
        self.assertEqual(self.rows(out), [])

    def test_malformed_lists_change_nothing(self):
        out = self.run_editor(exts=self.extension(), drop_waits=True, actions=[
            'wait-ext acme/gem running', 'wait 300', 'cmd acme/gem.bad', 'wait 300', 'wait 300', 'print-agents'])
        self.assertEqual(len(self.rows(out)), 2)
        errors = [l for l in self.agent_log().splitlines() if l.startswith('error ')]
        self.assertEqual(errors, ['error 2 syntax the sessions cannot be read',
                                  'error 3 syntax the sessions cannot be read',
                                  'error 4 syntax the sessions cannot be read',
                                  'error 5 syntax the sessions cannot be read',
                                  'error 6 syntax the sessions cannot be read',
                                  'error 7 refused no such session',
                                  'error 8 syntax cannot parse the line'])

    def test_without_provides_or_feature_rows_are_refused(self):
        self.run_editor(exts=self.extension(provides=False), actions=['wait-ext acme/gem running', 'wait 300'])
        self.assertIn('error 1 refused the manifest does not say [provides] agents = yes', self.agent_log())
        (self.work / 'state/rhun/extensions/acme--gem/agent.log').unlink()
        import shutil
        shutil.rmtree(self.work / 'agents-exts')
        self.run_editor(exts=self.extension(hello='hello 1'), actions=['wait-ext acme/gem running', 'wait 300'])
        self.assertIn('error 1 unknown no such request', self.agent_log())
        self.assertNotIn('0 features', self.agent_log())

    def test_feature_is_agreed(self):
        self.run_editor(exts=self.extension(hello='hello 1 agents no-such-feature'), actions=[
            'wait-ext acme/gem running', 'wait 300'])
        self.assertIn('0 features agents\n', self.agent_log())

    def test_settings_switch_hides_a_source_and_is_saved(self):
        out = self.run_editor(exts=self.extension(), drop_waits=True, actions=[
            'wait-ext acme/gem running', 'wait 300', 'print-settings', 'agents-source acme/gem',
            'wait 100', 'print-agents', 'print-settings'])
        self.assertIn('agents.acme/gem=true', out)
        self.assertIn('agents.acme/gem=false', out)
        self.assertEqual(self.rows(out), [])
        config = (self.work / 'config/rhun/config').read_text()
        self.assertIn('[agents]', config)
        self.assertIn('acme/gem = false', config)
        # read back: the source stays hidden in the next session
        out = self.run_editor(exts=self.extension(), drop_waits=True, actions=[
            'wait-ext acme/gem running', 'wait 300', 'print-agents'])
        self.assertEqual(self.rows(out), [])


if __name__ == '__main__':
    unittest.main()
