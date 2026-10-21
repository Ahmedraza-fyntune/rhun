#!/usr/bin/env python3
"""Document highlights (editor presentation, feature document-highlights): the language's
provider asked when the caret rests in a word, its read and write ranges drawn behind the text,
gone when the caret leaves them or the text changes; without a provider the word's occurrences
(highlight_occurrences). Driven headlessly with the fake extension tests/ext/present.py."""
import json
import unittest

pres = __import__('presentation')


class Highlights(pres.Base):
    def setUp(self):
        super().setUp()
        ini = self.exts / 'rhun-tests/present/extension.ini'
        ini.write_text(ini.read_text() + '[provides]\nhighlights = *.rs\n', encoding='utf-8')
        self.steps({}, hello='hello 1 document-highlights')
        path = self.exts / 'rhun-tests/present/answers.json'
        path.write_text(json.dumps({'highlights': ['ok {ID} {LEN}', '2\n2 9 2 10 write\n3 13 3 14 read\n']}),
                        encoding='utf-8')
        self.env['PRESENT_ANSWERS'] = path.as_posix()

    def hl(self, out):
        return [l for l in out if l.startswith('highlight ')]

    def at(self, line, col):
        x, y = map(int, self.run_p([f'print-xy {line} {col}'])[0].split())
        return f'click {x + 2} {y}'

    def asked(self):
        if not self.plog.exists():
            return []
        return [l.split(' ', 1)[1] for l in self.plog.read_text(errors='replace').splitlines()
                if ' highlights ' in l and l.split(' ')[0] != '0']

    def test_occurrences_without_a_provider(self):
        click = self.at(2, 9)                   # "x" in "let x = 1;"
        out = self.run_p([click, 'wait 400', 'print-present highlights', self.at(2, 6), 'print-present highlights',
                          'wait 400', 'print-present highlights', 'key End', 'print-present highlights'])
        h = self.hl(out)
        self.assertEqual(h[:2], ['highlight 2:9-2:10 text', 'highlight 3:13-3:14 text'])
        # "let": the old ranges go at once, the new ones after the pause; ";"'s end has no word
        self.assertEqual(h[2:4], ['highlight 2:5-2:8 text', 'highlight 3:5-3:8 text'])
        self.assertEqual(h[4:], [])

    def test_the_provider_answers_and_edits_clear(self):
        out = self.run_p(self.start() + [self.at(2, 9), 'wait 400', 'print-present highlights', 'type z',
                                         'print-present highlights'])
        h = self.hl(out)
        self.assertEqual(h, ['highlight 2:9-2:10 write', 'highlight 3:13-3:14 text'])
        asked = self.asked()
        self.assertTrue(asked and asked[0].endswith(' 2 9'), asked)
        path = self.work / 'hl.ppm'
        self.run_p(self.start() + [self.at(2, 9), 'wait 400', f'shot {path}'])
        self.assertTrue(path.exists())

    def test_setting_off(self):
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[editor]\nhighlight_occurrences = false\n')
        out = self.run_p([self.at(2, 9), 'wait 400', 'print-present highlights'])
        self.assertEqual(self.hl(out), [])


if __name__ == '__main__':
    unittest.main()
