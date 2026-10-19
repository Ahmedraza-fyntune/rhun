#!/usr/bin/env python3
"""The debug view (src/app/debugview.s): the Variables, Watch, Call Stack and Breakpoints sidebar
sections and the Debug Console panel tab (views' places and tree widget), driven with the keyboard
as a user would, and the debugger's keys (F5, F9, F10, Shift+F5, Ctrl+Shift+Y) and prompts."""
import unittest
import debughost


class View(debughost.DebugHost):
    def paused(self, extra, mode=None, line=3, files=('a.c',)):
        self.launch_ini()
        return self.run_editor(['bp %s %d' % (self.src, line), *self.start(), 'wait-debug paused', *extra],
                               mode=mode, files=files)

    def rows(self, out, prefix='row '):
        return [l for l in out if l.startswith(prefix)]

    def test_places_appear_with_a_session(self):
        out = self.paused(['print-sidebar', 'print-panel-tabs'])
        names = [l.split(' ')[0] for l in out]
        for name in ('debug.variables', 'debug.watch', 'debug.callstack', 'debug.breakpoints', 'debug.console'):
            self.assertIn(name, names)
        console = [l for l in out if l.startswith('debug.console')][0]
        self.assertIn('chosen', console)

    def test_hide_and_show(self):
        out = self.paused(['key ctrl+shift+y', 'print-sidebar', 'echo --', 'key ctrl+shift+y', 'print-sidebar'])
        first = out[:out.index('--')]
        self.assertFalse([l for l in first if l.startswith('debug.variables') and 'visible' in l], first)
        second = out[out.index('--'):]
        self.assertTrue([l for l in second if l.startswith('debug.variables') and 'visible' in l], second)

    def test_variables_tree(self):
        out = self.paused(['print-debug-tree variables'], line=9)
        rows = self.rows(out)
        self.assertIn('id=Locals label=Locals', rows[0])
        self.assertTrue(any('id=Locals/total label=total = 3 desc=int' in r for r in rows), rows)
        p = [r for r in rows if 'id=Locals/p ' in r][0]
        self.assertIn(' closed ', p)
        self.assertTrue(any('id=Globals' in r and ' closed ' in r for r in rows), rows)

    def test_opening_a_variable_with_the_keyboard(self):
        out = self.paused(['view-focus debug.variables', 'key Down', 'key Down', 'key Down', 'key Right',
                           'wait 300', 'print-debug-tree variables', 'print-vars'], line=9)
        rows = self.rows(out)
        self.assertTrue(any('id=Locals/p/x label=x = 1 desc=int' in r for r in rows), rows)
        self.assertIn('    x = 1 : int', out)

    def test_watch_section(self):
        out = self.paused(['debug-watch add total', 'debug-watch add nosuch', 'wait 300',
                           'print-debug-tree watch', 'view-focus debug.watch', 'key Down', 'key Down', 'key Delete',
                           'wait 200', 'print-debug-tree watch', 'print-watch'], line=9)
        rows = self.rows(out)
        self.assertIn('id=watch:total label=total = 3 desc=int', rows[0])
        self.assertIn("id=watch:nosuch label=nosuch = name 'nosuch' is not defined", rows[1])
        self.assertEqual(len(rows), 3, rows)               # nosuch removed by Delete
        self.assertIn('id=watch:total', rows[2])
        self.assertNotIn('nosuch', rows[2])
        self.assertEqual(out[-1], 'total = 3 : int')

    def test_watch_without_a_session(self):
        out = self.run_editor(['debug-watch add total', 'cmd debug_show', 'print-debug-tree watch'])
        self.assertEqual(self.rows(out), ['row 0 y=%s d=0 leaf id=watch:total label=total desc=not available'
                                          % self.rows(out)[0].split('y=')[1].split(' ')[0]])

    def test_call_stack_focus_frame(self):
        out = self.paused(['print-debug-tree stack', 'view-focus debug.callstack', 'key Down', 'key Down',
                           'key Down', 'key Down', 'key Return', 'wait 300', 'print-debug', 'print-vars'])
        rows = self.rows(out)
        self.assertIn('id=s1 label=Run desc=paused on breakpoint', rows[0])
        self.assertIn('id=s1/t1 label=main', rows[1])
        self.assertIn('id=s1/f0 label=add desc=a.c:3', rows[2])
        self.assertIn('id=s1/f1 label=main desc=a.c:8', rows[3])
        session = self.debug_lines(out)[0]
        self.assertEqual(self.field(session, 'frame'), '1')
        self.assertTrue(self.field(session, 'at').endswith('a.c:8'), session)
        self.assertIn('  total = 0 : int', out)             # main's locals now

    def test_breakpoints_section(self):
        out = self.paused(['bp-function add', 'print-debug-tree breakpoints', 'view-focus debug.breakpoints',
                           'key Down', 'key space', 'print-bps'])
        rows = self.rows(out)
        self.assertIn('check=1 id=b1 label=a.c:3 icon=14', rows[0])
        self.assertIn('check=1 id=b2 label=add()', rows[1])
        self.assertIn('%s 3 enabled=0 ' % self.src, out[-2])

    def test_exception_filters_in_the_breakpoints_section(self):
        out = self.paused(['print-debug-tree breakpoints'], mode='exceptions')
        rows = self.rows(out)
        self.assertTrue(any('check=0 id=x:raised label=Raised Exceptions' in r for r in rows), rows)
        self.assertTrue(any('check=1 id=x:uncaught label=Uncaught Exceptions' in r for r in rows), rows)

    def test_console_input_and_history(self):
        out = self.paused(['view-focus debug.console', 'type a', 'key Return', 'wait 200', 'type b', 'key Return',
                           'wait 200', 'key Up', 'key Up', 'key Return', 'wait 300', 'print-console'])
        self.assertEqual([l for l in out if l.startswith('input') or l.startswith('result')],
                         ['input a', 'result 0', 'input b', 'result 0', 'input a', 'result 0'])

    def test_keys(self):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')
        out = self.run_editor(['key ctrl+Home', 'key Down', 'key Down', 'key F9', 'print-bps',
                               'key F5', 'dialog yes', 'wait-debug paused', 'print-debug',
                               'key F10', 'wait-debug paused', 'print-debug',
                               'key F5', 'wait-debug paused', 'print-debug',
                               'key shift+F5', 'wait-debug ended', 'print-debug'])
        self.assertEqual(out[0], '%s 3 enabled=1 cond= hits= log= verified=- line=0 msg=' % self.src)
        sessions = self.debug_lines(out)
        self.assertEqual([self.field(l, 'reason') for l in sessions[:3]], ['entry', 'step', 'breakpoint'])
        self.assertEqual(self.field(sessions[3], 'state'), 'ended')

    def test_condition_prompt(self):
        self.launch_ini()
        out = self.run_editor(['key ctrl+Home', 'key Down', 'key Down', 'cmd debug_condition', 'print-palette',
                               'type b == 1', 'key Return', 'print-bps', 'cmd debug_condition',
                               'key ctrl+a', 'key BackSpace', 'key Return', 'print-bps'])
        self.assertIn('%s 3 enabled=1 cond=b == 1 hits= log=' % self.src, ' '.join(out))
        self.assertEqual(out[-1], '%s 3 enabled=1 cond= hits= log= verified=- line=0 msg=' % self.src)

    def test_add_watch_and_function_prompts(self):
        out = self.run_editor(['cmd debug_add_watch', 'type p.x', 'key Return',
                               'cmd debug_add_function_breakpoint', 'type main', 'key Return',
                               'print-bps', 'cmd debug_show', 'print-debug-tree watch'])
        self.assertIn('function main enabled=1 cond=', out)
        self.assertTrue(any('id=watch:p.x' in l for l in out), out)

    def test_open_configurations(self):
        out = self.run_editor(['cmd debug_open_configurations', 'print-tabs'])
        self.assertIn('launch.ini', [l for l in out if l.startswith('tabs=')][0])
        self.assertTrue((self.proj / '.rhun/launch.ini').read_text().startswith('# Launch configurations'))

    def toolbar(self, out):
        return {int(l.split()[1]): (int(l.split()[2]), int(l.split()[3]), int(l.split()[4]))
                for l in out if l.startswith('button ')}

    def test_toolbar(self):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')
        out = self.run_editor([*self.start(), 'wait-debug paused', 'print-debug-toolbar'])
        buttons = self.toolbar(out)
        self.assertEqual(sorted(buttons), [21, 149, 151, 152, 153, 154])   # restart, play, over, into, out, stop
        x, y, size = buttons[151]                                         # step over
        sx, sy, _ = buttons[154]
        out = self.run_editor([*self.start(), 'wait-debug paused', 'print-debug-toolbar',
                               'click %d %d' % (x + size // 2, y + size // 2), 'wait-debug paused', 'print-debug',
                               'click %d %d' % (sx + size // 2, sy + size // 2), 'wait-debug ended', 'print-debug'])
        sessions = self.debug_lines(out)
        self.assertEqual(self.field(sessions[0], 'reason'), 'step', out)
        self.assertEqual(self.field(sessions[1], 'state'), 'ended', out)

    def test_toolbar_without_debugging(self):
        steps = self.steps()
        steps[3]['block'] = True
        self.scenario(steps)
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\n')
        out = self.run_editor([*self.start(run=True), 'wait 300', 'print-debug-toolbar'])
        self.assertEqual(sorted(self.toolbar(out)), [21, 154])

    def test_context_keys(self):
        out = self.paused(['print-context', 'echo --', 'debug-stop', 'wait-debug ended', 'wait 50', 'print-context'])
        first = out[:out.index('--')]
        self.assertIn('debugState=stopped', first)
        self.assertIn('inDebugMode=true', first)
        self.assertIn('debugType=fake', first)
        second = out[out.index('--'):]
        self.assertIn('debugState=inactive', second)
        self.assertIn('inDebugMode=false', second)

    def test_keys_reach_the_debugger_from_the_terminal(self):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')
        out = self.run_editor([*self.start(), 'wait-debug paused', 'cmd toggle_terminal', 'wait 300', 'print-state',
                               'key F10', 'wait-debug paused', 'print-debug'])
        state = [l for l in out if l.startswith('tabs=')][0]
        self.assertIn(' focus=8 ', state)            # the terminal has the keyboard
        self.assertEqual(self.field(self.debug_lines(out)[0], 'reason'), 'step', out)


if __name__ == '__main__':
    unittest.main()
