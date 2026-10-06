#!/usr/bin/env python3
"""The sidebar splitter keeps its drag: a press inside its zone resizes the panel
and must not turn into a text selection in the editor."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()


class SidebarSplit(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-splitter-')
        self.work = Path(self.tmp.name).resolve()
        # project is a clean subdir: config/state churn in work would redraw the explorer
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        self.file = self.proj / 'words.txt'
        self.file.write_text('\n'.join('word%d some text to select and drag over' % i
                                     for i in range(200)), encoding='utf-8')
        self.config = self.work / 'config/rhun/config'
        self.config.parent.mkdir(parents=True)
        self.config.write_text('[ui]\nsidebar = true\nsidebar_width = 240\nagents_panel = false\n'
                               '[editor]\ncursor_blink = false\n'
                               '[files]\nrestore_session = false\nrestore_project = false\n'
                               '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix())

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions):
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), self.file.as_posix(),
                                 '--headless', '1000x700', '--scale', '1',
                                 '--script', script.as_posix()],
                                env=self.env, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8')

    def sidebar_width(self):
        return int(next(l.split('=')[1] for l in self.config.read_text().splitlines()
                        if l.strip().startswith('sidebar_width')))

    def test_drag_from_editor_side_resizes_without_selecting(self):
        # the handle's last ~3 px overlap the editor: the press must stay the splitter's
        out = self.run_editor(['wait 200', 'move 242 400', 'down', 'wait 60',
                               'move 330 400', 'wait 60', 'print-state', 'up', 'wait 50'])
        self.assertIn('sel=0', out)
        self.assertEqual(self.sidebar_width(), 330)

    def test_drag_from_panel_side_resizes(self):
        out = self.run_editor(['wait 200', 'move 238 400', 'down', 'wait 60',
                               'move 330 400', 'wait 60', 'print-state', 'up', 'wait 50'])
        self.assertIn('sel=0', out)
        self.assertEqual(self.sidebar_width(), 330)

    def test_editor_drag_still_selects(self):
        out = self.run_editor(['wait 200', 'move 400 400', 'down', 'wait 60',
                               'move 600 400', 'wait 60', 'print-state', 'up', 'wait 50'])
        self.assertNotIn('sel=0', out)

    def test_scrollbar_thumb_widens_on_hover(self):
        # the right 6 px of the track belong to the window-resize edge in CSD mode;
        # hover the left half of the 12 px track (988..994 of a 1000 px window)
        shots = [self.work / 'a.ppm', self.work / 'b.ppm']
        self.run_editor(['wait 200', 'move 500 400', 'shot ' + str(shots[0]),
                         'move 990 300', 'wait 60', 'shot ' + str(shots[1])])
        a, b = (ppm_pixels(p) for p in shots)
        w = 1000
        diffs = {(x, y) for y in range(len(a) // w // 3)
                 for x in range(w) if a[(y * w + x) * 3:(y * w + x) * 3 + 3]
                 != b[(y * w + x) * 3:(y * w + x) * 3 + 3]}
        self.assertTrue(diffs, 'thumb did not change on hover')
        self.assertTrue(all(x >= 985 for x, _ in diffs),
                        'hover changed pixels outside the scrollbar track')

    def shapes(self, actions):
        lines = self.run_editor(actions).splitlines()
        return {lines[i][:-1]: int(lines[i + 1])
                for i in range(len(lines) - 1) if lines[i].endswith('=')}

    def test_cursor_shapes_over_editor_chrome(self):
        # CUR_DEFAULT=0 CUR_TEXT=1 CUR_EW=3 CUR_ARROW=7
        shapes = self.shapes([
            'wait 200',
            'move 500 400', 'wait 60', 'echo text=', 'print-shape',
            'move 990 300', 'wait 60', 'echo track=', 'print-shape',
            'down', 'wait 60', 'move 500 400', 'wait 60', 'echo sbdrag=', 'print-shape', 'up', 'wait 60'])
        self.assertEqual(shapes['text'], 1, 'I-beam over editor text')
        self.assertEqual(shapes['track'], 7, 'arrow over the scrollbar')
        self.assertEqual(shapes['sbdrag'], 7, 'arrow keeps during the scrollbar drag')

    def test_splitter_drag_keeps_ew_cursor_over_scrollbar(self):
        # dragging the splitter across the scrollbar track must not lose the resize cursor
        shapes = self.shapes([
            'wait 200', 'move 238 400', 'down', 'wait 60',
            'move 990 400', 'wait 60', 'echo split=', 'print-shape', 'up'])
        self.assertEqual(shapes['split'], 3)

    def test_splitter_hover_draws_accent_line(self):
        shots = [self.work / 'a.ppm', self.work / 'b.ppm']
        self.run_editor(['wait 200', 'move 500 400', 'shot ' + str(shots[0]),
                         'move 242 400', 'wait 60', 'shot ' + str(shots[1])])
        a, b = (ppm_pixels(p) for p in shots)
        w = 1000
        diffs = {(x, y) for y in range(len(a) // w // 3)
                 for x in range(w) if a[(y * w + x) * 3:(y * w + x) * 3 + 3]
                 != b[(y * w + x) * 3:(y * w + x) * 3 + 3]}
        self.assertTrue(diffs, 'no divider line on splitter hover')
        self.assertTrue(all(235 <= x <= 246 for x, _ in diffs),
                        'splitter hover changed pixels away from the divider')

    def test_scrollbar_flashes_on_scroll_then_hides(self):
        shots = [self.work / 'a.ppm', self.work / 'b.ppm', self.work / 'c.ppm']
        self.run_editor(['wait 200', 'move 500 400', 'shot ' + str(shots[0]),
                         'scroll 600', 'wait 60', 'shot ' + str(shots[1]),
                         'wait 1000', 'shot ' + str(shots[2])])
        px = lambda d, x, y: d[(y * 1000 + x) * 3:(y * 1000 + x) * 3 + 3]
        a, b, c = (ppm_pixels(p) for p in shots)
        thumb = [(x, y) for y in (200, 300, 400, 500) for x in range(985, 1000)]
        # scrolling alone reveals the thumb without hovering the track
        self.assertTrue(any(px(a, *t) != px(b, *t) for t in thumb),
                        'no thumb flash on scroll')
        self.assertTrue(all(px(a, *t) == px(c, *t) for t in thumb),
                        'thumb still shown after the flash window')

    def test_tooltip_instant_after_first(self):
        # adjacent toolbar tips skip the delay once one is open
        out = self.run_editor(['wait 200',
                               'move 770 14', 'wait 650', 'echo first=', 'print-tip',
                               'move 810 14', 'wait 60', 'echo second=', 'print-tip'])
        lines = out.splitlines()
        tips = {lines[i][:-1]: lines[i + 1]
                for i in range(len(lines) - 1) if lines[i].endswith('=')}
        self.assertIn('Terminal', tips['first'])
        self.assertIn('Agents', tips['second'])

    def test_icon_button_press_darkens(self):
        shots = [self.work / 'a.ppm', self.work / 'b.ppm']
        self.run_editor(['wait 200', 'move 12 14', 'wait 60', 'shot ' + str(shots[0]),
                         'down', 'wait 60', 'shot ' + str(shots[1]),
                         'move 500 400', 'up'])
        a, b = (ppm_pixels(p) for p in shots)
        i = lambda d: d[(8 * 1000 + 12) * 3:(8 * 1000 + 12) * 3 + 3]
        self.assertNotEqual(i(a), i(b), 'button bg did not change on press')


def ppm_pixels(path):
    return path.read_bytes().split(b'\n', 3)[3]


if __name__ == '__main__':
    unittest.main()
