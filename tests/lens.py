#!/usr/bin/env python3
"""Code lens (editor presentation stage 9, feature code-lens): a row of titles above lines, the
caret stepping over those rows, a click running a lens's command and its tip, lenses moving with
edits, the view staying put when lenses come above its top, unresolved titles, broken answers, the
setting, and a provider that stops. Driven headlessly with the fake extension tests/ext/present.py."""
import json
import unittest

pres = __import__('presentation')


def lens(line, title, extra=''):
    return f'{line} {len(title.encode())} {len(extra.encode())}\n{title}{extra}'


def body(*lenses):
    return f'{len(lenses)}\n' + ''.join(lenses)


LENSES = body(lens(1, 'Run', 'command a 0\n'), lens(1, '2 references', 'tip 9\nused here'), lens(3, ''))


class Lens(pres.Base):
    def setUp(self):
        super().setUp()
        ini = self.exts / 'rhun-tests/present/extension.ini'
        ini.write_text(ini.read_text() + '[provides]\ncode_lens = *.rs\n', encoding='utf-8')
        self.steps({}, hello='hello 1 code-lens')
        self.answer(LENSES)

    def answer(self, *bodies):
        path = self.exts / 'rhun-tests/present/answers.json'
        path.write_text(json.dumps({'code-lens': [['ok {ID} {LEN}', b] for b in bodies]}), encoding='utf-8')
        self.env['PRESENT_ANSWERS'] = path.as_posix()

    def asked(self):
        if not self.plog.exists():
            return []
        return [l.split(' ', 1)[1] for l in self.plog.read_text(errors='replace').splitlines()
                if ' code-lens ' in l and l.split(' ')[0] != '0']

    def lenses(self, out):
        return [l for l in out if l.startswith('lens ')]

    def xy(self, out):
        return [tuple(map(int, l.split())) for l in out if len(l.split()) == 2 and l.split()[0].isdigit()]

    def state(self, out):
        return [l for l in out if l.startswith('tabs=')]

    def test_lens_rows_drawn_above_lines(self):
        out = self.run_p(['print-xy 1 1', 'print-xy 3 1'] + self.start() +
                         ['print-present lenses', 'print-viewport', 'print-xy 1 1', 'print-xy 2 1', 'print-xy 3 1'])
        self.assertEqual(self.lenses(out), ['lens 1 Run +command', 'lens 1 2 references', 'lens 3 …'])
        (x1, y1), (_, y3), (x1b, y1b), (_, y2b), (_, y3b) = self.xy(out)
        self.assertEqual(x1b, x1)
        self.assertEqual(y1b, y1 + 21)            # the document's top: the lens row shows
        self.assertEqual(y2b, y1b + 21)
        self.assertEqual(y3b, y3 + 42)            # two lens rows above it
        self.assertTrue(any(l.startswith('view mode=rows top=1 ') for l in out), out)
        asked = self.asked()
        self.assertEqual(len(asked), 1, asked)
        self.assertRegex(asked[0], r'^code-lens \d+ \d+ 1 \d+$')
        out = self.run_p(self.start() + [f'print-hit {x1 + 4} {y1}', f'print-hit {x1 + 4} {y1 + 21}'])
        self.assertIn('inlay lens 1:1', ' '.join(out).replace('lens 1 1', 'lens 1:1'))
        path = self.work / 'lens.ppm'
        self.run_p(self.start() + [f'shot {path}'])
        self.assertTrue(path.exists())

    def test_caret_steps_over_lens_rows(self):
        out = self.run_p(self.start() + ['key ctrl+Home', 'key Down', 'key Down', 'print-state', 'key Up',
                                         'key Up', 'print-state', 'key Up', 'print-state', 'key Down',
                                         'key Down', 'key Down', 'print-state'])
        s = self.state(out)
        self.assertIn('line=3 ', s[0])
        self.assertIn('line=1 ', s[1])
        self.assertIn('line=1 ', s[2])
        self.assertIn('line=4 ', s[3])

    def test_click_runs_the_command_and_rest_shows_the_tip(self):
        out = self.run_p(self.start() + ['print-xy 1 1'])
        x, y = self.xy(out)[0]
        self.steps({}, hello='hello 1 code-lens command-args')
        self.run_p(self.start() + [f'click {x + 6} {y - 21}', 'wait 200', 'print-state'])
        runs = self.events('run present.a')
        self.assertTrue(any(r.endswith(' ref 0') for r in runs), runs)     # the lens's command
        out = self.run_p(self.start() + [f'move {x + 70} {y - 21}', 'wait 650', 'print-tip'])
        self.assertIn('used here', '\n'.join(out))

    def test_lenses_move_with_edits(self):
        out = self.run_p(self.start() + ['key ctrl+Home', 'key Return', 'print-present lenses'])
        self.assertEqual(self.lenses(out)[:2], ['lens 2 Run +command', 'lens 2 2 references'])

    def test_the_view_stays_when_lenses_come_above_its_top(self):
        (self.proj / 'big.rs').write_text(''.join(f'let v{i} = {i};\n' for i in range(300)), encoding='utf-8')
        # the second answer (after the scroll) puts a lens on the line then at the top
        self.answer(body(lens(1, 'top')), body(lens(1, 'top'), lens(101, 'here')))
        out = self.run_p(self.start() + ['cmd goto_line', 'type 120', 'key Return', 'cmd center_line',
                                         'print-viewport'], files=('big.rs',))
        top = int([l for l in out if l.startswith('view ')][-1].split('top=')[1].split()[0])
        self.answer(body(lens(1, 'top')), body(lens(1, 'top'), lens(top, 'here')))
        out = self.run_p(self.start() + ['cmd goto_line', 'type 120', 'key Return', 'cmd center_line',
                                         'print-xy 120 1', 'wait 400', 'print-present lenses',
                                         'print-xy 120 1'], files=('big.rs',))
        self.assertIn(f'lens {top} here', self.lenses(out))
        a, b = self.xy(out)
        self.assertEqual(a, b)

    def test_broken_answers_are_dropped(self):
        for b in (body(lens(0, 'x')), body(lens(1, 'a\nb')), body(lens(1, 'x' * 201)), '2\n' + lens(1, 'x')):
            self.answer(b)
            out = self.run_p(self.start() + ['print-present lenses'])
            self.assertEqual(self.lenses(out), [], b)

    def test_setting_off_and_provider_stopping(self):
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[editor]\ncode_lens = false\n')
        out = self.run_p(self.start() + ['print-viewport'])
        self.assertTrue(any(l.startswith('view mode=lines') for l in out), out)
        self.assertEqual(self.asked(), [])
        config.write_text(config.read_text().replace('code_lens = false', 'code_lens = true'))
        out = self.run_p(self.start() + ['print-present lenses', 'ext-set present stop', 'wait 300',
                                         'print-present lenses', 'print-viewport'])
        self.assertEqual(len(self.lenses(out)), 3)
        self.assertTrue(any(l.startswith('view mode=lines') for l in out), out)


if __name__ == '__main__':
    unittest.main()
