#!/usr/bin/env python3
"""Semantic tokens (editor presentation stage 7, feature semantic-tokens): legends and their
effects, full and delta answers, classes drawn over the syntax classes with strike, underline and
faded, tokens moving with edits, broken deltas asked again with -, the setting, and a provider
that stops. Driven headlessly with the fake extension tests/ext/present.py."""
import json
import unittest

pres = __import__('presentation')

LEGEND = ('function variable macro keyword=strike struct comment=faded\n'
          'declaration mutable=underline deprecated defaultLibrary')
# main (function, declaration); x (variable, mutable); y; x (deprecated); println (macro, library)
INTS = '0 3 4 0 1 1 8 1 1 2 1 8 1 1 0 0 4 1 1 4 1 4 7 2 8'
FULL = 'r1 L1 full 5\n' + INTS
C_FUNCTION, C_VARIABLE, C_PREPROC = 3, 11, 10


class Semantic(pres.Base):
    def setUp(self):
        super().setUp()
        ini = self.exts / 'rhun-tests/present/extension.ini'
        ini.write_text(ini.read_text() + '[provides]\nsemantic_tokens = *.rs\n', encoding='utf-8')
        self.steps({'ready': [['semantic-legend L1 {LEN}', LEGEND]]}, hello='hello 1 semantic-tokens')
        self.answer(FULL)

    def answer(self, *bodies):
        path = self.exts / 'rhun-tests/present/answers.json'
        path.write_text(json.dumps({'semantic-tokens': [['ok {ID} {LEN}', b] for b in bodies]}),
                        encoding='utf-8')
        self.env['PRESENT_ANSWERS'] = path.as_posix()

    def asked(self):
        if not self.plog.exists():
            return []
        return [l.split(' ', 1)[1] for l in self.plog.read_text(errors='replace').splitlines()
                if ' semantic-tokens ' in l and l.split(' ')[0] != '0']

    def classes(self, out, line):
        row = next(l for l in out if l.startswith(f'classes {line} ') or l == f'classes {line}')
        return row.split()[2:]

    def test_full_answer_draws_classes_and_effects(self):
        out = self.run_p(self.start() + ['print-present tokens', 'print-classes 1', 'print-classes 2',
                                         'print-classes 3', 'print-classes 4'])
        self.assertIn('tokens present legend=L1 result=r1 ints=25 toks=5', out)
        self.assertIn(f'4-7={C_FUNCTION}', self.classes(out, 1))
        self.assertIn(f'9-9={C_VARIABLE}', self.classes(out, 2))
        self.assertIn(f'5-11={C_PREPROC}', self.classes(out, 4))   # defaultLibrary: only f, t, v
        fx = [l for l in out if l.startswith('fx ')]
        self.assertEqual(fx, ['fx 9-9=2', 'fx 13-13=1'])           # underline (mutable), strike
        asked = self.asked()
        self.assertEqual(len(asked), 1, asked)
        self.assertRegex(asked[0], r'^semantic-tokens \d+ \d+ -$')
        self.assertIn('ok 1', self.replies())                       # the legend
        path = self.work / 'tokens.ppm'
        self.run_p(self.start() + [f'shot {path}'])
        self.assertTrue(path.exists())

    def test_tokens_move_with_edits_then_a_delta_replaces_them(self):
        # the second answer moves main two bytes right (int 1) and makes it a variable (int 3)
        self.answer(FULL, 'r2 L1 delta 2\n1 1 1\n5\n3 1 1\n1')
        out = self.run_p(self.start() + ['key ctrl+Home', 'type xy', 'print-classes 1', 'wait 600',
                                         'print-classes 1', 'print-present tokens'])
        rows = [l for l in out if l.startswith('classes 1')]
        self.assertIn(f'6-9={C_FUNCTION}', rows[0].split())          # moved two bytes right
        self.assertIn('tokens present legend=L1 result=r2 ints=25 toks=5', out)
        asked = self.asked()
        self.assertEqual(len(asked), 2, asked)
        self.assertTrue(asked[1].endswith(' r1'), asked)            # PREV: the last result
        self.assertIn(f'6-9={C_VARIABLE}', rows[1].split())

    def test_broken_delta_drops_tokens_and_asks_again_with_dash(self):
        self.answer('r9 L1 delta 1\n0 1 0\n', FULL)
        out = self.run_p(self.start() + ['wait 300', 'print-present tokens'])
        asked = self.asked()
        self.assertGreaterEqual(len(asked), 2, asked)
        self.assertTrue(all(a.endswith(' -') for a in asked), asked)
        self.assertIn('tokens present legend=L1 result=r1 ints=25 toks=5', out)

    def test_bad_answers_are_dropped(self):
        for body in ('r1 L1 full 2\n0 3 4 0 1', 'r1 NOPE full 1\n0 3 4 0 1', 'r1 L1 sparse 1\n0 3 4 0 1',
                     'r1 L1 full 1\n0 3 4 0 1 9'):
            self.answer(body)
            out = self.run_p(self.start() + ['print-present tokens'])
            self.assertIn('tokens none', out, body)

    def test_legend_errors(self):
        self.steps({'ready': [['semantic-legend L1 {LEN}', 'function=sparkle'],
                              ['semantic-legend bad/name {LEN}', 'function'],
                              ['semantic-legend L2 {LEN}', ' '.join(f't{i}' for i in range(257))]]
                    + [[f'semantic-legend M{i} 1', 'x'] for i in range(9)]},
                   hello='hello 1 semantic-tokens')
        self.run_p(self.start())
        r = self.replies()
        self.assertIn('error 1 syntax', ' '.join(r))
        self.assertTrue(any(x.startswith('error 2 syntax') for x in r), r)
        self.assertTrue(any(x.startswith('error 3 toobig') for x in r), r)
        oks = [x for x in r if x.startswith('ok ')]
        self.assertEqual(len(oks), 8, r)                             # eight legends, the ninth too many
        self.assertTrue(any(x.startswith('error 12 toobig') for x in r), r)

    def test_setting_off_asks_nothing_and_draws_syntax(self):
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[editor]\nsemantic_highlighting = false\n')
        out = self.run_p(self.start() + ['print-classes 2'])
        self.assertEqual(self.asked(), [])
        self.assertNotIn(f'9-9={C_VARIABLE}', self.classes(out, 2))     # (main is a function to both)

    def test_provider_stopping_clears_tokens(self):
        out = self.run_p(self.start() + ['print-present tokens', 'ext-set present stop', 'wait 300',
                                         'print-present tokens', 'print-classes 2'])
        self.assertIn('tokens present legend=L1 result=r1 ints=25 toks=5', out)
        self.assertIn('tokens none', out)
        self.assertNotIn(f'9-9={C_VARIABLE}', self.classes(out, 2))


if __name__ == '__main__':
    unittest.main()
