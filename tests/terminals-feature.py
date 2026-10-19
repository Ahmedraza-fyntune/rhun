#!/usr/bin/env python3
"""The "terminals" feature of protocol 1.1 (tasks design 3.4, docs/extensions/v1.1.md): a fake
extension (the driver below) opens terminals running programs it names, after the one approval per
project, stops, restarts, closes, shows them, types into them and reads them, at each level of the
[needs] terminal ladder; every line it receives goes to a log in its state folder."""
import json
import os
from pathlib import Path
import time
import unittest

host = __import__('ext-host')
WINDOWS = os.name == 'nt'

DRIVER = r'''import os
import sys
from pathlib import Path

log = open(Path(os.environ['RHUN_STATE']) / 'driver.log', 'ab', buffering=0)
inp = sys.stdin.buffer
out = sys.stdout.buffer
next_id = 1
last_term = [0]

def send(line, body=b''):
    global next_id
    out.write(str(next_id).encode() + b' ' + line.encode() + b'\n' + body)
    out.flush()
    next_id += 1

def definition(task_id, form, label, cmd, cwd='', extra=b''):
    cmd = cmd.encode() if isinstance(cmd, str) else cmd
    head = f'{task_id} {form} {len(label.encode())} {len(cmd)} {len(cwd.encode())} {len(extra)}\n'
    return head.encode() + label.encode() + cmd + cwd.encode() + extra

def rec(name, args, data=b''):
    return (name + (' ' + args if args else '') + f' {len(data)}\n').encode() + data

out.write((HELLO + '\n').encode())
out.flush()
while True:
    line = inp.readline()
    if not line:
        break
    log.write(line)
    words = line.split()
    # bodies: terminal-output, and ok replies with a LEN (terminal-screen)
    if line.startswith(b'0 terminal-output '):
        log.write(inp.read(int(words[-1])))
    if words[:1] == [b'ok'] and len(words) == 3 and last_term[0] == -1:
        log.write(inp.read(int(words[2])))
        last_term[0] = 0
    if words[:1] == [b'ok'] and len(words) == 3 and last_term[0] == 0:
        last_term[0] = int(words[2])
    if line.startswith(b'0 terminal-started '):
        last_term[0] = int(words[2])
    if line.startswith(b'0 bye'):
        break
    if not line.startswith(b'0 run '):
        continue
    name = words[2].decode().split('.', 1)[1]
    t = str(last_term[0])
    if name == 'open':
        send('terminal-open ' + str(len(d := definition('-', 'shell', 'hi', "printf '\\033[1mhi\\033[0m\\n'; exit 3"))), d)
    elif name == 'argv':
        cmd = b'sh\0-c\0echo argv-$0 "$1"\0zero\0one two\0'
        send('terminal-open ' + str(len(d := definition('-', 'argv', 'args', cmd))), d)
    elif name == 'cat':
        last_term[0] = 0
        send('terminal-open ' + str(len(d := definition('-', 'shell', 'cat', 'cat', extra=rec('output', '')))), d)
    elif name == 'sleep':
        last_term[0] = 0
        send('terminal-open ' + str(len(d := definition('-', 'shell', 'sleeper', 'echo up; sleep 30'))), d)
    elif name == 'env':
        extra = rec('env', 'RHUN_T1', b'one two') + rec('unset', 'HOME') + rec('detail', '', b'shown') + rec('future', 'x y', b'skipped')
        send('terminal-open ' + str(len(d := definition('-', 'shell', 'env', 'echo "[$RHUN_T1]" "${HOME-nohome}"; pwd', 'sub', extra))), d)
    elif name == 'input':
        send('terminal-input ' + t + ' 6', b'hello\n')
    elif name == 'screen':
        last_term[0] = -1
        send('terminal-screen ' + t)
    elif name in ('stop', 'restart', 'close'):
        send('terminal-' + name + ' ' + t)
    elif name == 'show':
        send('terminal-show ' + t + ' focus')
    elif name == 'other':
        send('terminal-stop 1')
    elif name == 'bad':
        send('terminal-open ' + str(len(d := definition('x', 'shell', 'l', 'true'))), d)
        send('terminal-open ' + str(len(d := definition('-', 'csh', 'l', 'true'))), d)
        send('terminal-open ' + str(len(d := definition('-', 'shell', 'l', 'true', extra=rec('group', 'build')))), d)
        send('terminal-open ' + str(len(d := definition('-', 'shell', 'l', 'true', extra=rec('location', 'remote')))), d)
        send('terminal-open 5', b'abcde')
    elif name == 'outneed':
        send('terminal-open ' + str(len(d := definition('-', 'shell', 'l', 'true', extra=rec('output', '')))), d)
'''

