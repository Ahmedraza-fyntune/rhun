#!/usr/bin/env python3
"""Feature command-args (docs/extensions/v1.1.md): every invocation says where it came from and
carries its body ("0 run EXT.NAME DOC FROM LEN" + body); command references ("command NAME
ARGS_LEN" + ARGS) run their extension's command; an extension without the feature keeps v1's
"0 run NAME DOC"."""
import unittest

contribhost = __import__('contribhost')


class CommandArgs(contribhost.Contrib):
    def exts(self, hello='hello 1 command-args', **kw):
        root = self.work / 'exts'
        self.make_ext(root, hello=hello, commands=('ping = Ping', 'reg = Register'),
                      actions={'reg': ['register extra - Extra']}, **kw)
        return root

    def runs(self):
        """The run lines and their bodies, in order."""
        lines = self.contrib_log()
        out = []
        for i, line in enumerate(lines):
            if line.startswith('0 run '):
                body = lines[i + 1] if i + 1 < len(lines) and lines[i + 1].startswith('body=') else None
                out.append((line, body))
        return out

    def test_agreed_and_each_source(self):
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text() + '[keys]\nctrl+alt+7 = alice/demo.ping\n')
        out = self.run_editor(exts=self.exts(), drop_waits=True, actions=[
            'cmd demo.ping', 'wait-ext demo running', 'wait 200',
            'key ctrl+alt+7', 'wait 200',
            'cmd-args demo.ping hello world', 'wait 200',
            'cmd-ref demo ping some args', 'wait 200'])
        self.assertIn('0 features command-args', self.contrib_log())
        self.assertEqual(self.runs(), [
            ('0 run demo.ping 1 palette 0', 'body='),
            ('0 run demo.ping 1 key 0', 'body='),
            ('0 run demo.ping 1 ref 11', 'body=hello world'),
            ('0 run demo.ping 1 ref 9', 'body=some args')])

    def test_body_waits_for_a_lazy_start(self):
        self.run_editor(exts=self.exts(), drop_waits=True, actions=[
            'cmd-args demo.ping first', 'wait-ext demo running', 'wait 300'])
        self.assertEqual(self.runs(), [('0 run demo.ping 1 ref 5', 'body=first')])
        log = self.contrib_log()
        self.assertLess(log.index('0 ready ' + self.proj.as_posix()), log.index('0 run demo.ping 1 ref 5'))

    def test_a_later_command_replaces_the_waiting_one(self):
        self.run_editor(exts=self.exts(), drop_waits=True, actions=[
            'cmd-args demo.ping first', 'cmd-args demo.ping second', 'wait-ext demo running', 'wait 300'])
        self.assertEqual(self.runs(), [('0 run demo.ping 1 ref 6', 'body=second')])

    def test_v1_extension_gets_v1_lines(self):
        self.run_editor(exts=self.exts(hello='hello 1'), drop_waits=True, actions=[
            'cmd-args demo.ping hello', 'wait-ext demo running', 'wait 200',
            'cmd-ref demo ping more', 'wait 200'])
        self.assertEqual(self.runs(), [('0 run demo.ping 1', None), ('0 run demo.ping 1', None)])

    def test_reference_to_a_runtime_command(self):
        self.run_editor(exts=self.exts(), drop_waits=True, actions=[
            'cmd demo.reg', 'wait-ext demo running', 'wait 300',
            'cmd-ref demo extra x y', 'wait 200'])
        self.assertEqual(self.runs()[-1], ('0 run demo.extra 1 ref 3', 'body=x y'))

    def test_missing_command_toasts_and_sends_nothing(self):
        out = self.run_editor(exts=self.exts(), drop_waits=True, actions=[
            'cmd demo.ping', 'wait-ext demo running', 'wait 200',
            'cmd-ref demo gone x', 'print-toast', 'wait 200'])
        self.assertEqual(out, ['toast=This command is no longer available'])
        self.assertEqual(len(self.runs()), 1)

    def test_bad_references_are_refused(self):
        out = self.run_editor(exts=self.exts(), drop_waits=True, actions=[
            'cmd-ref demo Bad x', 'cmd-ref demo ' + 'a' * 41 + ' x', 'cmd-ref demo ping ' + 'x' * 8193])
        self.assertEqual(out, ['cmdref=bad'] * 3)
        self.assertEqual(self.runs(), [])

    def test_document_is_the_active_one(self):
        self.run_editor(exts=self.exts(), files=('a.txt', 'b.go'), drop_waits=True, actions=[
            'cmd demo.ping', 'wait-ext demo running', 'wait 200'])
        self.assertEqual(self.runs(), [('0 run demo.ping 2 palette 0', 'body=')])


if __name__ == '__main__':
    unittest.main()
