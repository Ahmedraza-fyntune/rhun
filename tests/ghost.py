#!/usr/bin/env python3
"""Inline completion (editor presentation, feature inline-complete): ghost text after the caret
from the language's provider, Tab taking it whole, ctrl+Right a word, typing through it, Escape and
caret moves dismissing it, multi-line ghosts as rows below, and the typing pause. Driven headlessly
with the fake extension tests/ext/present.py."""
import json
import unittest

pres = __import__('presentation')


def item(l1, c1, l2, c2, text, extra=''):
    return f'{l1} {c1} {l2} {c2} {len(text.encode())} {len(extra.encode())}\n{text}{extra}'


def body(*items):
    return f'{len(items)}\n' + ''.join(items)


END2 = ['key ctrl+Home', 'key Down', 'key End']     # after "    let x = 1;"


class Ghost(pres.Base):
    def setUp(self):
        super().setUp()
        ini = self.exts / 'rhun-tests/present/extension.ini'
        ini.write_text(ini.read_text() + '[provides]\ninline_complete = *.rs\n', encoding='utf-8')
        self.steps({}, hello='hello 1 inline-complete')
        self.answer(body(item(2, 15, 2, 15, ' // one')))

    def answer(self, b):
        path = self.exts / 'rhun-tests/present/answers.json'
        path.write_text(json.dumps({'inline-complete': ['ok {ID} {LEN}', b]}), encoding='utf-8')
        self.env['PRESENT_ANSWERS'] = path.as_posix()

    def ghost(self, out):
        return [l for l in out if l.startswith('ghost ')]

    def asked(self):
        if not self.plog.exists():
            return []
        return [l.split(' ', 1)[1] for l in self.plog.read_text(errors='replace').splitlines()
                if ' inline-complete ' in l and l.split(' ')[0] != '0']

    def doc(self, out):
        return '\n'.join(out)

    def test_invoked_ghost_and_tab_takes_it(self):
        out = self.run_p(self.start() + END2 + ['cmd inline_complete', 'wait 200', 'print-present ghost',
                                                 'print-xy 2 15', 'key Tab', 'print-present ghost', 'print-doc'])
        self.assertEqual(self.ghost(out), ['ghost 2:15  // one', 'ghost none'])
        self.assertIn('    let x = 1; // one', out)
        self.assertRegex(self.asked()[0], r'^inline-complete \d+ \d+ 2 15 invoked$')
        path = self.work / 'ghost.ppm'
        self.run_p(self.start() + END2 + ['cmd inline_complete', 'wait 200', f'shot {path}'])
        self.assertTrue(path.exists())

    def test_typing_through_escape_and_moves(self):
        self.answer(body(item(2, 15, 2, 15, 'foo bar')))
        out = self.run_p(self.start() + END2 + ['cmd inline_complete', 'wait 200', 'type fo', 'print-present ghost',
                                                 'type x', 'print-present ghost'])
        self.assertEqual(self.ghost(out), ['ghost 2:17 o bar', 'ghost none'])
        out = self.run_p(self.start() + END2 + ['cmd inline_complete', 'wait 200', 'key Escape',
                                                 'print-present ghost', 'cmd inline_complete', 'wait 200',
                                                 'key Left', 'print-present ghost'])
        self.assertEqual(self.ghost(out), ['ghost none', 'ghost none'])

    def test_ctrl_right_takes_a_word(self):
        self.answer(body(item(2, 15, 2, 15, 'foo bar')))
        out = self.run_p(self.start() + END2 + ['cmd inline_complete', 'wait 200', 'key ctrl+Right',
                                                 'print-present ghost', 'print-doc'])
        self.assertEqual(self.ghost(out), ['ghost 2:18  bar'])
        self.assertIn('    let x = 1;foo', out)

    def test_items_that_do_not_fit_are_skipped(self):
        # the first claims "zz" before the caret: the second fits
        self.answer(body(item(2, 13, 2, 15, 'zz; // a'), item(2, 15, 2, 15, ' b'), item(2, 13, 2, 15, '1; // c')))
        out = self.run_p(self.start() + END2 + ['cmd inline_complete', 'wait 200', 'print-present ghost'])
        self.assertEqual(self.ghost(out), ['ghost 2:15  b'])
        self.answer(body(item(2, 13, 2, 15, '1; // c')))
        out = self.run_p(self.start() + END2 + ['cmd inline_complete', 'wait 200', 'print-present ghost'])
        self.assertEqual(self.ghost(out), ['ghost 2:15  // c'])

    def test_lines_below_are_rows(self):
        self.answer(body(item(2, 15, 2, 15, '\n    let z = 3;\n    let w = 4;')))
        out = self.run_p(self.start() + END2 + ['print-xy 3 1', 'cmd inline_complete', 'wait 200', 'print-viewport',
                                                 'print-xy 3 1', 'key Tab', 'print-doc'])
        (_, y3a), (_, y3b) = [tuple(map(int, l.split())) for l in out if len(l.split()) == 2 and l[0].isdigit()]
        self.assertEqual(y3b - y3a, 2 * 21)      # two rows of ghost text before line 3
        self.assertTrue(any(l.startswith('view mode=rows') for l in out), out)
        self.assertIn('    let z = 3;', out)

    def test_lines_below_the_last_line_show_after_it(self):
        # the caret on the document's last (empty) line: no next line to sit before, the rows follow it
        self.answer(body(item(6, 1, 6, 1, 'aaaa\nbbbb\ncccc')))
        out = self.run_p(['key ctrl+End', 'print-xy 6 1'])
        _, y = map(int, out[-1].split())
        plain = self.shot(self.start() + ['key ctrl+End'], 'plain.ppm')
        ghost = self.shot(self.start() + ['key ctrl+End', 'cmd inline_complete', 'wait 200'], 'ghost.ppm')
        out = self.run_p(self.start() + ['key ctrl+End', 'cmd inline_complete', 'wait 200', 'print-present ghost'])
        self.assertEqual(self.ghost(out), ['ghost 6:1 aaaa\\nbbbb\\ncccc'])
        for row in (1, 2):              # the second and third lines, in the rows below line 6
            yy = y + row * 21
            self.assertTrue(self.differ(plain, ghost, yy), row)
        yy = y + 3 * 21                 # nothing past them
        self.assertFalse(self.differ(plain, ghost, yy))

    def test_rows_below_the_last_line_scroll_into_view(self):
        # without scroll_past_end the view stops at the end, which now ends with the ghost's rows
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[editor]\nscroll_past_end = false\n')
        (self.proj / 'long.rs').write_text(''.join(f'let v{i} = {i};\n' for i in range(100)) + 'x', encoding='utf-8')
        self.answer(body(item(101, 2, 101, 2, '1\nbbbb\ncccc')))
        out = self.run_p(self.start() + ['key ctrl+End', 'wait 100', 'print-xy 101 1', 'cmd inline_complete', 'wait 200',
                                         'print-present ghost', 'move 500 300', 'scroll 3000', 'wait 100',
                                         'print-xy 101 1'], files=('long.rs',))
        self.assertEqual(self.ghost(out), ['ghost 101:2 1\\nbbbb\\ncccc'])
        (_, before), (_, after) = [tuple(map(int, l.split())) for l in out if len(l.split()) == 2 and l[0].isdigit()]
        # up by the two rows below it, less the gap lines mode left under the last line
        self.assertTrue(21 < before - after <= 2 * 21, (before, after))

    def differ(self, a, b, y):
        return any(pres.host.ppm_pixel(a, x, yy) != pres.host.ppm_pixel(b, x, yy)
                   for yy in range(y, y + 21, 2) for x in range(40, 140, 2))

    def test_typing_pause_asks_and_the_setting(self):
        out = self.run_p(self.start() + END2 + ['type z', 'wait 500', 'print-present ghost'])
        asked = self.asked()
        self.assertTrue(asked and asked[-1].endswith(' typed'), asked)
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[editor]\ninline_complete = false\n')
        n = len(self.asked())
        self.run_p(self.start() + END2 + ['type z', 'wait 500'])
        self.assertEqual(len(self.asked()), n)


if __name__ == '__main__':
    unittest.main()
