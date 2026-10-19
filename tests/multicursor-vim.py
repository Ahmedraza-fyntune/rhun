#!/usr/bin/env python3
"""Vim mode with several cursors: gb, insert mode at every cursor, Esc, operators, yank and put
paired, ".", undo, visual mode, and the keys that stay about one place.

Runs the real editor headless with --script. print-selections lists every selection as
"L1 C1 L2 C2" (anchor, then cursor; lines and byte columns from 1), the primary first.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
DOC = ('echo @doc', 'print-doc')


def carets(*cells):
    return [((line, col), (line, col)) for line, col in cells]


class MultiCursorVim(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-multicursor-vim-')
        self.work = Path(self.tmp.name).resolve()
        self.file = self.work / 'text.txt'
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                          '[editor]\ncursor_blink = false\nauto_pairs = false\nvim_mode = true\n'
                          '[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')

    def tearDown(self):
        for _ in range(50):
            try:
                self.tmp.cleanup()
                return
            except OSError:
                time.sleep(0.2)
        self.tmp.cleanup()

    def run_editor(self, text, actions):
        self.file.write_bytes(text.encode('utf-8'))
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        env = dict(os.environ, HOME=self.work.as_posix(),
                   XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                   XDG_STATE_HOME=(self.work / 'state').as_posix(),
                   XDG_DATA_HOME=(self.work / 'data').as_posix())
        result = subprocess.run([str(EXE), self.work.as_posix(), self.file.as_posix(), '--headless',
                                 '1000x700', '--scale', '1', '--script', script.as_posix()],
                                env=env, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        out = result.stdout.decode('utf-8')
        self.assertNotIn('unknown command', out)
        return out

    @staticmethod
    def selections(out):
        blocks, lines = [], out.splitlines()
        for i, line in enumerate(lines):
            if line.startswith('sels='):
                n = int(line[5:])
                rows = [tuple(map(int, row.split())) for row in lines[i + 1:i + 1 + n]]
                blocks.append([((a, b), (c, d)) for a, b, c, d in rows])
        return blocks

    @staticmethod
    def docs(out):
        texts, at = [], 0
        while (at := out.find('@doc\n', at)) >= 0:
            end = out.index('\n<eod>\n', at)
            texts.append(out[at + 5:end])
            at = end
        return texts

    @staticmethod
    def modes(out):
        return [line.split(' vim=')[1].split()[0] for line in out.splitlines()
                if line.startswith('tabs=') and ' vim=' in line]

    def test_gb_ciw_then_escape_keeps_the_cursors_and_escape_again_leaves_one(self):
        out = self.run_editor('foo bar foo\nbaz foo qux\n', [
            'type gb', 'print-selections', 'type gb', 'print-selections', 'type ciw', 'print-state',
            'type XY', 'key Escape', *DOC, 'print-selections', 'print-state', 'key Escape',
            'print-selections', 'type u', *DOC, 'print-selections'])
        sels, docs = self.selections(out), self.docs(out)
        # a cursor at the start of each next occurrence; the newest is primary
        self.assertEqual(sels[0], carets((1, 9), (1, 1)))
        self.assertEqual(sels[1], carets((2, 5), (1, 9), (1, 1)))
        self.assertEqual(self.modes(out), ['insert', 'normal'])
        self.assertEqual(docs[0], 'XY bar XY\nbaz XY qux\n')
        # each cursor steps back onto the last character typed
        self.assertEqual(sels[2], carets((2, 6), (1, 9), (1, 2)))
        self.assertEqual(sels[3], carets((2, 6)))
        # one undo step: the text and the cursors as they were
        self.assertEqual(docs[1], 'foo bar foo\nbaz foo qux\n')
        self.assertEqual(sels[4], sels[1])

    def test_append_at_three_cursors_and_dot(self):
        out = self.run_editor('one two\nthree four\nfive six\nseven\neight\nnine\n', [
            'key ctrl+alt+Down', 'key ctrl+alt+Down', 'type A', 'type ;', 'key Escape', *DOC,
            'print-selections', 'type 3j', 'type .', *DOC, 'print-selections', 'type u', *DOC])
        sels, docs = self.selections(out), self.docs(out)
        self.assertEqual(docs[0], 'one two;\nthree four;\nfive six;\nseven\neight\nnine\n')
        self.assertEqual(sels[0], carets((3, 9), (2, 11), (1, 8)))
        # "." appends again at every cursor
        self.assertEqual(docs[1], 'one two;\nthree four;\nfive six;\nseven;\neight;\nnine;\n')
        self.assertEqual(sels[1], carets((6, 5), (5, 6), (4, 6)))
        self.assertEqual(docs[2], docs[0])

    def test_dw_and_undo_restores_the_cursors(self):
        out = self.run_editor('alpha beta\ngamma delta\nepsilon zeta\n', [
            'key ctrl+alt+Down', 'key ctrl+alt+Down', 'type dw', *DOC, 'print-selections',
            'type u', *DOC, 'print-selections', 'type x', *DOC])
        sels, docs = self.selections(out), self.docs(out)
        self.assertEqual(docs[0], 'beta\ndelta\nzeta\n')
        self.assertEqual(sels[0], carets((3, 1), (2, 1), (1, 1)))
        self.assertEqual(docs[1], 'alpha beta\ngamma delta\nepsilon zeta\n')
        self.assertEqual(sels[1], carets((3, 1), (2, 1), (1, 1)))
        self.assertEqual(docs[2], 'lpha beta\namma delta\npsilon zeta\n')

    def test_yy_then_p_puts_each_line_back_paired(self):
        out = self.run_editor('one\ntwo\nthree\n', [
            'key ctrl+alt+Down', 'key ctrl+alt+Down', 'type yy', 'type p', *DOC, 'print-selections',
            'type u', *DOC, 'type yiw', 'type P', *DOC])
        sels, docs = self.selections(out), self.docs(out)
        self.assertEqual(docs[0], 'one\none\ntwo\ntwo\nthree\nthree\n')
        self.assertEqual(sels[0], carets((6, 1), (4, 1), (2, 1)))
        self.assertEqual(docs[1], 'one\ntwo\nthree\n')
        self.assertEqual(docs[2], 'oneone\ntwotwo\nthreethree\n')

    def test_visual_mode_at_every_cursor(self):
        out = self.run_editor('abc def\nghi jkl\n', [
            'key ctrl+alt+Down', 'type vl', 'print-selections', 'print-state', 'type d', *DOC,
            'print-selections', 'print-state', 'type u', 'type vel', 'key Escape',
            'print-selections', 'print-state'])
        sels, docs = self.selections(out), self.docs(out)
        # the cursor's character is in the selection, as vim draws it
        self.assertEqual(sels[0], [((2, 1), (2, 2)), ((1, 1), (1, 2))])
        self.assertEqual(docs[0], 'c def\ni jkl\n')
        self.assertEqual(sels[1], carets((2, 1), (1, 1)))
        # Esc leaves visual mode at every cursor
        self.assertEqual(sels[2], carets((2, 4), (1, 4)))
        self.assertEqual(self.modes(out), ['visual', 'normal', 'normal'])

    def test_keys_about_one_place_collapse_and_ctrl_d_still_pages(self):
        text = ''.join('line %d\n' % n for n in range(1, 121))
        out = self.run_editor(text, [
            'key ctrl+alt+Down', 'type J', 'print-selections', *DOC,
            'key ctrl+alt+Down', 'key ctrl+d', 'print-selections'])
        sels, docs = self.selections(out), self.docs(out)
        self.assertEqual(len(sels[0]), 1)
        self.assertTrue(docs[0].startswith('line 1\nline 2 line 3\nline 4\n'), docs[0][:40])
        self.assertEqual(len(sels[1]), 1)
        self.assertGreater(sels[1][0][1][0], 10)


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0], *sys.argv[1:]])
