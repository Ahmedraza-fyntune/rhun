#!/usr/bin/env python3
"""Feature command-args, run-command and call (docs/extensions/v1.1.md): an extension runs rhun's
built-ins (some with ARGS) and other extensions' callable commands, whose answers rhun relays;
[command-options] callable, palette and when."""
import time
import unittest

contribhost = __import__('contribhost')
HELLO = 'hello 1 command-args'


class RunCommand(contribhost.Contrib):
    def setUp(self):
        super().setUp()
        (self.proj / 'c.txt').write_text('one\ntwo words here\nthree\n', encoding='utf-8')

    def exts(self, actions, call='reverse', peer_hello=HELLO, peer_options=None, needs='documents = write'):
        root = self.work / 'exts'
        self.make_ext(root, hello=HELLO, actions=actions, commands=[k + ' = ' + k for k in actions],
                      needs=needs)
        options = peer_options if peer_options is not None else 'echo.callable = yes\n'
        self.make_ext(root, owner='bob', name='peer', hello=peer_hello, call=call,
                      commands=('echo = Echo', 'other = Other'),
                      extra='[command-options]\n' + options)
        return root

    def answers(self, log):
        return [l for l in log if l.startswith(('ok ', 'error ', 'result=')) and l != 'result=']

    def test_builtins_with_and_without_args(self):
        out = self.run_editor(exts=self.exts({
            'go': [('run-command goto_line #', '2 5')],
            'all': ['run-command rhun.select_all 0'],
            'bad': [('run-command select_all #', 'x'), 'run-command nosuch 0', 'run-command toggle_terminal 0'],
        }), files=('c.txt',), drop_waits=True, actions=[
            'cmd demo.go', 'wait-ext demo running', 'wait 300', 'print-state',
            'cmd demo.all', 'wait 300', 'print-state', 'cmd demo.bad', 'wait 300'])
        self.assertIn('line=2 col=5', out[0])
        self.assertIn('sel=', out[1])
        self.assertNotIn('sel=0', out[1])
        self.assertEqual(self.answers(self.contrib_log()), [
            'ok 1 0', 'ok 2 0', 'error 3 syntax cannot parse the line',
            'error 4 refused not a command an extension may run', 'error 5 needs terminal=yes'])

    def test_needs_documents_write(self):
        self.run_editor(exts=self.exts({'tc': ['run-command toggle_comment 0']}, needs=''),
                        files=('c.txt',), drop_waits=True,
                        actions=['cmd demo.tc', 'wait-ext demo running', 'wait 300'])
        self.assertEqual(self.answers(self.contrib_log()), ['error 1 needs documents=write'])

    def test_find_and_palette_get_their_text(self):
        out = self.run_editor(exts=self.exts({
            'find': [('run-command find #', 'words')],
            'open': [('run-command quick_open #', 'c.t')],
            'again': [('run-command command_palette #', 'x')],
        }), files=('c.txt',), drop_waits=True, actions=[
            'cmd demo.find', 'wait-ext demo running', 'wait 300', 'when findFocus && findVisible',
            'key Escape', 'cmd demo.open', 'wait 300', 'print-palette', 'cmd demo.again', 'wait 300'])
        self.assertEqual(out[0], 'when=1')
        self.assertTrue(any('c.t' in line for line in out[1:]), out)
        self.assertEqual(self.answers(self.contrib_log()), ['ok 1 0', 'ok 2 0', 'error 3 busy a prompt is open'])

    def test_callable_command_answers_through_rhun(self):
        self.run_editor(exts=self.exts({
            'ask': [('run-command peer.echo #', 'hello'), ('run-command bob/peer.echo #', 'abc')],
            'refused': ['run-command peer.other 0', 'run-command demo.ask 0', 'run-command peer.none 0'],
        }), drop_waits=True, actions=[
            'cmd demo.ask', 'wait-ext demo running', 'wait-ext peer running', 'wait 500',
            'cmd demo.refused', 'wait 300'])
        self.assertEqual(self.answers(self.contrib_log()), [
            'ok 1 5', 'result=olleh', 'ok 2 3', 'result=cba', 'error 3 refused not callable',
            'error 4 refused its own command', 'error 5 refused no such command'])
        peer = self.contrib_log('bob', 'peer')
        self.assertIn('1 call peer.echo 1 alice/demo 5', peer)
        self.assertIn('body=hello', peer)

    def test_errors_and_big_results(self):
        self.run_editor(exts=self.exts({'ask': ['run-command peer.echo 0']}, call='error'),
                        drop_waits=True, actions=['cmd demo.ask', 'wait-ext demo running', 'wait 800'])
        self.assertEqual(self.answers(self.contrib_log()), ['error 1 refused nope'])

    def test_result_over_one_mib(self):
        self.run_editor(exts=self.exts({'ask': ['run-command peer.echo 0']}, call='big'),
                        drop_waits=True, actions=['cmd demo.ask', 'wait-ext demo running', 'wait 1500'])
        self.assertEqual(self.answers(self.contrib_log()), ['error 1 toobig the result exceeds 1 MiB'])

    def test_owner_without_the_feature_is_not_callable(self):
        self.run_editor(exts=self.exts({'ask': ['run-command peer.echo 0']}, peer_hello='hello 1'),
                        drop_waits=True, actions=['cmd demo.ask', 'wait-ext demo running', 'wait 800'])
        self.assertEqual(self.answers(self.contrib_log()), ['error 1 refused not callable'])

    def test_silent_owner_times_out_and_is_cancelled(self):
        start = time.time()
        self.run_editor(exts=self.exts({'ask': ['run-command peer.echo 0'] * 9}, call='silent'),
                        drop_waits=True, actions=['cmd demo.ask', 'wait-ext demo running', 'wait 800',
                                                  *(['wait 1000'] * 10)])
        answers = self.answers(self.contrib_log())
        self.assertEqual(answers[0], 'error 9 busy 8 calls outstanding')
        self.assertEqual(sorted(answers[1:]), sorted('error %d cancelled timeout' % i for i in range(1, 9)))
        peer = self.contrib_log('bob', 'peer')
        self.assertEqual(len([l for l in peer if l.startswith('0 cancel ')]), 8)
        self.assertGreater(time.time() - start, 10)

    def test_stopped_owner_cancels(self):
        self.run_editor(exts=self.exts({'ask': ['run-command peer.echo 0']}, call='silent'),
                        drop_waits=True, actions=['cmd demo.ask', 'wait-ext peer running', 'wait 300',
                                                  'ext-set peer stop', 'wait-ext peer stopped', 'wait 300'])
        self.assertEqual(self.answers(self.contrib_log()), ['error 1 cancelled'])

    def test_unagreed_run_command_is_unknown(self):
        root = self.work / 'exts'
        self.make_ext(root, hello='hello 1', actions={'x': ['run-command select_all 0']}, commands=('x = X',))
        self.run_editor(exts=root, drop_waits=True, actions=['cmd demo.x', 'wait-ext demo running', 'wait 300'])
        self.assertEqual(self.answers(self.contrib_log()), ['error 1 unknown no such request'])

    def test_command_options_palette_and_when(self):
        options = 'echo.callable = yes\nother.palette = no\necho.when = resourceExt == .go\n'
        out = self.run_editor(exts=self.exts({'x': []}, peer_options=options), files=('a.txt',),
                              drop_waits=True, actions=['cmd command_palette', 'type Peer', 'print-palette',
                                                        'key Escape', 'open ' + (self.proj / 'b.go').as_posix(),
                                                        'cmd command_palette', 'type Peer', 'print-palette'])
        first = '\n'.join(out[:len(out) // 2])
        self.assertNotIn('Other (Demo)', '\n'.join(out))
        self.assertNotIn('Echo (Demo)', first)
        self.assertIn('Echo (Demo)', '\n'.join(out[len(out) // 2:]))


if __name__ == '__main__':
    unittest.main()
