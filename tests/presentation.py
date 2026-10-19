#!/usr/bin/env python3
"""Editor presentation, stages 0-2: the frame probes, the view and hit-test print commands, the
edit tape (through decorations sent for older versions), decorations (feature `decorations`:
types, ranges, caps, drawing, tips, the visible event) and the gutter's glyph lane (the built-in
API through the glyph-test kind). Driven headlessly with the fake extension tests/ext/present.py."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

host = __import__('ext-host')
ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
PRESENT = ROOT / 'tests/ext/present.py'
TEXT = 'fn main() {\n    let x = 1;\n    let y = x + 2;\n    println!("{}", y);\n}\n'
MANIFEST = '''name = present
owner = rhun-tests
title = Present
version = 0.0.1
protocol = 1
runtime = python3
run = {run}
on = command
[commands]
a = Step A
b = Step B
c = Step C
d = Step D
e = Step E
f = Step F
g = Step G
h = Step H
[subscribe]
opened = *
changed = *
[needs]
documents = read
'''


def rgb(hexstr):
    return tuple(int(hexstr[i:i + 2], 16) for i in (0, 2, 4))


class Base(unittest.TestCase):
    """An isolated run of rhun with the present extension (the host tests' harness, without
    their tests)."""
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-pres-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(host.CONFIG, encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix())
        for k in ('PRESENT_STEPS', 'PRESENT_ANSWERS', 'PRESENT_HELLO', 'RHUN_STALE', 'RHUN_UNDERPAINT'):
            self.env.pop(k, None)
        (self.proj / 'm.rs').write_text(TEXT, encoding='utf-8')
        self.exts = self.work / 'pexts'
        folder = self.exts / 'rhun-tests/present'
        folder.mkdir(parents=True)
        (folder / 'extension.ini').write_text(MANIFEST.format(run=PRESENT.as_posix()), encoding='utf-8')
        # a confined program reads its own folder and writes its state folder
        self.plog = self.work / 'state/rhun/extensions/rhun-tests--present/present.log'
        self.env['PRESENT_LOG'] = self.plog.as_posix()

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions, exts, files=('m.rs',), size='1000x600'):
        opens = ['open ' + (self.proj / name).as_posix() for name in files]
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', *opens, *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', size, '--scale', '1',
                                 '--extensions', str(exts), '--script', script.as_posix()],
                                env=self.env, capture_output=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8', errors='replace').splitlines()

    def steps(self, steps, hello='hello 1 decorations'):
        path = self.exts / 'rhun-tests/present/steps.json'
        path.write_text(json.dumps(steps), encoding='utf-8')
        self.env['PRESENT_STEPS'] = path.as_posix()
        self.env['PRESENT_HELLO'] = hello

    def run_p(self, actions, files=('m.rs',), **kw):
        return self.run_editor(actions, exts=self.exts, files=files, **kw)

    def replies(self):
        if not self.plog.exists():
            return []
        return [l for l in self.plog.read_text(errors='replace').splitlines()
                if l.startswith('ok ') or l.startswith('error ')]

    def events(self, name):
        if not self.plog.exists():
            return []
        return [l for l in self.plog.read_text(errors='replace').splitlines() if l.startswith('0 ' + name)]

    def start(self):
        return ['cmd present.a', 'wait-ext present running', 'wait 200']

    def shot(self, actions, name='p.ppm', **kw):
        path = self.work / name
        self.run_p(actions + [f'shot {path}'], **kw)
        return path


class Presentation(Base):
    # ---------------- stage 0: probes and print commands ----------------

    def test_view_xy_and_hit_agree_with_the_text_cells(self):
        out = self.run_p(['print-view', 'print-xy 2 5', 'print-text-cell 2 5', 'print-hit 10 0'])
        self.assertTrue(out[0].startswith('view mode=lines top=1 off=0 rows='), out)
        x, y = map(int, out[1].split())
        cx, cy = map(int, out[2].split())
        self.assertEqual(y, cy)
        self.assertLess(x, cx)              # the caret's edge, half a cell before the middle
        out = self.run_p([f'print-hit {cx} {cy}', f'print-hit {x - 1} {cy}', 'print-hit 3 ' + str(cy)])
        self.assertEqual(out[0], 'text 2 5')
        self.assertTrue(out[1].startswith('git 2') or out[1] == 'text 2 1', out)
        self.assertEqual(out[2], 'left-lane 2')

    def test_probes_log_planted_faults_and_nothing_else(self):
        stale = self.work / 'stale.log'
        under = self.work / 'under.log'
        self.env['RHUN_STALE'] = stale.as_posix()
        self.env['RHUN_UNDERPAINT'] = under.as_posix()
        self.run_p(['type x', 'key Return', 'print-view'])
        self.assertFalse(stale.exists(), stale.read_text() if stale.exists() else '')
        self.assertFalse(under.exists(), under.read_text() if under.exists() else '')
        self.run_p(['probe-plant stale', 'print-view', 'probe-plant under', 'print-view'])
        self.assertIn('stale probe-plant stale | ', stale.read_text())
        self.assertIn('underpaint probe-plant under | ', under.read_text())

    # ---------------- stage 2: decoration types ----------------

    def test_types_register_replace_and_report_bad_lines(self):
        self.steps({'a': [
            ['decoration-type warn {LEN}', 'color #ff0000\nbackground warning/30|#00ff00\nunderline squiggle error\npriority 70\n'],
            ['decoration-type warn {LEN}', 'faded\n'],
            ['decoration-type bad {LEN}', 'color #ff0000\nwobble 3\n'],
            ['decoration-type Bad! {LEN}', 'faded\n'],
            ['decoration-type bad2 {LEN}', 'border 4 #ff0000\n'],
            ['decoration-type bad3 {LEN}', 'color nosuchslot\n'],
        ]})
        out = self.run_p(self.start() + ['print-present types'])
        self.assertEqual([l for l in out if l.startswith('type ')],
                         ['type rhun-tests/present warn flags=64 prio=50'])
        self.assertEqual(self.replies(), ['ok 1', 'ok 2', 'error 3 syntax line 2', 'error 4 syntax cannot parse the line',
                                          'error 5 syntax line 1', 'error 6 syntax line 1'])

    def test_type_caps(self):
        self.steps({'a': [[f'decoration-type t{i} {{LEN}}', 'faded\n'] for i in range(65)]})
        self.run_p(self.start())
        self.assertEqual(self.replies()[-1], 'error 65 toobig 64 decoration types per extension, 512 in all')
        self.assertEqual(len([r for r in self.replies() if r.startswith('ok ')]), 64)

    def test_unagreed_feature_is_unknown(self):
        self.steps({'a': [['decoration-type t {LEN}', 'faded\n']]}, hello='hello 1')
        self.run_p(self.start())
        self.assertEqual(self.replies(), ['error 1 unknown no such request'])

    # ---------------- stage 2: ranges ----------------

    def test_decorate_replaces_by_type_and_lines(self):
        self.steps({'a': [
            ['decoration-type t {LEN}', 'faded\n'],
            ['decoration-type u {LEN}', 'faded\n'],
            ['decorate {DOC} {VER} t 0 0 3 {LEN}', '1 1 1 3 0 0 0 0\n2 5 2 8 2 3 4 0\nabxyzwarn3 1 3 4 0 0 0 0\n'],
            ['decorate {DOC} {VER} u 0 0 1 {LEN}', '4 1 4 3 0 0 0 0\n'],
        ], 'b': [
            ['decorate {DOC} {VER} t 2 3 1 {LEN}', '2 1 2 2 0 0 0 0\n'],
        ], 'c': [
            ['decorate {DOC} {VER} t 0 0 0 0', ''],
        ]})
        out = self.run_p(self.start() + ['print-present deco', 'cmd present.b', 'wait 200', 'print-present deco',
                                         'cmd present.c', 'wait 200', 'print-present deco'])
        first = out[out.index('deco t 1:1-1:3'):][:4]
        self.assertEqual(first, ['deco t 1:1-1:3', 'deco t 2:5-2:8 before=ab after=xyz tip=warn',
                                 'deco t 3:1-3:4', 'deco u 4:1-4:3'])
        second = [l for l in out if l.startswith('deco ')][4:7]
        self.assertEqual(second, ['deco t 1:1-1:3', 'deco t 2:1-2:2', 'deco u 4:1-4:3'])
        self.assertEqual([l for l in out if l.startswith('deco ')][7:], ['deco u 4:1-4:3'])

    def test_decorate_errors(self):
        self.steps({'a': [
            ['decoration-type t {LEN}', 'faded\n'],
            ['decorate {DOC} {VER} nosuch 0 0 0 0', ''],
            ['decorate {DOC} {VER} t 0 0 1 {LEN}', '9 1 9 2 0 0 0 0\n'],
            ['decorate {DOC} {VER} t 0 0 1 {LEN}', '2 2 1 1 0 0 0 0\n'],
            ['decorate 999 1 t 0 0 0 0', ''],
            ['decorate {DOC} 9999 t 0 0 0 0', ''],
            ['decorate {DOC} {VER} t 0 0 2 {LEN}', '1 1 1 2 0 0 0 0\n'],
            ['decorate {DOC} {VER} t 0 0 1 {LEN}', '1 1 1 2 201 0 0 0\n' + 'x' * 201],
            ['decorate {DOC} {VER} t 0 0 1 {LEN}', '1 1 1 2 1 0 0 0\n\x01'],
        ]})
        self.run_p(self.start())
        r = self.replies()
        self.assertEqual(r[1], 'error 2 syntax unknown decoration type')
        self.assertEqual(r[2], 'error 3 badpos position outside the document or inside a character')
        self.assertEqual(r[3], 'error 4 badpos position outside the document or inside a character')
        self.assertEqual(r[4], 'error 5 nodoc no such document')
        self.assertTrue(r[5].startswith('error 6 stale '), r)
        self.assertEqual(r[6], 'error 7 syntax cannot parse the line')
        self.assertEqual(r[7], 'error 8 toobig more decorations than the caps allow')
        self.assertEqual(r[8], 'error 9 syntax cannot parse the line')

    def test_ranges_move_with_edits_and_grow_by_their_type(self):
        self.steps({'a': [
            ['decoration-type none {LEN}', 'faded\n'],
            ['decoration-type both {LEN}', 'faded\ngrow both\n'],
            ['decorate {DOC} {VER} none 0 0 2 {LEN}', '2 9 2 10 0 0 0 0\n3 5 3 8 0 0 0 0\n'],
            ['decorate {DOC} {VER} both 0 0 1 {LEN}', '2 9 2 10 0 0 0 0\n'],
        ]})
        # "x" (2:9-2:10) gets "ab" before and after it; line 3's "let" is deleted
        out = self.run_p(self.start() + ['key ctrl+Home', 'key Down', 'key End', 'key Left', 'key Left',
                                         'key Left', 'key Left', 'key Left', 'key Left', 'type ab', 'key Right',
                                         'type cd', 'key Down', 'key Home', 'key shift+End', 'key BackSpace',
                                         'print-present deco'])
        decos = [l for l in out if l.startswith('deco ')]
        self.assertEqual(decos, ['deco none 2:11-2:12', 'deco both 2:9-2:14'])

    def test_older_versions_are_moved_through_the_tape(self):
        self.steps({'a': [['decoration-type t {LEN}', 'faded\n']],
                    'b': [['decorate {DOC} {VER-2} t 0 0 2 {LEN}', '2 5 2 8 0 0 0 0\n3 13 3 14 0 0 0 0\n']]})
        # two lines inserted at the top, then an edit inside line 2's "let": three versions on
        out = self.run_p(self.start() + ['key ctrl+Home', 'type //\n', 'type \n', 'cmd present.b', 'wait 200',
                                         'print-present deco', 'print-present tape'])
        decos = [l for l in out if l.startswith('deco ')]
        self.assertEqual(decos, ['deco t 3:5-3:8', 'deco t 4:13-4:14'], out)

    def test_too_old_a_version_is_stale(self):
        self.steps({'a': [['decoration-type t {LEN}', 'faded\n']],
                    'b': [['decorate {DOC} 0 t 0 0 0 0', '']]})
        actions = self.start() + ['key ctrl+End'] + ['type x'] * 300 + ['cmd present.b', 'wait 200']
        self.run_p(actions)
        self.assertTrue(self.replies()[-1].startswith('error 2 stale '), self.replies())

    def test_stopping_the_extension_clears_its_decorations(self):
        self.steps({'a': [['decoration-type t {LEN}', 'faded\n'],
                          ['decorate {DOC} {VER} t 0 0 1 {LEN}', '1 1 1 3 0 0 0 0\n']]})
        out = self.run_p(self.start() + ['print-present deco', 'ext-set present stop', 'wait 300',
                                         'print-present deco', 'print-present types'])
        self.assertEqual([l for l in out if l.startswith('deco ') or l.startswith('type ')], ['deco t 1:1-1:3'])

    # ---------------- stage 2: drawing ----------------

    def test_styles_are_drawn(self):
        self.steps({'a': [
            ['decoration-type bg {LEN}', 'background #ff0000\n'],
            ['decoration-type line {LEN}', 'line-background #0000ff\n'],
            ['decoration-type ul {LEN}', 'underline solid #00ff00\n'],
            ['decoration-type st {LEN}', 'strike #ff00ff\n'],
            ['decoration-type fg {LEN}', 'color #ffff00\n'],
            ['decoration-type icon {LEN}', 'gutter square #00ffff\nscrollbar #ff8000\n'],
            ['decorate {DOC} {VER} bg 0 0 1 {LEN}', '2 5 2 8 0 0 0 0\n'],
            ['decorate {DOC} {VER} line 0 0 1 {LEN}', '4 1 4 1 0 0 0 0\n'],
            ['decorate {DOC} {VER} ul 0 0 1 {LEN}', '3 5 3 8 0 0 0 0\n'],
            ['decorate {DOC} {VER} st 0 0 1 {LEN}', '3 9 3 10 0 0 0 0\n'],
            ['decorate {DOC} {VER} fg 0 0 1 {LEN}', '1 1 1 3 0 0 0 0\n'],
            ['decorate {DOC} {VER} icon 0 0 1 {LEN}', '5 1 5 2 0 0 0 0\n'],
        ]})
        path = self.shot(self.start())
        colors = host.ppm_colors(path)
        for c in ('ff0000', '0000ff', '00ff00', 'ff00ff', 'ffff00', '00ffff', 'ff8000'):
            self.assertTrue(rgb(c) in colors, c)
        # the background sits under line 2's "let", the line background across line 4
        out = self.run_p(['print-xy 2 5', 'print-xy 2 8', 'print-xy 4 1'])
        (x1, y2), (x2, _), (_, y4) = (tuple(map(int, l.split())) for l in out[:3])
        self.assertEqual(host.ppm_pixel(path, x1 + 1, y2 - 3), rgb('ff0000'))
        self.assertNotEqual(host.ppm_pixel(path, x2 + 2, y2 - 3), rgb('ff0000'))
        self.assertEqual(host.ppm_pixel(path, 600, y4), rgb('0000ff'))

    def test_hover_shows_a_decorations_tip(self):
        self.steps({'a': [['decoration-type t {LEN}', 'faded\n'],
                          ['decorate {DOC} {VER} t 0 0 1 {LEN}', '2 5 2 8 0 0 13 0\nlet binding x']]})
        cell = self.run_p(['print-text-cell 2 6'])[0]
        out = self.run_p(self.start() + [f'move {cell}', 'wait 650', 'print-tip'])
        self.assertIn('let binding x', '\n'.join(out))

    def test_visible_event_follows_the_view(self):
        (self.proj / 'long.rs').write_text(''.join(f'line {i}\n' for i in range(400)), encoding='utf-8')
        self.steps({})
        self.run_p(self.start() + ['scroll 2000', 'wait 300', 'scroll 2000', 'wait 300'], files=('long.rs',))
        ev = self.events('visible')
        self.assertGreaterEqual(len(ev), 2, ev)
        first, last = ev[0].split(), ev[-1].split()
        self.assertEqual(first[3], '1')
        self.assertGreater(int(last[3]), 1)

    # ---------------- stage 2: the glyph lane ----------------

    def test_glyph_api_clicks_edits_and_tips(self):
        out = self.run_p(['glyph-test', 'glyph 3 6', 'print-present glyphs', 'print-xy 3 1'])
        self.assertIn('glyph 3 kind=1 shape=6', out)
        _, y3 = map(int, out[-1].split())
        out = self.run_p(['glyph-test', 'glyph 3 6', f'print-hit 4 {y3}', f'click 4 {y3}',
                          f'click 4 {y3 - 21}', f'click 4 {y3 - 21}', f'click 4 {y3} right',
                          'print-present glyphs'])
        self.assertEqual(out[0], 'left-lane 3')
        self.assertIn('click 3 1 6', out)       # the kind's glyph
        self.assertIn('click 2 1 0', out)       # an empty line: the GK_EMPTY kind, glyph 0
        self.assertIn('click 2 1 2', out)       # its circle, the second time
        self.assertIn('click 3 3 6', out)       # right button
        self.assertNotIn('glyph 2 kind=1 shape=2', out)
        # two lines inserted above move it down; deleting its line gives it to the next one
        out = self.run_p(['glyph-test', 'glyph 3 6', 'glyph 4 7', 'key ctrl+Home', 'type a\nb\n',
                          'print-present glyphs', 'key Down', 'key Down', 'key Down', 'key Home',
                          'key shift+Down', 'key BackSpace', 'print-present glyphs'])
        self.assertEqual([l for l in out if l.startswith('glyph')][:2],
                         ['glyph 5 kind=1 shape=6', 'glyph 6 kind=1 shape=7'])
        self.assertEqual([l for l in out if l.startswith('glyph')][2:], ['glyph 5 kind=1 shape=6'])
        out = self.run_p(['glyph-test', 'glyph 3 6', f'move 4 {y3}', 'wait 650', 'print-tip'])
        self.assertIn('Test glyph', '\n'.join(out))

    def test_glyph_lane_drawn_and_reserved_without_line_numbers(self):
        path = self.shot(['glyph-test', 'glyph 2 2', 'print-xy 2 1'])
        out = self.run_p(['print-xy 2 1'])
        _, y2 = map(int, out[0].split())
        accent = host.ppm_pixel(path, 8, y2)
        self.assertNotEqual(accent, host.ppm_pixel(path, 8, y2 + 21))
        out = self.run_p(['cmd toggle_line_numbers', 'print-xy 2 1', 'glyph-test', 'print-xy 2 1',
                          'print-hit 4 ' + str(y2), 'print-hit 20 ' + str(y2), 'cmd toggle_line_numbers'])
        x_before, x_after = int(out[0].split()[0]), int(out[1].split()[0])
        self.assertEqual(x_after - x_before, 16)
        self.assertEqual(out[2], 'left-lane 2')
        self.assertEqual(out[3], 'git 2')


if __name__ == '__main__':
    unittest.main()
