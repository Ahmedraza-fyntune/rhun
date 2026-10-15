#!/usr/bin/env python3
"""A new file from the tab strip (issue 86): the + right after the last tab, and a double click on the
strip's empty end, open an untitled tab at the end of the strip. With more tabs than fit, the + stays
in a square at the strip's right end and the tabs scroll beside it."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()

CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n'
          '[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
# at 1000x600, scale 1: the strip is y 40 to 76; one.txt, two.txt and three.txt end at x 307, and the +
# is the 24 px button 6 px after that
Y = 58
PLUS = 325
EMPTY = 700
ONE = 40                         # one.txt, left of its close button


class NewTab(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-newtab-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        for name in ('one', 'two', 'three'):
            (self.proj / (name + '.txt')).write_text(name + '\n', encoding='utf-8')
        for i in range(1, 10):
            (self.proj / f'file-number-{i}.txt').write_text(f'{i}\n', encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix())

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions, size='1000x600', files=('one', 'two', 'three')):
        opens = ['open ' + (self.proj / (name + '.txt')).as_posix() for name in files]
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 200', *opens, *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', size, '--scale', '1',
                                 '--script', script.as_posix()],
                                env=self.env, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8').splitlines()

    def test_plus_opens_an_untitled_tab_at_the_end(self):
        # the first tab is active: the new one still goes after the last, where the + is
        out = self.run_editor([f'click {ONE} {Y}', 'print-tabs', f'click {PLUS} {Y}', 'print-tabs',
                               'print-state', 'type hello', 'print-doc'])
        self.assertEqual(out[0], 'tabs=*one.txt | two.txt | three.txt')
        self.assertEqual(out[1], 'tabs=one.txt | two.txt | three.txt | *untitled')
        self.assertIn('tabs=4 active=untitled ', out[2])
        self.assertIn(' focus=0 ', out[2])
        self.assertEqual(out[3], 'hello')

    def test_plus_has_a_tooltip(self):
        out = self.run_editor([f'move {PLUS} {Y}', 'wait 650', 'print-tip'])
        self.assertEqual(out, ['tip=New file'])

    def test_double_click_on_the_empty_strip(self):
        out = self.run_editor([f'click {ONE} {Y}',
                               # one click there does nothing
                               f'click {EMPTY} {Y}', 'print-tabs', 'wait 600',
                               f'click {EMPTY} {Y}', f'click {EMPTY} {Y}', 'print-tabs'])
        self.assertEqual(out, ['tabs=*one.txt | two.txt | three.txt',
                               'tabs=one.txt | two.txt | three.txt | *untitled'])

    def test_double_click_on_a_tab_opens_nothing(self):
        out = self.run_editor([f'click {ONE} {Y}', f'click {ONE} {Y}', 'print-tabs'])
        self.assertEqual(out, ['tabs=*one.txt | two.txt | three.txt'])

    def test_quick_clicks_closing_the_last_tab_open_nothing(self):
        # three.txt's close button is at 279 to 299; once it closes, the strip ends before there, so
        # the second press of the quick pair lands on the empty end
        out = self.run_editor(['click 289 58', 'click 289 58', 'print-tabs'])
        self.assertEqual(out, ['tabs=one.txt | *two.txt'])

    def test_plus_stays_at_the_end_of_a_full_strip(self):
        # 600 px: the + is the button in the square from 564 to 600, the tabs scroll left of it
        files = [f'file-number-{i}' for i in range(1, 10)]
        names = ' | '.join(name + '.txt' for name in files)
        out = self.run_editor([
            # the active last tab ends where the square starts: its close button is at 536 to 556
            'click 546 58', 'print-tabs',
            # scrolled back to the first tab, the + is still at the end
            'move 300 58', 'scroll -3000', 'move 582 58', 'wait 650', 'print-tip',
            'click 582 58', 'print-tabs', 'print-state'], size='600x500', files=files)
        self.assertEqual(out[0], 'tabs=' + names.replace(' | file-number-9.txt', '').replace(
            'file-number-8.txt', '*file-number-8.txt'))
        self.assertEqual(out[1], 'tip=New file')
        self.assertEqual(out[2], 'tabs=' + names.replace(' | file-number-9.txt', '') + ' | *untitled')
        self.assertIn('tabs=9 active=untitled ', out[3])


if __name__ == '__main__':
    unittest.main()
