#!/usr/bin/env python3
"""Workspace edits as transactions (docs/extensions/v1.1.md, workspace-edits and
file-operations), driven headlessly with the wsx fake extension (tests/ext/wsx.py): v1 edits
across tabs undo as one step, the feature's edits of files that are not open go to disk with a
journal, the confirmation list, one undo across documents and files, partial undo, file
operations with tabs that follow, crash recovery."""
import os
import shutil
import unittest
from pathlib import Path

host = __import__('ext-host')
ROOT = host.ROOT


def fnv(data):
    h = 0xcbf29ce484222325
    for b in data:
        h = ((h ^ b) * 0x100000001b3) & 0xffffffffffffffff
    return '%016x' % h


MANIFEST = '''name = wsx
owner = rhun-tests
title = Wsx
version = 1
protocol = 1
runtime = python3
run = wsx.py
on = command

[commands]
{commands}

[subscribe]
opened = *
changed = *

[needs]
documents = write
project = {project}

[provides]
rename = *.txt *.go
'''


PD = 'echo @doc\nprint-doc'


def edit(*groups, records=()):
    """A workspace edit body: groups are (path, pre, [(l1, c1, l2, c2, text)...]) or raw lines
    for file operations (a str ending in a newline and its path bytes)."""
    out = [str(len(groups)) + '\n']
    for g in groups:
        if isinstance(g, str):
            out.append(g)
            continue
        path, pre, edits = g
        out.append('%d %s %d\n%s' % (len(path.encode()), pre, len(edits), path))
        for l1, c1, l2, c2, text in edits:
            out.append('%d %d %d %d %d\n%s' % (l1, c1, l2, c2, len(text.encode()), text))
    for name, args, data in records:
        out.append('%s %s%d\n%s' % (name, args + ' ' if args else '', len(data.encode()), data))
    return ''.join(out)