COMMANDS = ('open', 'argv', 'cat', 'sleep', 'env', 'input', 'screen', 'stop', 'restart', 'close', 'show',
            'other', 'bad', 'outneed')


class Feature(unittest.TestCase):
    setUp = host.Host.setUp
    tearDown = host.Host.tearDown
    run_editor = host.Host.run_editor

    def driver(self, level='output', features='terminals', name='driver'):
        root = self.work / 'exts'
        folder = root / 't' / name
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'extension.ini').write_text(
            f'name = {name}\nowner = t\ntitle = Driver\nversion = 1\nprotocol = 1\nruntime = python3\n'
            'run = main.py\non = command\n[commands]\n' + ''.join(f'{c} = {c}\n' for c in COMMANDS) +
            f'[needs]\nterminal = {level}\n', encoding='utf-8')
        (folder / 'main.py').write_text('HELLO = ' + json.dumps('hello 1 ' + features) + '\n' + DRIVER,
                                        encoding='utf-8')
        (self.proj / 'sub').mkdir(exist_ok=True)
        return root

    def dlog(self, name='driver'):
        path = self.work / f'state/rhun/extensions/t--{name}/driver.log'
        return path.read_bytes().decode('utf-8', errors='replace') if path.exists() else ''

    def go(self, actions, exts):
        return self.run_editor(drop_waits=True, exts=exts, actions=actions)

    def allow(self):
        return ['wait-ext driver running', 'wait 200', 'print-dialog', 'dialog yes', 'wait 300']

    # --- open, events, the tab ---

    def test_open_asks_once_then_runs_and_reports(self):
        exts = self.driver()
        out = self.go(['cmd t/driver.open', *self.allow(), 'wait-terminal 1 ended', 'wait 300', 'print-terminals',
                       'print-term', 'cmd t/driver.open', 'wait-terminal 2 ended', 'wait 300', 'print-dialog'], exts)
        self.assertEqual(out[0], 'dialog=Let Driver run programs in proj?')
        self.assertTrue(out[1].startswith("text=printf '"), out)
        log = self.dlog()
        self.assertIn('0 features terminals\n', log)
        self.assertIn('ok 1 1\n', log)
        self.assertRegex(log, r'0 terminal-started 1 \d+ -\n')
        self.assertIn('0 terminal-ended 1 exit 3 0 0\n', log)
        self.assertIn('kind=terminal owner=t/driver task=- state=exited code=3', '\n'.join(out))
        self.assertIn('hi', out)
        self.assertIn('ok 2 2\n', log)          # the second one does not ask
        self.assertEqual(out[-1], 'dialog=none')

    def test_cancel_and_busy(self):
        exts = self.driver()
        self.go(['cmd t/driver.open', 'wait-ext driver running', 'wait 300', 'cmd t/driver.open', 'wait 300',
                 'dialog no', 'wait 300'], exts)
        log = self.dlog()
        self.assertIn('error 2 busy\n', log)
        self.assertIn('error 1 cancelled\n', log)
        self.assertNotIn('terminal-started', log)

    def test_argv_env_unset_and_folder(self):
        exts = self.driver()
        out = self.go(['cmd t/driver.argv', *self.allow(), 'wait-terminal 1 ended', 'print-term',
                       'cmd t/driver.env', 'wait-terminal 2 ended', 'print-term'], exts)
        self.assertIn('argv-zero one two', out)
        self.assertIn('[one two] nohome', out)
        self.assertIn((self.proj / 'sub').as_posix(), ''.join(out))     # a long path wraps

    # --- the handle ---

    def test_stop_restart_close_and_show(self):
        exts = self.driver()
        out = self.go(['cmd t/driver.sleep', *self.allow(), 'wait-term up', 'cmd t/driver.stop',
                       'wait-terminal 1 ended', 'wait 300', 'print-terminals', 'cmd t/driver.restart',
                       'wait-terminal 1 running 2', 'wait 300', 'cmd t/driver.show', 'wait 200', 'print-state',
                       'cmd t/driver.close', 'wait 500', 'print-terminals', 'cmd t/driver.stop', 'wait 300'], exts)
        log = self.dlog()
        self.assertIn('0 terminal-ended 1 stopped ', log)
        self.assertEqual(log.count('0 terminal-started 1 '), 2)
        self.assertIn('0 terminal-closed 1\n', log)
        self.assertIn('focus=8 ', '\n'.join(out))     # show focus gives the terminal the keyboard
        # print-terminals after the close lists nothing
        self.assertEqual(sum(1 for line in out if line.lstrip('*').startswith('term=1 ')), 1, out)
        self.assertIn('error 6 noterm no such terminal\n', log)     # a closed tab's TERM is gone

    def test_a_users_shell_has_no_handle(self):
        exts = self.driver()
        self.go(['cmd new_terminal', 'wait 300', 'cmd t/driver.other', 'wait-ext driver running', 'wait 400'], exts)
        self.assertIn('error 1 noterm no such terminal\n', self.dlog())

    # --- input and output ---

    def test_input_output_and_screen(self):
        exts = self.driver()
        self.go(['cmd t/driver.cat', *self.allow(), 'wait 300', 'cmd t/driver.input', 'wait-term hello',
                 'wait 500', 'cmd t/driver.screen', 'wait 500'], exts)
        log = self.dlog()
        self.assertIn('0 terminal-output 1 0 ', log)
        self.assertIn('hello\n', log.split('0 terminal-output 1 0 ', 1)[1])
        self.assertRegex(log, r'ok 3 \d+\n\d+ \d+ \d+ \d+\nhello\n')

    # --- the ladder and the syntax ---

    def test_suggest_cannot_run(self):
        exts = self.driver(level='yes')
        self.go(['cmd t/driver.open', 'wait-ext driver running', 'wait 300'], exts)
        self.assertIn('error 1 needs terminal=run\n', self.dlog())

    def test_run_cannot_type_or_read(self):
        exts = self.driver(level='run')
        self.go(['cmd t/driver.sleep', *self.allow(), 'wait-term up', 'cmd t/driver.input', 'wait 200',
                 'cmd t/driver.screen', 'wait 200', 'cmd t/driver.outneed', 'wait 300'], exts)
        log = self.dlog()
        self.assertIn('error 2 needs terminal=input\n', log)
        self.assertIn('error 3 needs terminal=output\n', log)
        self.assertIn('error 4 needs terminal=output\n', log)

    def test_unagreed_feature(self):
        exts = self.driver(features='commands')
        self.go(['cmd t/driver.open', 'wait-ext driver running', 'wait 300'], exts)
        self.assertIn('error 1 unknown', self.dlog())

    def test_bad_definitions(self):
        exts = self.driver()
        self.go(['cmd t/driver.bad', 'wait-ext driver running', 'wait 400'], exts)
        log = self.dlog()
        self.assertIn('error 1 syntax definition: id: a terminal\'s is -\n', log)
        self.assertIn('error 2 syntax definition: form: shell or argv\n', log)
        self.assertIn('error 3 syntax definition: not in a terminal: group, default, depends, matcher, ready, busy\n', log)
        self.assertIn('error 4 syntax definition: unsupported location\n', log)
        self.assertIn('error 5 syntax definition: header', log)

    def test_extension_stopping_stops_its_programs(self):
        exts = self.driver()
        out = self.go(['cmd t/driver.sleep', *self.allow(), 'wait-term up', 'ext-set t/driver stop', 'wait 2500',
                       'print-terminals'], exts)
        self.assertIn('term=1 kind=terminal owner=t/driver task=- state=stopped', '\n'.join(out))


if __name__ == '__main__':
    unittest.main(verbosity=2)
