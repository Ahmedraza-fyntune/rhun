#!/usr/bin/env python3
"""launch.ini's questions (docs/guide.md "Debugging"): ${ask:PROMPT} asks for text, ${pick:PROMPT|A|B}
offers a list, ${process} lists the running processes; the launch starts once every question of
the configuration is answered, and Escape abandons it."""
import os
import unittest
import debughost


class Questions(debughost.DebugHost):
    def ini(self, extra):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\n' + extra)

    def test_ask(self):
        self.ini('port = ${ask:Port number}\n')
        out = self.run_editor(['debug-start Run', 'print-palette', 'type 8080', 'key Return', 'dialog yes',
                               'wait-debug ended'])
        self.assertTrue(any(l.startswith('prompt=Port number') for l in out), out)
        self.assertEqual(self.args_sent()['port'], '8080')

    def test_pick(self):
        self.ini('mode = ${pick:Mode|debug|test|exec}\n')
        out = self.run_editor(['debug-start Run', 'print-palette', 'type tes', 'key Return', 'dialog yes',
                               'wait-debug ended'])
        self.assertTrue(any(l.startswith('choose=Mode') for l in out), out)
        self.assertEqual([l for l in out if l.endswith(('debug', 'test', 'exec'))], ['> debug', '  test', '  exec'])
        self.assertEqual(self.args_sent()['mode'], 'test')

    def test_two_questions_in_turn(self):
        self.ini('mode = ${pick:Mode|debug|test}\nhost = ${ask:Host}\nlabel = ${ask:Host}-x\n')
        out = self.run_editor(['debug-start Run', 'key Return', 'print-palette', 'type box', 'key Return',
                               'dialog yes', 'wait-debug ended'])
        args = self.args_sent()
        self.assertEqual((args['mode'], args['host'], args['label']), ('debug', 'box', 'box-x'))   # asked once

    def test_process(self):
        self.ini('processId = ${process}\n')
        out = self.run_editor(['debug-start Run', 'wait 1500', 'print-palette', 'type %d' % os.getpid(),
                               'key Return', 'dialog yes', 'wait-debug ended'])
        self.assertTrue(any(l.startswith('choose=Attach to which process?') for l in out), out)
        self.assertEqual(self.args_sent()['processId'], str(os.getpid()))

    def test_escape_abandons_and_asks_again(self):
        self.ini('port = ${ask:Port number}\n')
        out = self.run_editor(['debug-start Run', 'key Escape', 'wait 200', 'print-debug', 'echo --',
                               'debug-start Run', 'print-palette', 'type 1', 'key Return', 'dialog yes',
                               'wait-debug ended'])
        self.assertEqual(self.debug_lines(out[:out.index('--')]), [], out)     # nothing started
        self.assertEqual(sum(1 for l in out if l.startswith('prompt=Port number')), 1, out)
        self.assertEqual(self.args_sent()['port'], '1')


if __name__ == '__main__':
    unittest.main()
