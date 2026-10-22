#!/usr/bin/env python3
"""Keys as data with chords (docs/guide.md "Keys", docs/extensions/v1.1.md "Keys"): built-in and
extension chords, the pause and its fallback, Escape and unbound second strokes, the user's [keys]
grammar (ARGS, when, none), precedence of user > extension [keys] > built-in > extension
[commands] defaults, the guard extensions need for typing keys, a layout that is not Latin, and
the Keyboard Shortcuts list."""
import sys
import unittest

contribhost = __import__('contribhost')
MAC = sys.platform == 'darwin'
CTRL = '⌘' if MAC else 'Ctrl+'


class Keys(contribhost.Contrib):
    def setUp(self):
        super().setUp()
        self.config = self.work / 'config/rhun/config'

    def user_keys(self, text):
        self.config.write_text(self.config.read_text() + '[keys]\n' + text)

    def exts(self, keys='', commands=('ping = Ping', 'pong = Pong')):
        root = self.work / 'exts'
        self.make_ext(root, hello='hello 1 command-args', commands=commands,
                      extra='[keys]\n' + keys if keys else '')
        return root

    def runs(self):
        lines = self.contrib_log()
        return [(l, lines[i + 1]) for i, l in enumerate(lines) if l.startswith('0 run ')]

    def panels(self, out):
        return [l for l in out if l.startswith('explorer=')]

    def test_builtin_chord_opens_the_theme_list(self):
        out = self.run_editor(drop_waits=True, actions=[
            'key ctrl+k', 'print-chord', 'key ctrl+t', 'print-chord', 'print-palette'])
        prefix = 'chord=' + CTRL + 'K fallback=- ms='
        self.assertTrue(out[0].startswith(prefix), out)
        self.assertTrue(4800 <= int(out[0][len(prefix):]) <= 5000, out)   # a busy machine takes some ms
        self.assertEqual(out[1], 'chord=none')
        self.assertIn('  GitHub Dark', out)

    def test_escape_unbound_and_timeout(self):
        out = self.run_editor(drop_waits=True, actions=[
            'key ctrl+k', 'key Escape', 'print-chord', 'print-toast',
            'key ctrl+k', 'key shift', 'print-chord', 'key ctrl+x', 'print-chord', 'print-toast',
            'key ctrl+k', 'wait 2600', 'wait 2600', 'print-chord', 'print-doc'])
        self.assertEqual(out[:2], ['chord=none', 'toast='])
        self.assertTrue(out[2].startswith('chord=' + CTRL + 'K'), out)
        self.assertEqual(out[3:5], ['chord=none', 'toast=' + CTRL + 'K ' + CTRL + 'X is not bound'])
        self.assertEqual(out[5], 'chord=none')
        self.assertEqual(out[6], 'hello world')       # nothing was cut or typed

    def test_click_cancels(self):
        out = self.run_editor(drop_waits=True, actions=['key ctrl+k', 'click 500 300', 'print-chord'])
        self.assertEqual(out, ['chord=none'])

    def test_user_override_and_none(self):
        self.user_keys('ctrl+k ctrl+t = toggle_sidebar\nctrl+b = none\n')
        out = self.run_editor(drop_waits=True, actions=[
            'print-panels', 'key ctrl+k', 'key ctrl+t', 'print-panels', 'key ctrl+b', 'print-panels',
            'print-keys'])
        self.assertEqual(self.panels(out)[:3], ['explorer=0 agents=0 term=0'] + ['explorer=1 agents=0 term=0'] * 2)
        self.assertIn('ctrl+k ctrl+t select_theme source=builtin rank=2 state=shadowed:user', out)
        self.assertIn('ctrl+k ctrl+t toggle_sidebar source=user rank=4 state=active', out)
        self.assertIn('ctrl+b none source=user rank=4 state=active', out)

    def test_user_binding_with_args_and_when(self):
        self.user_keys('ctrl+alt+u = alice/demo.ping hello there when editorFocus\n'
                       'ctrl+alt+i = demo.pong when findFocus\n'
                       'ctrl+alt+o = demo.pong when resourceExtt\n')
        out = self.run_editor(exts=self.exts(), drop_waits=True, actions=[
            'key ctrl+alt+u', 'wait-ext demo running', 'wait 300', 'key ctrl+alt+i', 'wait 200',
            'print-keys'])
        self.assertEqual(self.runs(), [('0 run demo.ping 1 key 11', 'body=hello there')])
        self.assertIn('ctrl+alt+u alice/demo.ping source=user rank=4 args=hello there when=editorFocus '
                      'state=active', out)
        self.assertIn('ctrl+alt+o demo.pong source=user rank=4 state=refused:when', out)

    def test_extension_keys_and_their_checks(self):
        keys = ('ctrl+k ctrl+c = ping when editorFocus\n'
                'ctrl+k ctrl+u = rhun.toggle_sidebar\n'
                'x = ping\n'
                'Delete = pong when viewFocus\n'
                'y = pong when view == \'\'\n'
                'z = pong when view == \'alice/demo.files\'\n'
                'ctrl+Tab = pong when !textInputFocus && editorFocus\n'
                'Return = pong when editorFocus || !textInputFocus\n'
                'k ctrl+c = ping\n'
                'ctrl+alt+n = missing\n'
                'linux:ctrl+alt+y = ping\nmac:ctrl+alt+y = pong\nwindows:ctrl+alt+y = ping\n')
        out = self.run_editor(exts=self.exts(keys), drop_waits=True, actions=[
            'key ctrl+k', 'key ctrl+c', 'wait-ext demo running', 'wait 300',
            'key ctrl+k', 'key ctrl+u', 'print-panels', 'key x', 'print-doc', 'print-keys demo'])
        self.assertEqual(self.runs()[0][0], '0 run demo.ping 1 key 0')
        self.assertIn('explorer=1 agents=0 term=0', out)
        self.assertIn('xhello world', out)
        self.assertIn('x ping source=ext:alice/demo rank=3 state=refused:typing', out)
        self.assertIn('Delete pong source=ext:alice/demo rank=3 when=viewFocus state=active', out)
        self.assertIn("y pong source=ext:alice/demo rank=3 when=view == '' state=refused:typing", out)
        self.assertIn("z pong source=ext:alice/demo rank=3 when=view == 'alice/demo.files' state=active", out)
        self.assertIn('ctrl+Tab pong source=ext:alice/demo rank=3 when=!textInputFocus && editorFocus '
                      'state=active', out)
        self.assertIn('Return pong source=ext:alice/demo rank=3 when=editorFocus || !textInputFocus '
                      'state=refused:typing', out)
        self.assertIn('k ctrl+c ping source=ext:alice/demo rank=3 state=refused:prefix', out)
        self.assertIn('ctrl+alt+n missing source=ext:alice/demo rank=3 state=refused:command', out)
        mine = 'pong' if MAC else 'ping'
        self.assertEqual([l for l in out if l.startswith('ctrl+alt+y')],
                         ['ctrl+alt+y ' + mine + ' source=ext:alice/demo rank=3 state=active'])

    def test_long_args_are_refused(self):
        self.user_keys('ctrl+alt+u = alice/demo.ping ' + 'a' * 4097 + '\n')
        out = self.run_editor(exts=self.exts(), drop_waits=True, actions=['print-keys'])
        self.assertTrue(any(l.startswith('ctrl+alt+u alice/demo.ping') and l.endswith('state=refused:args')
                            for l in out), [l for l in out if 'ctrl+alt+u' in l])

    def test_precedence(self):
        # an extension's [keys] beats the built-in; the user's beats it; [commands] defaults lose
        self.user_keys('ctrl+e = toggle_sidebar\n')
        out = self.run_editor(exts=self.exts('ctrl+b = ping\nctrl+e = pong\n',
                                             commands=('ping = Ping', 'pong = Pong', 'def = Def | ctrl+g ctrl+alt+d')),
                              drop_waits=True, actions=[
            'key ctrl+b', 'wait-ext demo running', 'wait 300', 'key ctrl+e', 'print-panels',
            'key ctrl+alt+d', 'wait 300', 'print-keys demo'])
        self.assertEqual([r[0] for r in self.runs()], ['0 run demo.ping 1 key 0', '0 run demo.def 1 key 0'])
        self.assertIn('explorer=1 agents=0 term=0', out)
        self.assertIn('ctrl+g demo.def source=default:alice/demo rank=1 state=shadowed:builtin', out)
        self.assertIn('ctrl+e pong source=ext:alice/demo rank=3 state=shadowed:user', out)

    def test_long_fallback_title_is_cut_in_the_status_bar(self):
        # the "or pause for TITLE" text has a fixed buffer: a 600-byte title (with a multibyte
        # character at the cut) must not overrun it
        keys = 'ctrl+alt+k = ping\nctrl+alt+k ctrl+alt+j = rhun.toggle_sidebar\n'
        title = 'é' * 300
        shot = self.work / 'chord.ppm'
        out = self.run_editor(exts=self.exts(keys, commands=('ping = ' + title, 'pong = Pong')), drop_waits=True,
                              actions=['key ctrl+alt+k', 'shot ' + shot.as_posix(), 'print-chord', 'key Escape',
                                       'print-chord'])
        self.assertTrue(out[0].startswith('chord=') and 'fallback=demo.ping' in out[0], out)
        self.assertEqual(out[-1], 'chord=none')
        self.assertTrue(shot.exists())

    def test_pause_runs_the_single_stroke(self):
        keys = 'ctrl+alt+k = ping\nctrl+alt+k ctrl+alt+j = rhun.toggle_sidebar\n'
        out = self.run_editor(exts=self.exts(keys), drop_waits=True, actions=[
            'key ctrl+alt+k', 'print-chord', 'wait 600', 'wait 600', 'print-chord',
            'wait-ext demo running', 'wait 300',
            'key ctrl+alt+k', 'key ctrl+alt+j', 'print-panels'])
        self.assertTrue(out[0].startswith('chord=') and 'fallback=demo.ping ms=' in out[0], out)
        self.assertTrue(800 <= int(out[0].split('ms=')[1]) <= 1000, out)
        self.assertEqual(out[1], 'chord=none')
        self.assertEqual([r[0] for r in self.runs()], ['0 run demo.ping 1 key 0'])
        self.assertIn('explorer=1 agents=0 term=0', out)

    def test_second_stroke_on_a_layout_that_is_not_latin(self):
        out = self.run_editor(exts=self.exts('ctrl+k t = rhun.toggle_sidebar\n'), drop_waits=True,
                              actions=['key ctrl+k', 'key-latin t Cyrillic_ie', 'print-panels', 'print-doc'])
        self.assertEqual(out[:2], ['explorer=1 agents=0 term=0', 'hello world'])

    def test_keyboard_shortcuts_list(self):
        out = self.run_editor(drop_waits=True, actions=[
            'cmd keyboard_shortcuts', 'type color theme', 'print-palette', 'key Return', 'print-palette'])
        self.assertIn(CTRL + 'K ' + CTRL + 'T  Select Color Theme', '\n'.join(out))
        self.assertIn('  GitHub Dark', out)


if __name__ == '__main__':
    unittest.main()
