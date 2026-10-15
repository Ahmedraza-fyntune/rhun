#!/usr/bin/env python3
"""Pinned tabs (issue 94): Pin Tab keeps a tab at the left with a pin for its close button. Keys, a
middle click and Close All Tabs leave it open, the tab's menu closes it, a drag across the pinned tabs
pins or unpins, and the session and Reopen Closed Tab bring the pin back."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()

CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n'
          '[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = {restore}\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
# at 1000x600, scale 1: the strip is y 40 to 76, and one.txt, two.txt and three.txt are x 0 to 97, 97
# to 195 and 195 to 307 (pinned or not, a tab keeps its width); the button of the first is at 69 to 89
Y = 58
ONE, TWO, THREE = 40, 140, 240
FIRST_BUTTON = 79
# a menu opened at y 58 has its items at 64, a line, then 104 and 136 (32 px each)
MENU_ITEMS = (80, 120, 152)


class TabPin(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-tabpin-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        for name in ('one', 'two', 'three'):
            (self.proj / (name + '.txt')).write_text(name + '\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix())
        self.write_config(False)

    def tearDown(self):
        self.tmp.cleanup()

    def write_config(self, restore):
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text(CONFIG.format(restore='true' if restore else 'false'), encoding='utf-8')

    def run_editor(self, actions, files=('one', 'two', 'three')):
        opens = ['open ' + (self.proj / (name + '.txt')).as_posix() for name in files]
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 200', *opens, *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', '1000x600', '--scale', '1',
                                 '--script', script.as_posix()],
                                env=self.env, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8').splitlines()

    def test_pinned_tabs_go_first(self):
        # the palette pins the active tab, the menu the one clicked; each goes after the pinned ones
        out = self.run_editor([f'click {THREE} {Y}', 'cmd pin_tab', 'print-tabs',
                               f'click {TWO} {Y} right', 'print-menu', f'click 180 {MENU_ITEMS[0]}',
                               'print-tabs'])
        self.assertEqual(out, ['tabs=^*three.txt | one.txt | two.txt',
                               'Pin Tab', '-', 'Close Tab', 'Close All Tabs',
                               'tabs=^*three.txt | ^one.txt | two.txt'])

    def test_unpinned_tabs_go_after_the_pinned(self):
        out = self.run_editor([f'click {ONE} {Y}', 'cmd pin_tab', f'click {TWO} {Y}', 'cmd pin_tab',
                               'print-tabs',
                               # the pin unpins one.txt (and the press shows it, as a close button's
                               # does): it goes before the tabs not pinned
                               f'click {FIRST_BUTTON} {Y}', 'print-tabs',
                               # and Unpin Tab in the palette, for two.txt, now first
                               f'click {ONE} {Y}', 'cmd unpin_tab', 'print-tabs'])
        self.assertEqual(out, ['tabs=^one.txt | ^*two.txt | three.txt',
                               'tabs=^two.txt | *one.txt | three.txt',
                               'tabs=*two.txt | one.txt | three.txt'])

    def test_keys_and_middle_click_leave_a_pinned_tab_open(self):
        out = self.run_editor([f'click {ONE} {Y}', 'cmd pin_tab', 'key ctrl+w', 'print-tabs', 'print-toast',
                               'cmd close_tab', f'click {ONE} {Y} middle', 'print-tabs',
                               # an unpinned tab still closes
                               f'click {THREE} {Y} middle', f'click {TWO} {Y}', 'key ctrl+w', 'print-tabs'])
        self.assertEqual(out, ['tabs=^*one.txt | two.txt | three.txt',
                               'toast=The tab is pinned: unpin it to close it',
                               'tabs=^*one.txt | two.txt | three.txt',
                               'tabs=^*one.txt'])

    def test_vim_quit_leaves_a_pinned_tab_open(self):
        # :q, then :q! and ZQ with an unsaved change, which stays; :wq saves but leaves it open
        out = self.run_editor(['cmd toggle_vim', f'click {ONE} {Y}', 'cmd pin_tab', 'key Escape',
                               'type :q', 'key Return', 'print-tabs', 'print-toast',
                               'type x', 'type :q!', 'key Return', 'type ZQ', 'print-tabs', 'print-state',
                               'type :wq', 'key Return', 'print-tabs', 'print-state'])
        self.assertEqual(out[:3], ['tabs=^*one.txt | two.txt | three.txt',
                                   'toast=The tab is pinned: unpin it to close it',
                                   'tabs=^*one.txt | two.txt | three.txt'])
        self.assertIn(' dirty=1 ', out[3])
        self.assertEqual(out[4], 'tabs=^*one.txt | two.txt | three.txt')
        self.assertIn(' dirty=0 ', out[5])
        self.assertEqual((self.proj / 'one.txt').read_text(encoding='utf-8'), 'ne\n')

    def test_the_menu_closes_a_pinned_tab(self):
        # two.txt, pinned, is first: its menu closes it, and the next tab shows
        out = self.run_editor([f'click {TWO} {Y}', 'cmd pin_tab', f'click {ONE} {Y} right', 'print-menu',
                               f'click 70 {MENU_ITEMS[1]}', 'print-tabs'])
        self.assertEqual(out, ['Unpin Tab', '-', 'Close Tab', 'Close All Tabs',
                               'tabs=*one.txt | three.txt'])

    def test_close_all_tabs_keeps_the_pinned(self):
        # a modified pinned file is not asked about
        out = self.run_editor([f'click {TWO} {Y}', 'cmd pin_tab', 'type x', 'key ctrl+shift+w', 'print-tabs',
                               'print-state'])
        self.assertEqual(out[0], 'tabs=^*two.txt')
        self.assertIn(' dirty=1 ', out[1])
        self.assertIn(' focus=0 ', out[1])

    def test_close_all_from_the_menu(self):
        out = self.run_editor([f'click {ONE} {Y}', 'cmd pin_tab', f'click {THREE} {Y} right',
                               f'click 300 {MENU_ITEMS[2]}', 'print-tabs'])
        self.assertEqual(out, ['tabs=^*one.txt'])

    def test_new_files_open_after_the_pinned(self):
        out = self.run_editor([f'click {ONE} {Y}', 'cmd pin_tab', f'click {TWO} {Y}', 'cmd pin_tab',
                               f'click {ONE} {Y}', 'key ctrl+n', 'print-tabs'])
        self.assertEqual(out, ['tabs=^one.txt | ^two.txt | *untitled | three.txt'])

    def test_a_file_does_not_replace_a_pinned_untitled_tab(self):
        one = (self.proj / 'one.txt').as_posix()
        out = self.run_editor(['key ctrl+n', 'cmd pin_tab', f'open {one}', 'print-tabs'], files=())
        self.assertEqual(out, ['tabs=^untitled | *one.txt'])
        # unpinned and untouched, it gives its place to the file as before
        out = self.run_editor(['key ctrl+n', f'open {one}', 'print-tabs'], files=())
        self.assertEqual(out, ['tabs=*one.txt'])

    def test_a_drag_pins_and_unpins(self):
        out = self.run_editor([f'click {ONE} {Y}', 'cmd pin_tab',
                               # three.txt, held at 45 of its 112 px, to the left end: among the pinned
                               f'move {THREE} {Y}', 'down', 'move 10 58', 'up', 'print-tabs',
                               # three.txt is at 0 to 112: to the right end, among the others
                               'move 50 58', 'down', 'move 590 58', 'up', 'print-tabs',
                               # one.txt between the two groups stays pinned
                               'move 40 58', 'down', 'move 60 58', 'up', 'print-tabs'])
        self.assertEqual(out, ['tabs=^*three.txt | ^one.txt | two.txt',
                               'tabs=^one.txt | two.txt | *three.txt',
                               'tabs=^*one.txt | two.txt | three.txt'])

    def test_reopen_closed_tab_pins_it_again(self):
        out = self.run_editor([f'click {TWO} {Y}', 'cmd pin_tab', f'click {ONE} {Y} right',
                               f'click 70 {MENU_ITEMS[1]}', 'print-tabs', 'key ctrl+shift+t', 'print-tabs'])
        self.assertEqual(out, ['tabs=*one.txt | three.txt', 'tabs=^*two.txt | one.txt | three.txt'])

    def test_the_session_remembers_the_pins(self):
        self.write_config(True)
        self.run_editor([f'click {TWO} {Y}', 'cmd pin_tab', f'click {THREE} {Y}'])
        self.write_config(True)
        out = self.run_editor(['print-tabs'], files=())
        self.assertEqual(out, ['tabs=^two.txt | one.txt | *three.txt'])
        session = next(self.work.rglob('*.session'))
        lines = session.read_text(encoding='utf-8').splitlines()
        self.assertEqual([line.endswith(end) for line, end in zip(lines, ('two.txt\t0\tpin', 'one.txt\t0',
                                                                         'three.txt\t0'))], [True] * 3)
        # a pinned file listed after others still goes first, and the active one stays active
        one, two, three = (lines[1].split('\t')[0], lines[0].split('\t')[0], lines[2].split('\t')[0][1:])
        session.write_text(f'{one}\t2\n*{two}\t1\n{three}\t0\tpin\n', encoding='utf-8')
        self.write_config(True)
        out = self.run_editor(['print-tabs', 'print-state'], files=())
        self.assertEqual(out[0], 'tabs=^three.txt | one.txt | *two.txt')
        self.assertIn(' col=2 ', out[1])


if __name__ == '__main__':
    unittest.main()
