#!/usr/bin/env python3
"""Inlay hints (editor presentation stage 8, feature inlay-hints): hints drawn as virtual text,
their tooltips, a part's command and place to go, a double click applying a hint's edits, hints
moving with edits, answers replacing a provider's hints on the lines asked about, broken answers,
the setting, and a provider that stops. Driven headlessly with the fake extension
tests/ext/present.py."""
import json
import unittest

pres = __import__('presentation')


def part(label, tip='', extra=''):
    return f'{len(label.encode())} {len(tip.encode())} {len(extra.encode())}\n{label}{tip}{extra}'


def hint(line, col, side, parts, extra=''):
    return f'{line} {col} {side} {len(parts)} {len(extra.encode())}\n' + ''.join(parts) + extra


def body(*hints):
    return f'{len(hints)}\n' + ''.join(hints)


# x: i32 (a type, written out by a double click); y: (part) i32 (goes to line 1); fmt: (runs a)
HINTS = body(hint(2, 10, 'after', [part(': i32', 'the type of x')], 'edit 2 10 2 10 5\n: i32'),
             hint(3, 10, 'after', [part(': '), part('i32', '', 'goto 1 4 0\n')]),
             hint(4, 14, 'before', [part('fmt:', '', 'command a 3\nabc')]))


class Hints(pres.Base):
    def setUp(self):
        super().setUp()
        ini = self.exts / 'rhun-tests/present/extension.ini'
        ini.write_text(ini.read_text() + '[provides]\ninlay_hints = *.rs\n', encoding='utf-8')
        self.steps({}, hello='hello 1 inlay-hints')
        self.answer(HINTS)

    def answer(self, *bodies):
        path = self.exts / 'rhun-tests/present/answers.json'
        path.write_text(json.dumps({'inlay-hints': [['ok {ID} {LEN}', b] for b in bodies]}),
                        encoding='utf-8')
        self.env['PRESENT_ANSWERS'] = path.as_posix()

    def asked(self):
        if not self.plog.exists():
            return []
        return [l.split(' ', 1)[1] for l in self.plog.read_text(errors='replace').splitlines()
                if ' inlay-hints ' in l and l.split(' ')[0] != '0']

    def hints(self, out):
        return [l for l in out if l.startswith('hint ')]

    def xy(self, out):
        return [tuple(map(int, l.split())) for l in out if len(l.split()) == 2 and l.split()[0].isdigit()]

    def test_hints_drawn_as_virtual_text(self):
        out = self.run_p(self.start() + ['print-present hints', 'print-xy 2 10', 'print-xy 2 11',
                                         'print-xy 4 14', 'print-xy 4 15'])
        self.assertEqual(self.hints(out), ['hint 2 10 after label=: i32 edits=1',
                                           'hint 3 10 after label=: |i32',
                                           'hint 4 14 before label=fmt:'])
        (x10, y), (x11, _), (x14, _), (x15, _) = self.xy(out)
        # the caret rule: before an after-hint's text at its own position; ";" after five cells
        self.assertEqual(x11 - x10, 6 * 7)
        self.assertEqual(x15 - x14, 1 * 7)          # the caret at 14 goes after "fmt:"
        asked = self.asked()
        self.assertEqual(len(asked), 1, asked)
        self.assertRegex(asked[0], r'^inlay-hints \d+ \d+ 1 \d+$')
        out = self.run_p(self.start() + [f'print-hit {x10 + 14} {y}'])
        self.assertIn('inlay hint 2 10', out)
        path = self.work / 'hints.ppm'
        self.run_p(self.start() + [f'shot {path}'])
        self.assertTrue(path.exists())

    def test_tooltip_command_goto_and_edits(self):
        out = self.run_p(self.start() + ['print-xy 2 10', 'print-xy 3 10', 'print-xy 4 14'])
        (x2, y2), (x3, y3), (x4, y4) = self.xy(out)
        out = self.run_p(self.start() + [f'move {x2 + 14} {y2}', 'wait 650', 'print-tip'])
        self.assertIn('the type of x', '\n'.join(out))
        # "i32" after ": " (two cells) goes to line 1 column 4
        out = self.run_p(self.start() + [f'click {x3 + 3 * 7 + 3} {y3}', 'print-state'])
        self.assertIn('line=1 col=4 ', [l for l in out if l.startswith('tabs=')][0])
        # fmt: runs present.a with its arguments
        self.steps({}, hello='hello 1 inlay-hints command-args')
        self.run_p(self.start() + [f'click {x4 - 14} {y4}', 'wait 200'])
        self.assertTrue(any(' ref 3' in l for l in self.events('run present.a')), self.events('run'))
        # a double click writes the type out, one undo step
        out = self.run_p(self.start() + [f'click {x2 + 14} {y2}', f'click {x2 + 14} {y2}', 'print-doc',
                                         'key ctrl+z', 'print-doc'])
        doc = '\n'.join(out)
        self.assertIn('let x: i32 = 1;', doc)
        self.assertEqual(doc.count('let x = 1;'), 1)

    def test_hints_move_with_edits_and_answers_replace_them(self):
        self.answer(HINTS, body(hint(2, 11, 'after', [part(': u8')])))
        out = self.run_p(self.start() + ['key ctrl+Home', 'key Down', 'key Home', 'type z',
                                         'print-present hints', 'wait 700', 'print-present hints'])
        h = self.hints(out)
        self.assertEqual(h[:3], ['hint 2 11 after label=: i32 edits=1', 'hint 3 10 after label=: |i32',
                                 'hint 4 14 before label=fmt:'])
        # the second answer holds one hint: the others on the lines asked about go
        self.assertEqual(h[3:], ['hint 2 11 after label=: u8'])
        self.assertEqual(len(self.asked()), 2)

    def test_broken_answers_are_dropped(self):
        for b in (body(hint(2, 10, 'aside', [part('x')])), body(hint(2, 10, 'after', [part('a\nb')])),
                  body(hint(2, 10, 'after', [part('x' * 121)])), '2\n' + hint(2, 10, 'after', [part('x')]),
                  body(hint(0, 1, 'after', [part('x')]))):
            self.answer(b)
            out = self.run_p(self.start() + ['print-present hints'])
            self.assertEqual(self.hints(out), [], b)

    def test_setting_off_and_provider_stopping(self):
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[editor]\ninlay_hints = false\n')
        out = self.run_p(self.start() + ['print-xy 2 10', 'print-xy 2 11'])
        (x10, _), (x11, _) = self.xy(out)
        self.assertEqual(x11 - x10, 7)
        self.assertEqual(self.asked(), [])
        config.write_text(config.read_text().replace('inlay_hints = false', 'inlay_hints = true'))
        out = self.run_p(self.start() + ['print-present hints', 'ext-set present stop', 'wait 300',
                                         'print-present hints'])
        self.assertEqual(len(self.hints(out)), 3)


if __name__ == '__main__':
    unittest.main()
