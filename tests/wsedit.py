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


    # --- workspace-edits: files that are not open go to disk, with a journal ---

    def disk_edit(self, extra=()):
        """a.txt open (clean), b.go open and dirty, c.txt closed: one edit of all three."""
        c = self.proj / 'c.txt'
        return edit((str(self.proj / 'a.txt'), '{ver:a.txt}', [(1, 1, 1, 6, 'HELLO')]),
                    (str(self.proj / 'b.go'), '{ver:b.go}', [(1, 2, 1, 9, 'PACKAGE')]),
                    (str(c), 'fnv1a64:{fnv:%s}' % c, [(1, 1, 1, 6, 'THIRD')]), *extra,
                    records=[('label', '', 'Shout them')])

    def test_feature_edit_writes_closed_files_after_the_list_and_undoes_as_one(self):
        exts = self.ext({'go': 'apply LEN\n' + self.disk_edit()}, features='workspace-edits')
        out = self.run_ws(exts, ['type X', 'key ctrl+shift+Tab', 'cmd wsx.go', 'wait-ext wsx running',
                                 'wait 400', 'print-palette', 'key Return', 'wait 100', 'print-tabs',
                                 'print-tx', 'print-journal', 'print-toast', 'print-state', PD,
                                 'key ctrl+Tab', 'print-state', PD])
        self.assertIn('0 features workspace-edits', self.extlines())
        self.assertIn("choose=Wsx: 'Shout them' changes 1 file that is not open and 2 open files", out)
        self.assertIn('> Apply', out)
        self.assertIn('  Apply, and let Wsx change project files from now on', out)
        self.assertIn('  Preview changes', out)
        self.assertIn('  M  a.txt    1 edit', out)
        self.assertIn('  M  b.go    1 edit', out)
        self.assertIn('  M  c.txt    1 edit', out)
        self.assertIn('ok 1', self.replies())
        self.assertIn('tabs=*a.txt | b.go', out)                 # no tab for c.txt
        self.assertTrue([l for l in out if l.startswith('tx=')][0].startswith(
            'tx=1 state=applied parts=3 files=3 label=Shout them'), out)
        self.assertTrue(any(l.startswith('journal=tx-') and l.endswith(' committed=1') for l in out), out)
        self.assertIn("toast=Applied 'Shout them' to 3 files", out)
        self.assertEqual((self.proj / 'c.txt').read_text(), 'THIRD file\n')
        self.assertEqual((self.proj / 'a.txt').read_text(), 'HELLO world\nsecond line\n')  # was clean
        self.assertEqual((self.proj / 'b.go').read_text(), 'package b\n')   # had unsaved changes
        states = [l for l in out if l.startswith('tabs=2 ')]
        self.assertIn(' dirty=0 ', states[0])
        self.assertIn(' dirty=1 ', states[1])
        self.assertEqual(self.docs(out), ['HELLO world\nsecond line\n', 'XPACKAGE b\n'])
        # undo from a.txt: all three back, c.txt on disk byte for byte
        (self.proj / 'a.txt').write_text('hello world\nsecond line\n')
        (self.proj / 'c.txt').write_text('third file\n')
        out = self.run_ws(exts, ['type X', 'key ctrl+shift+Tab', 'cmd wsx.go', 'wait-ext wsx running',
                                 'wait 400', 'key Return', 'wait 100', 'key ctrl+z', 'print-toast',
                                 'print-tx', 'print-state', PD, 'key ctrl+Tab', PD])
        self.assertIn("toast=Undid 'Shout them' in 3 files", out)
        self.assertEqual((self.proj / 'c.txt').read_text(), 'third file\n')
        self.assertEqual((self.proj / 'a.txt').read_text(), 'hello world\nsecond line\n')
        self.assertIn(' dirty=0 ', [l for l in out if l.startswith('tabs=2 ')][0])
        self.assertEqual(self.docs(out), ['hello world\nsecond line\n', 'Xpackage b\n'])

    def test_redo_writes_the_closed_file_again(self):
        exts = self.ext({'go': 'apply LEN\n' + self.disk_edit()}, features='workspace-edits',
                        project='write')
        self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'key ctrl+shift+Tab',
                           'key ctrl+z', 'key ctrl+y', 'print-tx'])
        self.assertEqual((self.proj / 'c.txt').read_text(), 'THIRD file\n')
        self.assertEqual((self.proj / 'a.txt').read_text(), 'HELLO world\nsecond line\n')

    def test_project_write_applies_without_the_list(self):
        exts = self.ext({'go': 'apply LEN\n' + self.disk_edit()}, features='workspace-edits',
                        project='write')
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'print-palette'])
        self.assertIn('none', out)
        self.assertIn('ok 1', self.replies())
        self.assertEqual((self.proj / 'c.txt').read_text(), 'THIRD file\n')

    def test_confirm_record_shows_the_list_even_with_permission(self):
        body = self.disk_edit().replace('label 10\nShout them', 'label 10\nShout themconfirm 0\n')
        exts = self.ext({'go': 'apply LEN\n' + body}, features='workspace-edits', project='write')
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'print-palette',
                                 'key Escape', 'wait 100'])
        self.assertIn("choose=Wsx: 'Shout them' changes 1 file that is not open and 2 open files", out)
        self.assertNotIn('  Apply, and let Wsx change project files from now on', out)
        self.assertIn('error 1 cancelled 0 the user cancelled the edit', self.replies())
        self.assertEqual((self.proj / 'c.txt').read_text(), 'third file\n')

    def test_escape_cancels_and_changes_nothing(self):
        exts = self.ext({'go': 'apply LEN\n' + self.disk_edit()}, features='workspace-edits')
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'key Escape',
                                 'wait 100', 'print-tx', PD])
        self.assertIn('error 1 cancelled 0 the user cancelled the edit', self.replies())
        self.assertIn('tx=none', out)
        self.assertEqual((self.proj / 'c.txt').read_text(), 'third file\n')
        self.assertEqual(self.docs(out), ['package b\n'])

    def test_allow_from_now_on_is_stored_and_can_be_taken_back(self):
        exts = self.ext({'go': 'apply LEN\n' + edit((str(self.proj / 'c.txt'), '-', [(1, 1, 1, 6, 'THIRD')])),
                         'back': 'apply LEN\n' + edit((str(self.proj / 'c.txt'), '-', [(1, 1, 1, 6, 'third')]))},
                        features='workspace-edits')
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'key Down', 'key Return',
                                 'wait 100', 'cmd wsx.back', 'wait 300', 'print-palette', 'ext-page wsx',
                                 'print-ext-page'])
        ini = (self.work / 'config/rhun/extensions.ini').read_text()
        self.assertIn('[rhun-tests/wsx]', ini)
        self.assertIn('edits = yes', ini)
        self.assertEqual(self.replies()[:2], ['ok 1', 'ok 2'])
        self.assertIn('none', out)                         # the second edit did not ask
        self.assertIn('edits=yes', out)
        self.assertEqual((self.proj / 'c.txt').read_text(), 'third file\n')
        out = self.run_ws(exts, ['ext-edits wsx no', 'cmd wsx.go', 'wait-ext wsx running', 'wait 400',
                                 'print-palette', 'key Escape'])
        self.assertTrue(any(l.startswith('choose=Wsx:') for l in out), out)
        self.assertNotIn('edits = yes', (self.work / 'config/rhun/extensions.ini').read_text())

    def test_stale_hash_and_version_change_nothing(self):
        c = self.proj / 'c.txt'
        stale = edit((str(self.proj / 'a.txt'), '{ver:a.txt}', [(1, 1, 1, 6, 'HELLO')]),
                     (str(c), 'fnv1a64:0123456789abcdef', [(1, 1, 1, 6, 'THIRD')]))
        old = edit((str(self.proj / 'a.txt'), '7', [(1, 1, 1, 6, 'HELLO')]),
                   (str(c), '-', [(1, 1, 1, 6, 'THIRD')]))
        exts = self.ext({'go': 'apply LEN\n' + stale, 'old': 'apply LEN\n' + old}, features='workspace-edits')
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'cmd wsx.old', 'wait 300',
                                 'print-palette', PD], files=('a.txt',))
        self.assertEqual(self.replies()[:2], ['error 1 stale 2 a file changed since the edit was made',
                                              'error 2 stale 1 a document changed since the edit was made'])
        self.assertEqual(c.read_text(), 'third file\n')
        self.assertEqual(self.docs(out), ['hello world\nsecond line\n'])

    def test_file_outside_the_project_needs_permission(self):
        out_file = self.work / 'outside.txt'
        out_file.write_text('outside\n')
        exts = self.ext({'go': 'apply LEN\n' + edit((str(out_file), '-', [(1, 1, 1, 2, 'O')]))},
                        features='workspace-edits', project='write')
        self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400'])
        self.assertEqual(self.replies()[0], 'error 1 needs 1 project=write a file is outside the '
                                            "project and the extension's state folder")
        self.assertEqual(out_file.read_text(), 'outside\n')

    def test_preview_shows_a_diff_tab_and_comes_back_to_the_list(self):
        exts = self.ext({'go': 'apply LEN\n' + self.disk_edit()}, features='workspace-edits')
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'key Down', 'key Down',
                                 'key Return', 'wait 100', 'print-palette', 'print-tabs', 'key Escape',
                                 'wait 100', PD])
        self.assertIn('tabs=a.txt | b.go | *Preview: Shout them', out, out)
        self.assertTrue(any(l.startswith('choose=Wsx:') for l in out), out)
        doc = self.docs(out)[0]
        self.assertIn('@@ -1,1 +1,1 @@ c.txt', doc)
        self.assertIn('third file', doc)
        self.assertIn('THIRD file', doc)
        self.assertIn('@@ -1,2 +1,2 @@ a.txt', doc)
        self.assertIn('@@ -1,1 +1,1 @@ b.go\npackage b\npPACKAGEb\n', doc)
        self.assertEqual((self.proj / 'c.txt').read_text(), 'third file\n')   # cancelled after all

    def test_crash_in_the_middle_is_rolled_back_at_the_next_start(self):
        exts = self.ext({'go': 'apply LEN\n' + self.disk_edit()}, features='workspace-edits',
                        project='write')
        env = dict(self.env, RHUN_TEST_EDIT_CRASH='2')
        script = self.work / 'crash.rsc'
        script.write_text('\n'.join(['wait 100', 'open ' + str(self.proj / 'a.txt'),
                                      'open ' + str(self.proj / 'b.go'), 'cmd wsx.go', 'wait-ext wsx running',
                                      'wait 600', 'quit']) + '\n')
        import subprocess
        r = subprocess.run([str(host.EXE), str(self.proj), '--headless', '1000x600', '--scale', '1',
                            '--extensions', str(exts), '--script', str(script)], env=env,
                           capture_output=True, timeout=60)
        self.assertEqual(r.returncode, 70, r.stderr)
        self.assertEqual((self.proj / 'c.txt').read_text(), 'THIRD file\n')       # written
        self.assertEqual((self.proj / 'a.txt').read_text(), 'HELLO world\nsecond line\n')
        out = self.run_ws(exts, ['print-journal', 'print-toast'], files=())
        self.assertIn('journal=none', out)
        self.assertIn('toast=Restored 2 files from a workspace edit that was cut short', out)
        self.assertEqual((self.proj / 'c.txt').read_text(), 'third file\n')
        self.assertEqual((self.proj / 'a.txt').read_text(), 'hello world\nsecond line\n')

    def test_a_write_the_system_refuses_puts_everything_back(self):
        sub = self.proj / 'locked'
        sub.mkdir()
        (sub / 'd.txt').write_text('locked file\n')
        body = edit((str(self.proj / 'c.txt'), '-', [(1, 1, 1, 6, 'THIRD')]),
                    (str(sub / 'd.txt'), '-', [(1, 1, 1, 7, 'LOCKED')]))
        exts = self.ext({'go': 'apply LEN\n' + body}, features='workspace-edits', project='write')
        os.chmod(sub, 0o555)
        try:
            out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'print-tx'])
        finally:
            os.chmod(sub, 0o755)
        self.assertEqual(self.replies()[0], 'error 1 io 2 the system refused a write; everything was put back')
        self.assertEqual((self.proj / 'c.txt').read_text(), 'third file\n')
        self.assertEqual((sub / 'd.txt').read_text(), 'locked file\n')
        self.assertIn('tx=none', out)

    def test_undo_asks_when_a_closed_file_changed_on_disk(self):
        c = self.proj / 'c.txt'
        exts = self.ext({'go': 'apply LEN\n' + self.disk_edit(),
                         'touch': '!write %s\nchanged on disk\n' % c}, features='workspace-edits',
                        project='write')
        out = self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'key ctrl+shift+Tab',
                                 'cmd wsx.touch', 'wait 300', 'key ctrl+z', 'print-palette', 'key Down',
                                 'key Return', 'print-tx', PD])
        self.assertIn("choose='Shout them': c.txt changed after it", out)
        self.assertIn('  Undo in the 2 files that did not change', out)
        self.assertTrue([l for l in out if l.startswith('tx=')][0].startswith('tx=1 state=partial'), out)
        self.assertEqual(c.read_text(), 'changed on disk\n')      # left as it is
        self.assertEqual((self.proj / 'a.txt').read_text(), 'hello world\nsecond line\n')
        self.assertEqual(self.docs(out), ['hello world\nsecond line\n'])

    def test_rename_answer_with_the_feature_writes_and_one_undo(self):
        c = self.proj / 'c.txt'
        rename = edit((str(self.proj / 'b.go'), '{ver:b.go}', [(1, 9, 1, 10, 'start')]),
                      (str(c), 'fnv1a64:{fnv:%s}' % c, [(1, 1, 1, 6, 'start')]))
        exts = self.ext({'rename': 'answer LEN\n' + rename, 'x': 'toast LEN\nhi'}, features='workspace-edits rename',
                        project='write')
        out = self.run_ws(exts, ['cmd wsx.x', 'wait-ext wsx running', 'wait 300', 'key End', 'key F2',
                                 'key ctrl+a', 'type start', 'key Return', 'wait 600', 'print-toast', 'print-tx',
                                 'key ctrl+z', 'print-tx'], files=('b.go',))
        self.assertIn("toast=Applied 'Rename to 'start'' to 2 files", out)
        tx = [l for l in out if l.startswith('tx=')]
        self.assertTrue(tx[1].startswith('tx=1 state=undone'), tx)
        self.assertEqual(c.read_text(), 'third file\n')
        self.assertEqual((self.proj / 'b.go').read_text(), 'package b\n')


    # --- file-operations: create, rename, delete with the rest, tabs follow ---

    def op(self, kind, path, flags='-', to=None):
        if kind == 'rename':
            return 'rename %d %d %s\n%s%s' % (len(str(path).encode()), len(str(to).encode()), flags, path, to)
        return '%s %d %s\n%s' % (kind, len(str(path).encode()), flags, path)

    def test_create_edit_rename_delete_in_one_and_undo_brings_all_back(self):
        p = self.proj
        (p / 'old.txt').write_text('old\n')
        body = edit(self.op('create', p / 'new.txt'),
                    (str(p / 'new.txt'), '-', [(1, 1, 1, 1, 'made\n')]),
                    (str(p / 'a.txt'), '{ver:a.txt}', [(1, 1, 1, 6, 'HELLO')]),
                    self.op('rename', p / 'a.txt', to=p / 'sub' / 'moved.txt'),
                    self.op('delete', p / 'old.txt'), records=[('label', '', 'Shuffle')])
        exts = self.ext({'go': 'apply LEN\n' + body}, features='workspace-edits file-operations',
                        project='write')
        out = self.run_ws(exts, ['open ' + str(p / 'old.txt'), 'key ctrl+Tab', 'key ctrl+Tab', 'cmd wsx.go',
                                 'wait-ext wsx running', 'wait 400', 'print-tabs', 'print-tx', 'echo ---',
                                 'cmd undo_workspace_edit', 'wait 200', 'print-tabs', 'print-tx', 'echo ---',
                                 'cmd redo_workspace_edit', 'wait 200', 'print-tabs', 'print-tx'])
        self.assertIn('0 features workspace-edits file-operations', self.extlines())
        self.assertIn('ok 1', self.replies())
        tabs = [l for l in out if l.startswith('tabs=')]
        self.assertEqual(tabs[0], 'tabs=moved.txt | *b.go', out)            # old.txt's tab closed
        self.assertTrue([l for l in out if l.startswith('tx=')][0].startswith('tx=1 state=applied parts=5'), out)
        self.assertEqual((p / 'new.txt').read_text(), 'made\n')
        self.assertEqual((p / 'sub/moved.txt').read_text(), 'HELLO world\nsecond line\n')
        self.assertFalse((p / 'a.txt').exists())
        self.assertFalse((p / 'old.txt').exists())
        # extensions saw a.txt closed and opened again under its new name
        log = self.extlines()
        self.assertTrue(any(l.startswith('0 opened ') and l.endswith('/sub/moved.txt') for l in log), log)
        # undone: all back, old.txt's tab again; redone
        self.assertIn('a.txt', tabs[1], out)
        self.assertIn('old.txt', tabs[1], out)
        self.assertTrue([l for l in out if l.startswith('tx=')][1].startswith('tx=1 state=undone'), out)
        self.assertEqual(tabs[2], 'tabs=moved.txt | *b.go', out)

    def test_undo_restores_disk_after_the_ops(self):
        p = self.proj
        (p / 'old.txt').write_text('old\n')
        body = edit(self.op('create', p / 'new.txt'),
                    self.op('rename', p / 'c.txt', to=p / 'renamed.txt'),
                    self.op('delete', p / 'old.txt'))
        exts = self.ext({'go': 'apply LEN\n' + body}, features='workspace-edits file-operations',
                        project='write')
        self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 400', 'cmd undo_workspace_edit',
                           'wait 200'])
        self.assertFalse((p / 'new.txt').exists())
        self.assertEqual((p / 'c.txt').read_text(), 'third file\n')
        self.assertFalse((p / 'renamed.txt').exists())
        self.assertEqual((p / 'old.txt').read_text(), 'old\n')

    def test_rename_onto_an_existing_file_needs_overwrite_and_undo_restores_both(self):
        p = self.proj
        bad = edit(self.op('rename', p / 'c.txt', to=p / 'b.go'))
        good = edit(self.op('rename', p / 'c.txt', 'overwrite', to=p / 'b.go'))
        exts = self.ext({'bad': 'apply LEN\n' + bad, 'good': 'apply LEN\n' + good},
                        features='workspace-edits file-operations', project='write')
        self.run_ws(exts, ['cmd wsx.bad', 'wait-ext wsx running', 'wait 300', 'cmd wsx.good', 'wait 300'],
                    files=('a.txt',))
        r = self.replies()
        self.assertTrue(r[0].startswith('error 1 refused 1 '), r)
        self.assertEqual(r[1], 'ok 2')
        self.assertEqual((p / 'b.go').read_text(), 'third file\n')
        self.assertFalse((p / 'c.txt').exists())
        self.run_ws(exts, ['cmd undo_workspace_edit', 'wait 200'], files=('a.txt',))
        # a new session cannot undo the last one's edit: its journal was dropped at quit
        self.assertEqual((p / 'b.go').read_text(), 'third file\n')
        (p / 'c.txt').write_text('third file\n')
        (p / 'b.go').write_text('package b\n')
        self.run_ws(exts, ['cmd wsx.good', 'wait-ext wsx running', 'wait 300', 'cmd undo_workspace_edit',
                           'wait 200'], files=('a.txt',))
        self.assertEqual((p / 'b.go').read_text(), 'package b\n')
        self.assertEqual((p / 'c.txt').read_text(), 'third file\n')

    def test_case_only_rename(self):
        p = self.proj
        body = edit(self.op('rename', p / 'c.txt', to=p / 'C.txt'))
        exts = self.ext({'go': 'apply LEN\n' + body}, features='workspace-edits file-operations',
                        project='write')
        self.run_ws(exts, ['cmd wsx.go', 'wait-ext wsx running', 'wait 300'], files=('a.txt',))
        self.assertEqual(self.replies()[0], 'ok 1')
        self.assertIn('C.txt', os.listdir(p))
        self.assertNotIn('c.txt', os.listdir(p))

    def test_folder_delete_needs_recursive_and_comes_back(self):
        p = self.proj
        (p / 'dir/deep').mkdir(parents=True)
        (p / 'dir/deep/x.txt').write_text('x\n')
        (p / 'dir/y.txt').write_text('y\n')
        bad = edit(self.op('delete', p / 'dir'))
        good = edit(self.op('delete', p / 'dir', 'recursive'))
        exts = self.ext({'bad': 'apply LEN\n' + bad, 'good': 'apply LEN\n' + good},
                        features='workspace-edits file-operations', project='write')
        out = self.run_ws(exts, ['cmd wsx.bad', 'wait-ext wsx running', 'wait 300', 'cmd wsx.good', 'wait 300',
                                 'echo gone=' + str(int(True)), 'cmd undo_workspace_edit', 'wait 200'],
                          files=('a.txt',))
        r = self.replies()
        self.assertTrue(r[0].startswith('error 1 refused 1 '), r)
        self.assertEqual(r[1], 'ok 2')
        self.assertEqual((p / 'dir/deep/x.txt').read_text(), 'x\n')
        self.assertEqual((p / 'dir/y.txt').read_text(), 'y\n')

    def test_refusals(self):
        p = self.proj
        (p / '.git').mkdir()
        cases = {
            'git': edit(self.op('create', p / '.git' / 'hooks')),
            'project': edit(self.op('delete', p, 'recursive')),
            'twice': edit(self.op('create', p / 'n.txt'), self.op('delete', p / 'n.txt', 'ignore-missing')),
            'textdel': edit((str(p / 'c.txt'), '-', [(1, 1, 1, 6, 'X')]), self.op('delete', p / 'c.txt')),
            'flag': edit(self.op('delete', p / 'c.txt', 'overwrite')),
        }
        plans = {k: 'apply LEN\n' + v for k, v in cases.items()}
        plans['x'] = 'toast LEN\nhi'
        exts = self.ext(plans, features='workspace-edits file-operations', project='write')
        acts = ['cmd wsx.x', 'wait-ext wsx running', 'wait 200']
        for k in cases:
            acts += ['cmd wsx.' + k, 'wait 200']
        self.run_ws(exts, acts, files=('a.txt',))
        r = self.replies()[1:]
        self.assertEqual(len(r), 5, r)
        self.assertTrue(r[0].startswith('error 2 refused 1 '), r)
        self.assertTrue(r[1].startswith('error 3 refused 1 '), r)
        self.assertTrue(r[2].startswith('error 4 refused '), r)
        self.assertTrue(r[3].startswith('error 5 refused '), r)
        self.assertTrue(r[4].startswith('error 6 syntax 1 '), r)
        self.assertTrue((p / 'c.txt').exists())

    def test_explorer_delete_and_rename_are_undoable(self):
        p = self.proj
        exts = self.ext({}, features='')
        out = self.run_ws(exts, ['cmd delete_file', 'print-dialog', 'dialog yes', 'wait 100', 'print-toast',
                                 'print-tabs', 'echo ---', 'cmd undo_workspace_edit', 'wait 100', 'print-tabs'],
                          files=('c.txt',))
        self.assertIn("toast=Delete c.txt: Ctrl+Z in the explorer, or Undo Last Multi-File Edit, takes it back", out)
        self.assertEqual((p / 'c.txt').read_text(), 'third file\n')
        tabs = [l for l in out if l.startswith('tabs=')]
        self.assertNotIn('c.txt', tabs[0])
        self.assertIn('c.txt', tabs[1])
        (p / 'e.md').write_text('# e\n')
        out = self.run_ws(exts, ['cmd rename_file', 'key ctrl+a', 'type ' + str(p / 'f.md'), 'key Return',
                                 'wait 100', 'print-tabs', 'cmd undo_workspace_edit', 'wait 100', 'print-tabs'],
                          files=('e.md',))
        tabs = [l for l in out if l.startswith('tabs=')]
        self.assertEqual(tabs[0], 'tabs=*f.md', out)
        self.assertEqual(tabs[1], 'tabs=*e.md', out)
        self.assertEqual((p / 'e.md').read_text(), '# e\n')

    def test_crash_during_file_operations_is_rolled_back(self):
        p = self.proj
        (p / 'old.txt').write_text('old\n')
        body = edit(self.op('create', p / 'new.txt'), (str(p / 'c.txt'), '-', [(1, 1, 1, 6, 'THIRD')]),
                    self.op('rename', p / 'b.go', to=p / 'renamed.go'), self.op('delete', p / 'old.txt'))
        exts = self.ext({'go': 'apply LEN\n' + body}, features='workspace-edits file-operations',
                        project='write')
        env = dict(self.env, RHUN_TEST_EDIT_CRASH='3')
        script = self.work / 'crash.rsc'
        script.write_text('\n'.join(['wait 100', 'cmd wsx.go', 'wait-ext wsx running', 'wait 600', 'quit']) + '\n')
        import subprocess
        r = subprocess.run([str(host.EXE), str(p), '--headless', '1000x600', '--scale', '1',
                            '--extensions', str(exts), '--script', str(script)], env=env,
                           capture_output=True, timeout=60)
        self.assertEqual(r.returncode, 70, r.stderr)
        self.assertTrue((p / 'renamed.go').exists())               # three steps: create, write, rename
        out = self.run_ws(exts, ['print-journal', 'print-toast'], files=())
        self.assertIn('journal=none', out)
        self.assertFalse((p / 'new.txt').exists())
        self.assertEqual((p / 'c.txt').read_text(), 'third file\n')
        self.assertEqual((p / 'b.go').read_text(), 'package b\n')
        self.assertFalse((p / 'renamed.go').exists())
        self.assertEqual((p / 'old.txt').read_text(), 'old\n')


for name in dir(host.Host):
    if name.startswith('test_'):
        setattr(Ws, name, None)

if __name__ == '__main__':
    unittest.main()
