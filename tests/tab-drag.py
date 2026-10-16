#!/usr/bin/env python3
"""Tabs move by dragging (issue 94): a tab held by the left button follows the pointer once it has moved
a few pixels, takes the place nearest to where it is held, and scrolls a full strip at its ends."""
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
# at 1000x600, scale 1: the strip is y 40 to 76, and one.txt, two.txt and three.txt are x 0 to 97, 97
# to 195 and 195 to 307
Y = 58
ONE, TWO, THREE = 40, 140, 240


class TabDrag(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-tabdrag-')
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
                                env=self.env, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8').splitlines()

    def test_a_dragged_tab_moves_both_ways(self):
        out = self.run_editor([f'move {ONE} {Y}', 'down',
                               # past half of two.txt it takes two.txt's place, past three.txt the last
                               'move 100 58', 'print-tabs', 'move 300 58', 'print-tabs', 'up', 'print-tabs',
                               # one.txt is at 210 to 307 now: back to the start
                               'move 250 58', 'down', 'move 10 58', 'up', 'print-tabs'])
        self.assertEqual(out, ['tabs=two.txt | *one.txt | three.txt',
                               'tabs=two.txt | three.txt | *one.txt',
                               'tabs=two.txt | three.txt | *one.txt',
                               'tabs=*one.txt | two.txt | three.txt'])

    def test_a_small_move_is_a_click(self):
        out = self.run_editor([f'move {ONE} {Y}', 'down', f'move {ONE + 3} {Y}', 'up', 'print-tabs'])
        self.assertEqual(out, ['tabs=*one.txt | two.txt | three.txt'])

    def test_the_place_follows_the_pointer_only(self):
        # held still, frame after frame, the tab stays where it went; short of half the neighbor it
        # goes back
        out = self.run_editor([f'move {ONE} {Y}', 'down', 'move 100 58', 'print-tabs', 'move 100 58',
                               'move 100 58', 'print-tabs', 'move 95 58', 'print-tabs',
                               'move 80 58', 'print-tabs', 'up'])
        self.assertEqual(out, ['tabs=two.txt | *one.txt | three.txt'] * 3
                         + ['tabs=*one.txt | two.txt | three.txt'])

    def test_a_close_button_press_drags_nothing(self):
        # one.txt's close button is at 69 to 89: a press there that moves off closes nothing and
        # moves nothing
        out = self.run_editor([f'click {ONE} {Y}', 'move 79 58', 'down', 'move 300 58', 'up', 'print-tabs'])
        self.assertEqual(out, ['tabs=*one.txt | two.txt | three.txt'])

    def test_another_tab_taking_the_place_ends_the_drag(self):
        # Ctrl+W closes the dragged two.txt: three.txt, now at its index, does not follow the pointer
        out = self.run_editor([f'move {TWO} {Y}', 'down', 'move 160 58', 'key ctrl+w', 'move 10 58',
                               'up', 'print-tabs'])
        self.assertEqual(out, ['tabs=one.txt | *three.txt'])
        # Ctrl+Tab shows another tab: the drag ends there
        out = self.run_editor([f'move {ONE} {Y}', 'down', 'move 100 58', 'key ctrl+Tab', 'move 300 58',
                               'up', 'print-tabs'])
        self.assertEqual(out, ['tabs=two.txt | one.txt | *three.txt'])

    def test_the_strip_scrolls_while_a_tab_is_held_past_its_ends(self):
        # 600 px: the tabs scroll in 0 to 564. Every command draws a frame, and every frame scrolls the
        # strip a little; the release leaves the tab where the strip took it.
        files = [f'file-number-{i}' for i in range(1, 10)]
        names = [name + '.txt' for name in files]
        out = self.run_editor(['move 300 58', 'scroll -3000', 'move 40 58', 'down', 'move 120 58',
                               *['move 590 58'] * 150, 'up', 'print-tabs',
                               # and back, with the pointer on the window's edge
                               'move 450 58', 'down', 'move 400 58', *['move 1 58'] * 150, 'up', 'print-tabs'],
                              size='600x500', files=files)
        self.assertEqual(out, ['tabs=' + ' | '.join(names[1:] + ['*' + names[0]]),
                               'tabs=' + ' | '.join(['*' + names[0]] + names[1:])])


if __name__ == '__main__':
    unittest.main()
