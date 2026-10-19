#!/usr/bin/env python3
"""Multiple selections: the commands, keys and mouse gestures that make them, motion, editing at
every selection with one undo step, line commands, word wrap and the 512 cap.

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

DOC = ('echo @doc', 'print-doc')
ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
# text cells at scale 1 in a 1000x700 window, without the explorer
X0, Y0, CW, LH = 56, 86, 7, 21


def cell(line, col):
    """The middle of a text cell (lines and columns from 1)."""
    return X0 + (col - 1) * CW, Y0 + (line - 1) * LH


class MultiCursor(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-multicursor-')
        self.work = Path(self.tmp.name).resolve()
        self.file = self.work / 'text.txt'
        self.configure()

    def tearDown(self):
        for _ in range(50):
            try:
                self.tmp.cleanup()
                return
            except OSError:
                time.sleep(0.2)
        self.tmp.cleanup()

    def configure(self, extra=''):
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                          '[editor]\ncursor_blink = false\nauto_pairs = false\n' + extra +
                          '[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')

    def run_editor(self, text, actions, size='1000x700'):
        self.file.write_bytes(text.encode('utf-8'))
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        env = dict(os.environ, HOME=self.work.as_posix(),
                   XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                   XDG_STATE_HOME=(self.work / 'state').as_posix(),
                   XDG_DATA_HOME=(self.work / 'data').as_posix())
        result = subprocess.run([str(EXE), self.work.as_posix(), self.file.as_posix(), '--headless',
                                 size, '--scale', '1', '--script', script.as_posix()],
                                env=env, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        out = result.stdout.decode('utf-8')
        self.assertNotIn('unknown command', out)
        return out

    @staticmethod
    def selections(out):
        """Every print-selections block: a list of (anchor, cursor) tuples, primary first."""
        blocks, lines = [], out.splitlines()
        for i, line in enumerate(lines):
            if line.startswith('sels='):
                n = int(line[5:])
                rows = [tuple(map(int, row.split())) for row in lines[i + 1:i + 1 + n]]
                blocks.append([((a, b), (c, d)) for a, b, c, d in rows])
        return blocks

    @staticmethod
    def docs(out):
        """The text of every print-doc that DOC (echo @doc first) asked for."""
        texts, at = [], 0
        while (at := out.find('@doc\n', at)) >= 0:
            end = out.index('\n<eod>\n', at)
            texts.append(out[at + 5:end])
            at = end
        return texts

    # ---------------- creating selections ----------------

    def test_ctrl_d_adds_next_matches_type_and_undo(self):
        out = self.run_editor('foo bar foo\nfoo baz\nfoobar foo\n', [
            'key ctrl+d', 'print-selections', 'key ctrl+d', 'key ctrl+d', 'print-selections',
            'type X', *DOC, 'print-selections', 'key ctrl+z', *DOC, 'print-selections',
            'key ctrl+shift+z', *DOC])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((1, 1), (1, 4))])
        # whole words of the same case: foobar is skipped; the newest is primary
        self.assertEqual(sels[1], [((2, 1), (2, 4)), ((1, 9), (1, 12)), ((1, 1), (1, 4))])
        docs = self.docs(out)
        self.assertEqual(docs[0], 'X bar X\nX baz\nfoobar foo\n')
        self.assertEqual(sels[2], [((2, 2), (2, 2)), ((1, 8), (1, 8)), ((1, 2), (1, 2))])
        # one undo step brings back the text and the three selections; redo the text
        self.assertEqual(docs[1], 'foo bar foo\nfoo baz\nfoobar foo\n')
        self.assertEqual(sels[3], sels[1])
        self.assertEqual(docs[2], docs[0])

    def test_ctrl_d_on_a_selection_matches_exact_bytes_and_says_when_none_are_left(self):
        out = self.run_editor('ab abc xab\nab\n', [
            'key shift+Right', 'key shift+Right', 'key ctrl+d', 'key ctrl+d', 'print-selections',
            'key ctrl+d', 'key ctrl+d', 'key ctrl+d', 'print-selections', 'print-toast'])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((1, 9), (1, 11)), ((1, 4), (1, 6)), ((1, 1), (1, 3))])
        self.assertEqual(len(sels[1]), 4)
        self.assertIn('No more matches', out)

    def test_move_selection_to_next_match_keeps_the_others(self):
        out = self.run_editor('foo foo foo foo\n', [
            'key ctrl+d', 'key ctrl+d', 'cmd select_next_skip', 'print-selections',
            'key Escape', 'cmd select_next_skip', 'print-selections'])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((1, 9), (1, 12)), ((1, 1), (1, 4))])
        self.assertEqual(sels[1], [((1, 13), (1, 16))])

    def test_add_cursor_below_type_backspace_and_word_delete(self):
        out = self.run_editor('alpha one\nbeta two\ngamma three\n', [
            'key End', 'key ctrl+alt+Down', 'key ctrl+alt+Down', 'print-selections',
            'type !', *DOC, 'key BackSpace', 'key ctrl+BackSpace', *DOC,
            'key ctrl+z', *DOC, 'print-selections',
            'key Escape', 'key ctrl+alt+Up', 'key ctrl+alt+Up', 'print-selections'])
        sels = self.selections(out)
        # the primary's column (10) on every line, clamped; the newest is primary
        self.assertEqual(sels[0], [((3, 10), (3, 10)), ((2, 9), (2, 9)), ((1, 10), (1, 10))])
        docs = self.docs(out)
        self.assertEqual(docs[0], 'alpha one!\nbeta two!\ngamma thr!ee\n')
        # Backspace takes the "!"s, ctrl+Backspace the words before the carets
        self.assertEqual(docs[1], 'alpha \nbeta \ngamma ee\n')
        # the two deletes were one undo step, and undo brings back the carets as they were
        self.assertEqual(docs[2], 'alpha one!\nbeta two!\ngamma thr!ee\n')
        self.assertEqual(sels[1], [((3, 11), (3, 11)), ((2, 10), (2, 10)), ((1, 11), (1, 11))])
        # add above goes above the topmost caret, at the primary's column
        self.assertEqual(sels[2], [((1, 11), (1, 11)), ((2, 10), (2, 10)), ((3, 11), (3, 11))])

    def test_select_all_matches(self):
        out = self.run_editor('cat Cat cat\ncatalog cat\n', [
            'key ctrl+shift+l', 'print-selections', 'type dog', *DOC])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((1, 1), (1, 4)), ((1, 9), (1, 12)), ((2, 9), (2, 12))])
        self.assertEqual(self.docs(out), ['dog Cat dog\ncatalog dog\n'])

    def test_alt_click_adds_and_removes_carets_and_a_plain_click_collapses(self):
        out = self.run_editor('one two\nthree four\nfive\n', [
            'click %d %d alt' % cell(2, 3), 'click %d %d alt' % cell(3, 2), 'print-selections',
            'click %d %d alt' % cell(2, 3), 'print-selections', 'print-state',
            'click %d %d' % cell(1, 5), 'print-selections'])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((3, 2), (3, 2)), ((2, 3), (2, 3)), ((1, 1), (1, 1))])
        self.assertEqual(sels[1], [((3, 2), (3, 2)), ((1, 1), (1, 1))])
        self.assertIn(' sels=2 ', out)
        self.assertEqual(sels[2], [((1, 5), (1, 5))])

    def test_alt_drag_adds_a_selection_and_alt_double_click_a_word(self):
        out = self.run_editor('one two three\nfour five six\n', [
            'drag %d %d %d %d alt' % (*cell(2, 1), *cell(2, 5)), 'print-selections',
            'click %d %d alt' % cell(1, 6), 'click %d %d alt' % cell(1, 6), 'print-selections'])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((2, 1), (2, 5)), ((1, 1), (1, 1))])
        self.assertEqual(sels[1][0], ((1, 5), (1, 8)))
        self.assertEqual(len(sels[1]), 3)

    def test_ctrl_as_the_multi_cursor_modifier(self):
        self.configure('multi_cursor_modifier = ctrl\n')
        out = self.run_editor('one\ntwo\nthree\n', [
            'click %d %d ctrl' % cell(2, 2), 'print-selections',
            'click %d %d alt' % cell(3, 2), 'print-selections'])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((2, 2), (2, 2)), ((1, 1), (1, 1))])
        self.assertEqual(sels[1], [((3, 2), (3, 2))])

    def test_shift_alt_drag_selects_a_box_and_typing_replaces_it(self):
        out = self.run_editor('abcdef\nab\n\tcdef\na\nabcdefgh\n', [
            'drag %d %d %d %d shift+alt' % (*cell(1, 3), *cell(5, 5)), 'print-selections',
            'type X', *DOC, 'key ctrl+z', 'print-selections'])
        sels = self.selections(out)
        # columns 2..4, tabs expanded; "ab" ends at the box's edge, "a" left of it (skipped);
        # the moving corner is primary
        self.assertEqual(sels[0], [((5, 3), (5, 5)), ((3, 2), (3, 2)), ((2, 3), (2, 3)),
                                   ((1, 3), (1, 5))])
        self.assertEqual(self.docs(out), ['abXef\nabX\n\tXcdef\na\nabXefgh\n'])
        self.assertEqual(sels[1], sels[0])

    def test_column_select_keys_grow_a_box(self):
        out = self.run_editor('abcdef\nabcdef\nabcdef\n', [
            'key Right', 'key ctrl+shift+alt+Down', 'key ctrl+shift+alt+Down',
            'key ctrl+shift+alt+Right', 'key ctrl+shift+alt+Right', 'print-selections',
            'key ctrl+shift+alt+Up', 'print-selections'])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((3, 2), (3, 4)), ((2, 2), (2, 4)), ((1, 2), (1, 4))])
        self.assertEqual(sels[1], [((2, 2), (2, 4)), ((1, 2), (1, 4))])

    def test_escape_remove_last_and_line_ends(self):
        out = self.run_editor('one\ntwo\nthree\nfour\n', [
            'key ctrl+alt+Down', 'key ctrl+alt+Down', 'key ctrl+u', 'print-selections',
            'key Escape', 'print-selections', 'key ctrl+a', 'key shift+alt+i', 'print-selections',
            'type ;', *DOC])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((2, 1), (2, 1)), ((1, 1), (1, 1))])
        self.assertEqual(sels[1], [((2, 1), (2, 1))])
        self.assertEqual(sels[2], [((4, 5), (4, 5)), ((2, 4), (2, 4)), ((3, 6), (3, 6)),
                                   ((1, 4), (1, 4))])
        self.assertEqual(self.docs(out), ['one;\ntwo;\nthree;\nfour;\n'])

    # ---------------- motion ----------------

    def test_motions_merge_overlapping_selections(self):
        out = self.run_editor('abcdef\n', [
            'click %d %d alt' % cell(1, 3), 'key shift+Right', 'print-selections',
            'key shift+Right', 'print-selections', 'key shift+Right', 'print-selections',
            'key Left', 'print-selections'])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((1, 3), (1, 4)), ((1, 1), (1, 2))])
        # touching selections stay apart; overlapping ones merge, in the primary's direction
        self.assertEqual(sels[1], [((1, 3), (1, 5)), ((1, 1), (1, 3))])
        sels.pop(1)
        self.assertEqual(sels[1], [((1, 1), (1, 6))])
        self.assertEqual(sels[2], [((1, 1), (1, 1))])

    def test_vertical_motion_keeps_each_columns_over_short_lines(self):
        out = self.run_editor('0123456789\nabcdefghijkl\nx\n0123456789\nabcdefghijkl\n', [
            'key End', 'click %d %d alt' % cell(2, 4), 'key Down', 'print-selections',
            'key Down', 'print-selections', 'key Down', 'print-selections'])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((3, 2), (3, 2)), ((2, 11), (2, 11))])
        self.assertEqual(sels[1], [((4, 4), (4, 4)), ((3, 2), (3, 2))])
        self.assertEqual(sels[2], [((5, 4), (5, 4)), ((4, 11), (4, 11))])

    def test_home_end_and_word_motions_at_every_caret(self):
        out = self.run_editor('  one two\n  three four\n', [
            'key End', 'key ctrl+alt+Down', 'key Home', 'print-selections',
            'key ctrl+Right', 'print-selections', 'key shift+End', 'type X', *DOC])
        sels = self.selections(out)
        self.assertEqual(sels[0], [((2, 3), (2, 3)), ((1, 3), (1, 3))])
        self.assertEqual(sels[1], [((2, 8), (2, 8)), ((1, 6), (1, 6))])
        self.assertEqual(self.docs(out), ['  oneX\n  threeX\n'])

    # ---------------- line commands ----------------

    def test_line_commands_with_carets_on_three_lines(self):
        three = ['key Down', 'key ctrl+alt+Down', 'key ctrl+alt+Down']
        out = self.run_editor('one\ntwo\nthree\nfour\nfive\n', [
            *three, 'key ctrl+shift+d', *DOC, 'print-selections', 'key ctrl+z', *DOC,
            'print-selections', 'key alt+Down', *DOC, 'print-selections', 'key alt+Up',
            'key alt+Up', *DOC, 'print-selections', 'key alt+Up', *DOC,
            'key ctrl+shift+k', *DOC, 'print-selections', 'key ctrl+z', *DOC,
            'print-selections', 'key ctrl+l', 'print-selections', 'key ctrl+l', 'print-selections'])
        docs, sels = self.docs(out), self.selections(out)
        carets = lambda *lines: [((line, 1), (line, 1)) for line in lines]
        # each line once below itself, the carets onto the copies; one undo step back
        self.assertEqual(docs[0], 'one\ntwo\ntwo\nthree\nthree\nfour\nfour\nfive\n')
        self.assertEqual(sels[0], carets(7, 5, 3))
        self.assertEqual(docs[1], 'one\ntwo\nthree\nfour\nfive\n')
        self.assertEqual(sels[1], carets(4, 3, 2))
        # the lines move as one block; at the top nothing moves
        self.assertEqual(docs[2], 'one\nfive\ntwo\nthree\nfour\n')
        self.assertEqual(sels[2], carets(5, 4, 3))
        self.assertEqual(docs[3], 'two\nthree\nfour\none\nfive\n')
        self.assertEqual(sels[3], carets(3, 2, 1))
        self.assertEqual(docs[4], docs[3])
        # the lines go, one caret is left; undo brings them and the carets back
        self.assertEqual(docs[5], 'one\nfive\n')
        self.assertEqual(sels[4], carets(1))
        self.assertEqual(docs[6], docs[3])
        self.assertEqual(sels[5], carets(3, 2, 1))
        # Select Line: whole lines, then one more each (they merge)
        self.assertEqual(sels[6], [((3, 1), (4, 1)), ((2, 1), (3, 1)), ((1, 1), (2, 1))])
        self.assertEqual(sels[7], [((1, 1), (5, 1))])

    def test_toggle_comment_and_insert_line_above_at_several_carets(self):
        self.file = self.work / 'code.c'
        out = self.run_editor('int a;\n  int b;\n\n}\n', [
            'key ctrl+alt+Down', 'key ctrl+alt+Down', 'key ctrl+/', *DOC, 'key ctrl+/', *DOC,
            'key ctrl+alt+Down', 'key ctrl+shift+Return', 'type X', *DOC, 'key ctrl+z',
            'key ctrl+z', *DOC])
        docs = self.docs(out)
        self.assertEqual(docs[0], '// int a;\n  // int b;\n\n}\n')
        self.assertEqual(docs[1], 'int a;\n  int b;\n\n}\n')
        # a level more above a closing bracket; the caret at the end of the indentation
        self.assertEqual(docs[2], 'X\nint a;\n  X\n  int b;\nX\n\n    X\n}\n')
        self.assertEqual(docs[3], docs[1])

    # ---------------- clipboard ----------------

    def test_paste_paired_and_spread(self):
        out = self.run_editor('one\ntwo\nthree\nx\ny\nz\n', [
            'key ctrl+alt+Down', 'key ctrl+alt+Down', 'key shift+End', 'key ctrl+c',
            'key Escape', 'key ctrl+End', 'key Up', 'key Up', 'key Up',
            'key ctrl+alt+Down', 'key ctrl+alt+Down', 'key End', 'key ctrl+v', *DOC])
        self.assertEqual(self.docs(out), ['one\ntwo\nthree\nxone\nytwo\nzthree\n'])
        out = self.run_editor('a\nb\nc\n1\n2\n3\n', [
            'key shift+Down', 'key shift+Down', 'key shift+End', 'key ctrl+c', 'key ctrl+End',
            'key Up', 'key Up', 'key Up', 'key ctrl+alt+Down', 'key ctrl+alt+Down', 'key End',
            'key ctrl+v', *DOC])
        self.assertEqual(self.docs(out), ['a\nb\nc\n1a\n2b\n3c\n'])

    # ---------------- word wrap and limits ----------------

    def test_word_wrap_rows(self):
        self.configure('word_wrap = true\n')
        line = 'word ' * 40
        out = self.run_editor(line + '\n' + line + '\n', [
            'key ctrl+alt+Down', 'print-selections', 'key Down', 'print-selections', 'type #',
            *DOC], size='400x500')
        sels = self.selections(out)
        self.assertEqual(sels[0], [((2, 1), (2, 1)), ((1, 1), (1, 1))])
        # one visual row down each: both move by the same row width on their own line
        (_, (l1, c1)), (_, (l2, c2)) = sels[1]
        self.assertEqual((l1, l2), (2, 1))
        self.assertEqual(c1, c2)
        self.assertGreater(c1, 1)
        self.assertEqual(self.docs(out)[0].count('#'), 2)

    def test_at_most_512_selections(self):
        out = self.run_editor('x\n' * 600, [
            'key shift+Right', 'key ctrl+shift+l', 'print-state', 'print-toast',
            'click %d %d alt' % cell(5, 1), 'print-toast'])
        self.assertIn(' sels=512 ', out)
        self.assertIn('Selected the 512 matches nearest the cursor.', out)
        self.assertIn('At most 512 selections.', out)


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0], *sys.argv[1:]])
