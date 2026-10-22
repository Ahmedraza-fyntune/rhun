#!/usr/bin/env python3
"""The debugger's second review (Codex, round 2), one test per finding: answers about another frame's
variables, watch rounds per session, frame rows of another session, superseded hover answers, the
console's keys and paste, the selected configuration after launch.ini changes, the gutter after a
file is reopened, and the debug view's first toggle, show_on_start and focus when hidden."""
import unittest
import debughost

TWO = '[Run]\ntype = fake\nprogram = scenario.json\n[Two]\ntype = fake\nprogram = scenario.json\n'


class Review(debughost.DebugHost):
    def two_paused(self, extra, mode=None):
        self.scenario()
        self.launch_ini(TWO)
        return self.run_editor(['bp %s 3' % self.src, *self.start(), 'wait-debug paused', 'debug-start Two',
                                'wait 600', *extra], mode=mode)

    def vars(self, out):
        return [l for l in out if l.startswith('  ') and ' = ' in l]

    def test_another_frames_variables_are_dropped(self):
        # slow answers: the scopes and variables asked for frame 1 come after frame 0 is back
        self.launch_ini()
        out = self.run_editor(['bp %s 3' % self.src, *self.start(), 'wait-debug paused', 'wait 1500',
                               'debug-frame 1', 'debug-frame 0', 'wait 3000', 'print-debug', 'print-vars'],
                              mode='slow=150')
        session = self.debug_lines(out)[0]
        self.assertEqual(self.field(session, 'frame'), '0', out)
        tops = [l for l in out if l in ('Locals', 'Globals')]
        self.assertEqual(tops, ['Locals', 'Globals'], out)      # no duplicate scope roots
        names = [l.split(' = ')[0].strip() for l in self.vars(out)]
        self.assertEqual(names, ['a', 'b', 's'], out)            # add's locals, not main's

    def test_watch_rounds_are_per_session(self):
        # both sessions stop and evaluate the watch about together; the first one's answers stand
        self.scenario()
        self.launch_ini(TWO)
        out = self.run_editor(['debug-watch add a', 'bp %s 3' % self.src, *self.start(), 'debug-start Two',
                               'wait 2500', 'view-focus debug.callstack', 'key Down', 'key Return',
                               'print-watch'], mode='slow=100')
        self.assertEqual(out[-1], 'a = 0 : int', out)

    def test_a_frame_row_focuses_its_own_session(self):
        out = self.two_paused(['view-focus debug.callstack', 'key Down', 'key Down', 'key Down', 'key Down',
                               'key Return', 'wait 300', 'print-debug', 'print-vars'])
        s1, s2 = self.debug_lines(out)[-2:]
        self.assertEqual(self.field(s1, 'frame'), '1', out)
        self.assertEqual(self.field(s2, 'frame'), '0', out)
        self.assertIn('  total = 0 : int', out)                  # session 1's main, now focused

    def hover_xy(self, col):
        out = self.run_editor([*self.start(), 'wait-debug paused', 'print-xy 2 %d' % col], files=('h.c',))
        return map(int, out[-1].split())

    def test_a_superseded_hover_answer_is_dropped(self):
        h = self.proj / 'h.c'
        h.write_text('int f(void) {\n    return p->x + p.y + total;\n}\n')
        self.scenario([{'file': h.as_posix(), 'line': 2, 'function': 'f',
                        'locals': {'total': 3, 'p': {'x': 1, 'y': 2}}}])
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')
        x1, y = self.hover_xy(26)                                # total
        x2, _ = self.hover_xy(15)                                # the x of p->x
        out = self.run_editor([*self.start(), 'wait-debug paused', 'wait 1500', 'move %d %d' % (x1 + 2, y),
                               'wait 650', 'move %d %d' % (x2 + 2, y), 'wait 650', 'print-debug-hover',
                               'wait 450', 'print-debug-hover', 'wait 1500', 'print-debug-hover'],
                              files=('h.c',), mode='slow=600')
        hovers = [l for l in out if '=' in l and ('total' in l or 'p->x' in l) or l == 'none']
        self.assertNotIn('p->x = 3  int', hovers, out)          # total's answer under p->x's name
        self.assertEqual(hovers[-1], 'p->x = 1  int', out)

    def test_console_keys_it_does_not_take_reach_the_debugger(self):
        self.launch_ini()
        out = self.run_editor(['bp %s 3' % self.src, *self.start(), 'wait-debug paused', 'view-focus debug.console',
                               'key F10', 'wait-debug paused', 'print-debug'])
        self.assertEqual(self.field(self.debug_lines(out)[-1], 'reason'), 'step', out)

    def test_paste_into_the_console(self):
        self.launch_ini()
        out = self.run_editor(['bp %s 3' % self.src, *self.start(), 'wait-debug paused', 'key ctrl+Home',
                               *(['key Right'] * 4), *(['key shift+Right'] * 3), 'key ctrl+c',
                               'view-focus debug.console', 'key ctrl+v', 'key Return', 'wait 300', 'print-console'])
        self.assertIn('input add', out)

    def test_the_selection_follows_launch_ini(self):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\n')
        ini = self.proj / '.rhun/launch.ini'
        out = self.run_editor(['key F5', 'dialog yes', 'wait-debug ended', 'open %s' % ini, 'key ctrl+a',
                               'type [Other]', 'key Return', 'type type = fake', 'key Return',
                               'type program = scenario.json', 'key Return', 'key ctrl+s', 'wait 2100',
                               'key F5', 'wait-debug ended', 'print-debug', 'print-console'])
        self.assertEqual(self.field(self.debug_lines(out)[-1], 'name'), 'Other', out)
        self.assertFalse([l for l in out if 'no configuration' in l], out)

    def test_glyphs_after_the_file_is_reopened(self):
        self.launch_ini()
        out = self.run_editor(['bp %s 3' % self.src, 'cmd debug_show', 'wait 100', 'cmd close_tab', 'wait 100',
                               'open %s' % self.src, 'wait 200', 'print-present glyphs'])
        self.assertTrue([l for l in out if l.startswith('glyph 3 ')], out)

    def visible(self, out, name='debug.variables'):
        return [l for l in out if l.startswith(name) and 'visible' in l]

    def test_the_first_toggle_shows_the_view(self):
        out = self.run_editor(['key ctrl+shift+y', 'print-sidebar'])
        self.assertTrue(self.visible(out), out)

    def test_show_on_start_off_keeps_the_sections_hidden(self):
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[debug]\nshow_on_start = false\n')
        self.launch_ini()
        out = self.run_editor(['bp %s 3' % self.src, *self.start(), 'wait-debug paused', 'print-sidebar'])
        self.assertFalse(self.visible(out), out)

    def test_hiding_gives_the_keyboard_back_to_the_editor(self):
        self.launch_ini()
        out = self.run_editor(['bp %s 3' % self.src, *self.start(), 'wait-debug paused',
                               'view-focus debug.variables', 'key ctrl+shift+y', 'print-state'])
        state = [l for l in out if l.startswith('tabs=')][-1]
        self.assertIn(' focus=0 ', state)                   # FOCUS_EDITOR


if __name__ == '__main__':
    unittest.main()
