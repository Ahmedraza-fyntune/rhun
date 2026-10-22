#!/usr/bin/env python3
"""Document colors (editor presentation, feature document-colors): swatches before the colors a
provider finds, a click asking for a new color and the provider's color-edit making it, colors
moving with edits, broken answers, the setting, and a provider that stops. Driven headlessly with
the fake extension tests/ext/present.py."""
import json
import unittest

pres = __import__('presentation')

TEXT = 'let a = 0xff0000;\nlet b = 0x00ff00;\n'
COLORS = '2\n1 9 1 17 ff0000ff\n2 9 2 17 00ff0080\n'


class Colors(pres.Base):
    def setUp(self):
        super().setUp()
        (self.proj / 'c.rs').write_text(TEXT, encoding='utf-8')
        ini = self.exts / 'rhun-tests/present/extension.ini'
        ini.write_text(ini.read_text().replace('[needs]\ndocuments = read\n', '[needs]\ndocuments = write\n') +
                       '[provides]\ncolors = *.rs\n', encoding='utf-8')
        self.steps({}, hello='hello 1 document-colors')
        self.answer(COLORS)

    def answer(self, body, edit=None):
        answers = {'colors': ['ok {ID} {LEN}', body]}
        if edit is not None:
            answers['color-edit'] = ['ok {ID} {LEN}', edit]
        path = self.exts / 'rhun-tests/present/answers.json'
        path.write_text(json.dumps(answers), encoding='utf-8')
        self.env['PRESENT_ANSWERS'] = path.as_posix()

    def run_c(self, actions):
        return self.run_p(actions, files=('c.rs',))

    def colors(self, out):
        return [l for l in out if l.startswith('color ')]

    def xy(self, out):
        return [tuple(map(int, l.split())) for l in out if len(l.split()) == 2 and l.split()[0].isdigit()]

    def asked(self, verb):
        if not self.plog.exists():
            return []
        return [l.split(' ', 1)[1] for l in self.plog.read_text(errors='replace').splitlines()
                if f' {verb} ' in l and l.split(' ')[0] != '0']

    def test_swatches_drawn_before_colors(self):
        out = self.run_c(['print-xy 1 9'] + self.start() + ['print-present colors', 'print-xy 1 9', 'print-xy 1 10'])
        self.assertEqual(self.colors(out), ['color 1:9-1:17 ff0000ff', 'color 2:9-2:17 00ff0080'])
        (x0, y), (x9, _), (x10, _) = self.xy(out)
        self.assertEqual(x9 - x0, 2 * 7)        # the caret goes after the swatch before the color
        self.assertEqual(x10 - x9, 7)
        self.assertRegex(self.asked('colors')[0], r'^colors \d+ \d+ 1 \d+$')
        path = self.work / 'colors.ppm'
        self.run_c(self.start() + [f'shot {path}'])
        self.assertEqual(pres.host.ppm_pixel(path, x0 + 7, y), (255, 0, 0))

    def test_a_click_changes_the_color_through_the_provider(self):
        edit = '1\n2 {VER} 1\n#{DOC}1 9 1 17 8\n0x0000ff'
        self.answer(COLORS, edit)
        out = self.run_c(['print-xy 1 9'])
        x0, y = self.xy(out)[0]
        out = self.run_c(self.start() + [f'click {x0 + 5} {y}', 'wait 100', 'key ctrl+a', 'type #0000ff', 'key Return',
                                         'wait 300', 'print-doc'])
        self.assertIn('color-edit', ' '.join(self.asked('color-edit')))
        self.assertTrue(self.asked('color-edit')[0].endswith(' 1 9 1 17 0000ffff'), self.asked('color-edit'))
        self.assertIn('let a = 0x0000ff;', out)

    def test_broken_answers_setting_and_stop(self):
        for b in ('1\n1 9 1 17 ff00\n', '1\n0 9 1 17 ff0000ff\n', '2\n1 9 1 17 ff0000ff\n'):
            self.answer(b)
            out = self.run_c(self.start() + ['print-present colors'])
            self.assertEqual(self.colors(out), [], b)
        self.answer(COLORS)
        out = self.run_c(self.start() + ['print-present colors', 'ext-set present stop', 'wait 300',
                                         'print-present colors'])
        self.assertEqual(len(self.colors(out)), 2)
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[editor]\ncolor_swatches = false\n')
        out = self.run_c(self.start() + ['print-present colors'])
        self.assertEqual(self.colors(out), [])


if __name__ == '__main__':
    unittest.main()
