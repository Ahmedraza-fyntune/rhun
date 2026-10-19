#!/usr/bin/env python3
"""Feature selections (docs/extensions/v1.1.md): the selections event, select-many,
insert at every selection, select collapsing. A small fake extension written by the test agrees
the feature, logs every line rhun sends (SEL_LOG, in its state folder) and sends requests when
its commands run."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()

CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
MANIFEST = '''name = sel
owner = fixture
title = Selections
version = 1
protocol = 1
runtime = python3
run = main.py
on = startup

[commands]
many = Select Many
toobig = Select Too Many
badpos = Select Outside
insert = Insert Everywhere
select = Select One

[subscribe]
opened = *
changed = *
cursor = *
selection = *

[needs]
documents = write
'''
MAIN = r'''import os, sys
LOG = os.environ['SEL_LOG']
out, inp = sys.stdout.buffer, sys.stdin.buffer
def log(data):
    with open(LOG, 'ab') as f:
        f.write(data + b'\n')
def send(line, body=b''):
    out.write(line.encode() + b'\n' + body)
    out.flush()
def body(n):
    data = b''
    while len(data) < n:
        chunk = inp.read(n - len(data))
        if not chunk:
            break
        data += chunk
    return data
send('hello 1 selections')
versions, rid = {}, 1
while True:
    line = inp.readline()
    if not line:
        break
    line = line.rstrip(b'\n')
    f = line.decode().split(' ')
    log(line)
    if f[0] != '0':
        continue
    event = f[1]
    if event in ('selections', 'edits'):
        log(body(int(f[-1])).replace(b'\n', b'|'))
    elif event in ('opened', 'changed'):
        versions[int(f[2])] = int(f[3])
    elif event == 'bye':
        break
    elif event == 'run':
        cmd, doc = f[2], int(f[3])
        if cmd.endswith('.many'):
            text = b'1 1 1 4\n2 1 2 3\n1 2 1 3\n'
            send(f'{rid} select-many {doc} 3 {len(text)}', text)
        elif cmd.endswith('.toobig'):
            text = b'1 1 1 1\n' * 513
            send(f'{rid} select-many {doc} 513 {len(text)}', text)
        elif cmd.endswith('.badpos'):
            text = b'1 1 1 2\n9 9 9 9\n'
            send(f'{rid} select-many {doc} 2 {len(text)}', text)
        elif cmd.endswith('.insert'):
            send(f'{rid} insert {doc} {versions[doc]} 1', b'X')
        elif cmd.endswith('.select'):
            send(f'{rid} select {doc} 2 2 2 2')
        rid += 1
'''


class Selections(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-ext-sel-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        (self.proj / 'a.txt').write_text('alpha beta\ngamma delta\n', encoding='utf-8')
        (self.proj / 'long.txt').write_text(''.join(f'line {n}\n' for n in range(1, 201)),
                                            encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.log = self.work / 'state/rhun/extensions/fixture--sel/sel.log'
        self.exts = self.work / 'exts'
        self.extension()

    def tearDown(self):
        for _ in range(50):
            try:
                self.tmp.cleanup()
                return
            except OSError:
                time.sleep(0.2)
        self.tmp.cleanup()

    def extension(self):
        folder = self.exts / 'fixture' / 'sel'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'extension.ini').write_text(
            MANIFEST, encoding='utf-8')
        (folder / 'main.py').write_text(MAIN, encoding='utf-8')

    def run_editor(self, actions, files=('a.txt',)):
        env = dict(os.environ, HOME=self.work.as_posix(),
                   XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                   XDG_STATE_HOME=(self.work / 'state').as_posix(),
                   SEL_LOG=self.log.as_posix())
        opens = ['open ' + (self.proj / name).as_posix() for name in files]
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', *opens, 'wait-ext sel running', 'wait 200',
                                     *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', '1000x600',
                                 '--scale', '1', '--extensions', str(self.exts),
                                 '--script', script.as_posix()],
                                env=env, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        out = result.stdout.decode('utf-8', errors='replace')
        self.assertNotIn('unknown command', out)
        return out

    def sel_log(self):
        return self.log.read_text(encoding='utf-8').splitlines() if self.log.exists() else []

    @staticmethod
    def selections(out):
        blocks, lines = [], out.splitlines()
        for i, line in enumerate(lines):
            if line.startswith('sels='):
                n = int(line[5:])
                blocks.append(lines[i + 1:i + 1 + n])
        return blocks

    def events(self, name):
        """Every "0 NAME ..." line of the log, with the body line after it for selections."""
        log, found = self.sel_log(), []
        for i, line in enumerate(log):
            if line.startswith('0 ' + name + ' '):
                found.append(line + (' | ' + log[i + 1] if name == 'selections' else ''))
        return found

    def test_selections_replace_selection_events(self):
        cell = lambda line, col: f'{56 + (col - 1) * 7} {86 + (line - 1) * 21}'
        self.run_editor(['click ' + cell(2, 3) + ' alt', 'wait 100', 'key Right', 'wait 100',
                         'key Escape', 'wait 100', 'key Right', 'wait 100', 'key shift+Right',
                         'wait 200'])
        log = self.sel_log()
        self.assertIn('features selections', ' '.join(l for l in log if l.startswith('0 features')))
        sels = self.events('selections')
        # catch-up: the active document's one caret; then every change of the set, primary first
        self.assertEqual(sels[0], '0 selections 1 1 8 | 1 1 1 1|')
        self.assertEqual(sels[1], '0 selections 1 2 16 | 2 3 2 3|1 1 1 1|')
        self.assertEqual(sels[2], '0 selections 1 2 16 | 2 4 2 4|1 2 1 2|')
        # Escape back to one caret is a change; a caret that moves is not (the cursor event says it)
        self.assertEqual(sels[3], '0 selections 1 1 8 | 2 4 2 4|')
        self.assertEqual(sels[4], '0 selections 1 1 8 | 2 5 2 6|')
        self.assertEqual(len(sels), 5, sels)
        self.assertIn('0 cursor 1 2 5', log)
        self.assertFalse([l for l in log if l.startswith('0 selection ')], log)

    def test_select_many_merges_and_checks(self):
        out = self.run_editor(['cmd sel.many', 'wait 200', 'print-selections', 'cmd sel.toobig',
                               'wait 200', 'print-selections', 'cmd sel.badpos', 'wait 200',
                               'print-selections'])
        sels = self.selections(out)
        # the first is primary; the third overlaps it and merges into it
        self.assertEqual(sels[0], ['1 1 1 4', '2 1 2 3'])
        self.assertEqual(sels[1], sels[0])
        self.assertEqual(sels[2], sels[0])
        log = self.sel_log()
        self.assertIn('ok 1', log)
        self.assertTrue([l for l in log if l.startswith('error 2 toobig')], log)
        self.assertTrue([l for l in log if l.startswith('error 3 badpos')], log)
        self.assertIn('0 selections 1 2 16 | 1 1 1 4|2 1 2 3|', self.events('selections'))

    def test_insert_goes_to_every_selection_and_select_collapses(self):
        out = self.run_editor(['cmd sel.many', 'wait 200', 'cmd sel.insert', 'wait 200',
                               'print-doc', 'print-selections', 'key ctrl+z', 'print-selections',
                               'cmd sel.select', 'wait 200', 'print-selections'])
        self.assertIn('Xha beta\nXmma delta\n', out)
        sels = self.selections(out)
        self.assertEqual(sels[0], ['1 2 1 2', '2 2 2 2'])
        self.assertEqual(sels[1], ['1 1 1 4', '2 1 2 3'])
        self.assertEqual(sels[2], ['2 2 2 2'])
        self.assertTrue([l for l in self.sel_log() if l.startswith('ok 2 ')], self.sel_log())


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0], *sys.argv[1:]])