class Ws(host.Host):
    def setUp(self):
        super().setUp()
        (self.proj / 'c.txt').write_text('third file\n', encoding='utf-8')
        self.extlog = self.work / 'state/rhun/extensions/rhun-tests--wsx/wsx.log'

    def ext(self, plans, features='', project='read', folder='exts'):
        root = self.work / folder
        dst = root / 'rhun-tests' / 'wsx'
        if dst.exists():
            shutil.rmtree(dst)
        (dst / 'plans').mkdir(parents=True)
        shutil.copy(ROOT / 'tests/ext/wsx.py', dst / 'wsx.py')
        (dst / 'features').write_text(features, encoding='utf-8')
        names = []
        for name, text in plans.items():
            (dst / 'plans' / name).write_bytes(text.encode())
            if name != 'rename':
                names.append(name + ' = Wsx ' + name)
        (dst / 'extension.ini').write_text(MANIFEST.format(commands='\n'.join(names) or 'x = X',
                                                           project=project), encoding='utf-8')
        return root

    def extlines(self):
        if not self.extlog.exists():
            return []
        return self.extlog.read_text(encoding='utf-8', errors='replace').splitlines()

    def replies(self):
        return [l for l in self.extlines() if l.startswith('ok ') or l.startswith('error ')]

    def run_ws(self, exts, actions, files=('a.txt', 'b.go')):
        return self.run_editor(actions, exts=exts, files=files)

    def docs(self, out):
        """The text of each 'echo @doc' + print-doc pair in order (see PD)."""
        docs, cur = [], None
        for line in out:
            if line == '@doc':
                cur = []
            elif line == '<eod>' and cur is not None:
                docs.append('\n'.join(cur))
                cur = None
            elif cur is not None:
                cur.append(line)
        return docs

    # --- v1: no feature, closed files open as unsaved tabs, one undo across tabs ---

    def test_v1_edit_across_tabs_undoes_as_one_step(self):
        body = edit((str(self.proj / 'a.txt'), '-', [(1, 1, 1, 6, 'HELLO')]),
                    (str(self.proj / 'b.go'), '-', [(1, 9, 1, 10, 'B')]),
                    (str(self.proj / 'c.txt'), '-', [(1, 1, 1, 6, 'THIRD')]))
        exts = self.ext({'go': 'apply LEN\n' + body})
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'print-tabs',
                                 'print-tx', PD, 'key ctrl+z', 'print-toast', 'print-tx',
                                 PD, 'key ctrl+shift+Tab', PD, 'key ctrl+shift+Tab',
                                 PD, 'key ctrl+y', 'print-tx', PD])
        self.assertIn('ok 1', self.replies())
        tabs = [l for l in out if l.startswith('tabs=')]
        self.assertEqual(tabs[0], 'tabs=a.txt | *b.go | c.txt', out)
        tx = [l for l in out if l.startswith('tx=')]
        self.assertTrue(tx[0].startswith('tx=1 state=applied parts=3 files=3 label=Edit from Wsx'), tx)
        self.assertTrue(tx[1].startswith('tx=1 state=undone '), tx)
        self.assertTrue(tx[2].startswith('tx=1 state=applied '), tx)
        self.assertIn("toast=Undid 'Edit from Wsx' in 3 files", out)
        docs = self.docs(out)
        self.assertEqual(docs, ['package B\n', 'package b\n', 'hello world\nsecond line\n',
                                'third file\n', 'THIRD file\n'])   # redo from c.txt

    def test_one_document_edit_is_no_transaction(self):
        body = edit((str(self.proj / 'a.txt'), '-', [(1, 1, 1, 6, 'HELLO')]))
        exts = self.ext({'go': 'apply LEN\n' + body})
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'print-tx',
                                 'key ctrl+z', PD], files=('a.txt',))
        self.assertIn('tx=none', out)
        self.assertEqual(self.docs(out)[0], 'hello world\nsecond line\n')

    def test_partial_undo_asks_and_undoes_this_file_only(self):
        body = edit((str(self.proj / 'a.txt'), '-', [(1, 1, 1, 6, 'HELLO')]),
                    (str(self.proj / 'b.go'), '-', [(1, 9, 1, 10, 'B')]))
        exts = self.ext({'go': 'apply LEN\n' + body})
        # a.txt changes after the edit; undo in b.go (active) asks
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400',
                                 'key ctrl+Tab', 'key End', 'type X', 'key ctrl+shift+Tab',
                                 'key ctrl+z', 'print-palette', 'key Return', 'print-tx', PD,
                                 'key ctrl+Tab', PD, 'key ctrl+z', PD, 'key ctrl+z', 'print-tx', PD])
        self.assertIn("choose='Edit from Wsx': a.txt changed after it", out)
        self.assertIn('> Undo in this file only', out)
        self.assertIn('  Cancel', out)
        tx = [l for l in out if l.startswith('tx=')]
        self.assertTrue(tx[0].startswith('tx=1 state=partial'), tx)
        self.assertTrue(tx[1].startswith('tx=1 state=undone'), tx)
        docs = self.docs(out)
        self.assertEqual(docs[0], 'package b\n')                  # b.go only
        self.assertEqual(docs[1], 'HELLO worldX\nsecond line\n')  # a.txt keeps both
        self.assertEqual(docs[2], 'HELLO world\nsecond line\n')   # its own typing undone
        self.assertEqual(docs[3], 'hello world\nsecond line\n')   # then its part of the edit

    def test_partial_undo_of_the_files_that_did_not_change(self):
        body = edit((str(self.proj / 'a.txt'), '-', [(1, 1, 1, 6, 'HELLO')]),
                    (str(self.proj / 'b.go'), '-', [(1, 9, 1, 10, 'B')]),
                    (str(self.proj / 'c.txt'), '-', [(1, 1, 1, 6, 'THIRD')]))
        exts = self.ext({'go': 'apply LEN\n' + body})
        # tabs a.txt b.go c.txt (b active); c.txt changes; undo in b.go: undo b and a
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400',
                                 'key ctrl+Tab', 'key End', 'type X', 'key ctrl+shift+Tab',
                                 'key ctrl+z', 'print-palette', 'key Down', 'key Return', 'print-tx',
                                 'print-toast', PD, 'key ctrl+shift+Tab', PD, 'key ctrl+shift+Tab', PD])
        self.assertIn('  Undo in the 2 files that did not change', out)
        self.assertIn("toast=Undid 'Edit from Wsx' in 2 files", out)
        tx = [l for l in out if l.startswith('tx=')]
        self.assertTrue(tx[0].startswith('tx=1 state=partial'), tx)
        docs = self.docs(out)
        self.assertEqual(docs, ['package b\n', 'hello world\nsecond line\n', 'THIRD fileX\n'])

    def test_partial_undo_cancel_changes_nothing(self):
        body = edit((str(self.proj / 'a.txt'), '-', [(1, 1, 1, 6, 'HELLO')]),
                    (str(self.proj / 'b.go'), '-', [(1, 9, 1, 10, 'B')]))
        exts = self.ext({'go': 'apply LEN\n' + body})
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400',
                                 'key ctrl+Tab', 'key End', 'type X', 'key ctrl+shift+Tab',
                                 'key ctrl+z', 'key Escape', 'print-tx', PD])
        self.assertTrue([l for l in out if l.startswith('tx=')][0].startswith('tx=1 state=applied'))
        self.assertEqual(self.docs(out), ['package B\n'])

    def test_undo_last_multi_file_edit_command(self):
        body = edit((str(self.proj / 'a.txt'), '-', [(1, 1, 1, 6, 'HELLO')]),
                    (str(self.proj / 'b.go'), '-', [(1, 9, 1, 10, 'B')]))
        exts = self.ext({'go': 'apply LEN\n' + body})
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400',
                                 'cmd undo_workspace_edit', 'print-tx', PD, 'cmd undo_workspace_edit',
                                 'print-toast', 'cmd redo_workspace_edit', 'print-tx', PD])
        tx = [l for l in out if l.startswith('tx=')]
        self.assertTrue(tx[0].startswith('tx=1 state=undone'), tx)
        self.assertTrue(tx[1].startswith('tx=1 state=applied'), tx)
        self.assertIn('toast=No multi-file edit to undo', out)
        self.assertEqual(self.docs(out), ['package b\n', 'package B\n'])


for name in dir(host.Host):
    if name.startswith('test_'):
        setattr(Ws, name, None)

if __name__ == '__main__':
    unittest.main()
