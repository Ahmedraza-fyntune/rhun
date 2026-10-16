#!/usr/bin/env python3
"""The extension host (docs/extensions/v1.md, gate 1), driven headlessly with the echo extension
(tests/ext/echo.py): discovery and commands before any process exists, the handshake with its
catch-up, versioned edits, the error replies, and the ways a program can misbehave without
taking the editor with it. Each run gets its own HOME and config; ECHO_MODE and ECHO_LOG reach
the extension through the environment (a --extensions session inherits rhun's)."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
EXTS = ROOT / 'tests/ext/exts'

CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
CMDS = 'echo.shout,echo.hi,echo.toast,echo.stale,echo.status,echo.open,echo.bad'


class Host(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-ext-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        (self.proj / 'a.txt').write_text('hello world\nsecond line\n', encoding='utf-8')
        (self.proj / 'b.go').write_text('package b\n', encoding='utf-8')
        (self.proj / 'u.txt').write_text('héllo\n', encoding='utf-8')   # é is two bytes
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.log = self.work / 'echo.log'
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(),
                        ECHO_LOG=self.log.as_posix())
        self.env.pop('ECHO_MODE', None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions, mode=None, exts=EXTS, files=('a.txt',)):
        env = dict(self.env)
        if mode:
            env['ECHO_MODE'] = mode
        opens = ['open ' + (self.proj / name).as_posix() for name in files]
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', *opens, *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', '1000x600', '--scale', '1',
                                 '--extensions', str(exts), '--script', script.as_posix()],
                                env=env, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8', errors='replace').splitlines()

    def echo_log(self):
        return self.log.read_text(encoding='utf-8', errors='replace').splitlines() if self.log.exists() else []

    def state_lines(self, out):
        return [line for line in out if line.startswith('rhun-tests/echo ')]

    # --- discovery and commands ---

    def test_manifest_commands_exist_before_any_process(self):
        out = self.run_editor(['print-extensions', 'print-palette'])
        self.assertEqual(out[0], f'rhun-tests/echo state=idle pid=0 cmds={CMDS}')
        self.assertFalse(self.log.exists(), 'no process was started')

    def test_a_folder_without_manifests_is_fine(self):
        empty = self.work / 'none'
        empty.mkdir()
        out = self.run_editor(['print-extensions', 'print-state'], exts=empty)
        self.assertTrue(out[0].startswith('tabs=1'), out)

    def test_bad_manifests_are_reported_not_fatal(self):
        bad = self.work / 'bad'
        (bad / 'o' / 'notitle').mkdir(parents=True)
        (bad / 'o' / 'notitle' / 'extension.ini').write_text('name = notitle\nprotocol = 1\nruntime = python3\nrun = x.py\n')
        (bad / 'o' / 'v2').mkdir(parents=True)
        (bad / 'o' / 'v2' / 'extension.ini').write_text('name = v2\ntitle = V2\nprotocol = 2\nruntime = python3\nrun = x.py\n')
        (bad / 'o' / 'noprog').mkdir(parents=True)
        (bad / 'o' / 'noprog' / 'extension.ini').write_text('name = noprog\ntitle = No\nprotocol = 1\nrun.linux-x86_64 = none\nrun.macos-arm64 = none\n')
        (bad / 'o' / 'nortl').mkdir(parents=True)
        (bad / 'o' / 'nortl' / 'extension.ini').write_text('name = nortl\ntitle = No\nprotocol = 1\nruntime = no-such-runtime-xyz\nrun = x.py\n')
        out = self.run_editor(['print-extensions'], exts=bad)
        states = sorted(line for line in out if line.startswith('o/'))
        self.assertIn('o/noprog state=failed reason=program file missing pid=0 cmds=', states)
        self.assertIn('o/nortl state=failed reason=runtime not found on PATH pid=0 cmds=', states)
        self.assertIn('o/notitle state=failed reason=extension.ini has no title pid=0 cmds=', states)
        self.assertIn('o/v2 state=failed reason=protocol version not supported (rhun speaks 1) pid=0 cmds=', states)

    # --- handshake and events ---

    def test_a_command_starts_the_program_and_catch_up_lists_the_open_tabs(self):
        out = self.run_editor(['cmd echo.toast', 'wait-ext echo running', 'wait 300', 'print-toast',
                               'print-extensions'], files=('a.txt', 'b.go'))
        self.assertEqual(out[0], 'ext=echo state=running')
        self.assertEqual(out[1], 'toast=hello there')
        log = self.echo_log()
        self.assertTrue(log[0].startswith('0 ready ' + self.proj.as_posix()), log)
        self.assertEqual(log[1], '0 opened 1 0 - ' + (self.proj / 'a.txt').as_posix())
        self.assertEqual(log[2], '0 opened 2 0 Go ' + (self.proj / 'b.go').as_posix())
        self.assertEqual(log[3], '0 active 2')
        self.assertEqual(log[4], '0 run echo.toast 2')
        self.assertEqual(log[5], 'ok 1')

    def test_typing_saving_and_closing_are_reported(self):
        out = self.run_editor(['cmd echo.toast', 'wait-ext echo running', 'wait 100', 'type xy', 'wait 100',
                               'key ctrl+s', 'wait 200', 'cmd close_tab', 'wait 200', 'print-extensions'])
        self.assertEqual(out[0], 'ext=echo state=running')
        log = self.echo_log()
        self.assertIn('0 changed 1 2', log)     # two keystrokes, one event per frame
        self.assertIn('0 cursor 1 1 3', log)
        saved = [line for line in log if line.startswith('0 saved 1 ')]
        self.assertEqual(len(saved), 1, log)
        self.assertIn('0 closed 1', log)
        self.assertIn('0 active 0', log)

    def test_hello_arrives_before_the_pending_command(self):
        # the command that started the program is delivered after ready and catch-up
        self.run_editor(['cmd echo.hi', 'wait-ext echo running', 'wait 300', 'print-doc'])
        log = self.echo_log()
        self.assertEqual(log[3], '0 run echo.hi 1')

    # --- requests ---

    def test_insert_text_replace_and_the_version_in_replies(self):
        out = self.run_editor(['cmd echo.hi', 'wait-ext echo running', 'wait 300', 'print-doc',
                               'cmd echo.shout', 'wait 400', 'print-doc', 'print-state'])
        self.assertEqual(out[1:3], ['hihello world', 'second line'])
        self.assertEqual(out[5:7], ['HIHELLO WORLD', 'SECOND LINE'])
        self.assertIn('dirty=1', out[-1])
        log = self.echo_log()
        self.assertIn('ok 1 1', log, 'insert replied with the new version')
        self.assertIn('0 changed 1 1', log)
        text_reply = [line for line in log if line.startswith('ok 2 ')]
        self.assertEqual(text_reply, ['ok 2 1 26'])

    def test_an_extension_edit_is_one_undo_step(self):
        out = self.run_editor(['cmd echo.shout', 'wait-ext echo running', 'wait 400', 'print-doc',
                               'cmd undo', 'print-doc'])
        self.assertEqual(out[1:3], ['HELLO WORLD', 'SECOND LINE'])
        self.assertEqual(out[5:7], ['hello world', 'second line'])

    def test_a_stale_version_is_refused(self):
        self.run_editor(['cmd echo.toast', 'wait-ext echo running', 'wait 100', 'type z', 'wait 100',
                         'cmd echo.stale', 'wait 300', 'print-doc'])
        log = self.echo_log()
        self.assertIn('error 2 stale 1', log)

    def test_a_bad_position_is_refused(self):
        self.run_editor(['cmd echo.bad', 'wait-ext echo running', 'wait 300'])
        log = self.echo_log()
        self.assertTrue(any(line.startswith('error 1 badpos') for line in log), log)

    def test_status_text_shows_in_print_extensions(self):
        out = self.run_editor(['cmd echo.status', 'wait-ext echo running', 'wait 300', 'print-extensions'])
        self.assertTrue(out[1].endswith(' status=echo ok'), out)

    def test_open_request_opens_a_tab_at_a_line(self):
        self.env['ECHO_OPEN'] = (self.proj / 'b.go').as_posix()
        out = self.run_editor(['cmd echo.open', 'wait-ext echo running', 'wait 400', 'print-tabs', 'print-state'])
        self.assertEqual(out[1], 'tabs=a.txt | *b.go')
        self.assertIn('line=2', out[2])      # b.go ends in a newline: line 2 is its empty last line
        log = self.echo_log()
        self.assertIn('ok 1 2', log)
        self.assertIn('0 opened 2 0 Go ' + (self.proj / 'b.go').as_posix(), log)

    def test_a_needs_refusal(self):
        ro = self.work / 'ro'
        dst = ro / 'rhun-tests' / 'echo'
        dst.mkdir(parents=True)
        manifest = (EXTS / 'rhun-tests/echo/extension.ini').read_text()
        manifest = manifest.replace('documents = write', 'documents = none')
        manifest = manifest.replace('run = ../../../echo.py', 'run = ' + (ROOT / 'tests/ext/echo.py').as_posix())
        (dst / 'extension.ini').write_text(manifest)
        self.run_editor(['cmd echo.hi', 'wait-ext echo running', 'wait 300', 'print-doc'], exts=ro)
        log = self.echo_log()
        self.assertIn('error 1 needs documents=write', log)

    # --- misbehaviour ---

    def test_no_hello_within_five_seconds(self):
        out = self.run_editor(['cmd echo.toast', 'wait 5500', 'print-extensions'], mode='nohello')
        self.assertIn('state=stopped reason=no hello within 5 s', out[0])

    def test_a_late_hello_is_too_late(self):
        out = self.run_editor(['cmd echo.toast', 'wait 5500', 'print-extensions'], mode='slowhello')
        self.assertIn('state=stopped reason=no hello within 5 s', out[0])

    def test_another_protocol_version(self):
        out = self.run_editor(['cmd echo.toast', 'wait 400', 'print-extensions'], mode='badhello')
        self.assertIn('state=stopped reason=protocol version not supported', out[0])

    def test_three_crashes_stop_it(self):
        out = self.run_editor(['cmd echo.toast', 'wait 400', 'print-extensions', 'cmd echo.toast', 'wait 400',
                               'print-extensions', 'cmd echo.toast', 'wait 400', 'print-extensions',
                               'cmd echo.toast', 'wait 400', 'print-extensions'], mode='crash')
        states = self.state_lines(out)
        self.assertIn('state=crashed reason=exited with status 3', states[0])
        self.assertIn('state=crashed reason=exited with status 3', states[1])
        self.assertIn('state=stopped reason=crashed three times within a minute', states[2])
        self.assertIn('state=stopped reason=crashed three times within a minute', states[3])

    def test_a_sleeping_program_costs_nothing(self):
        out = self.run_editor(['cmd echo.toast', 'wait-ext echo running', 'print-frames', 'type abc',
                               'wait 300', 'print-frames', 'print-doc', 'print-extensions'], mode='sleep')
        self.assertEqual(out[0], 'ext=echo state=running')
        self.assertEqual(out[3], 'abchello world')
        self.assertIn('state=running', out[-1])

    def test_a_flood_ends_the_program_and_frames_keep_coming(self):
        out = self.run_editor(['cmd echo.toast', 'wait-ext echo running', 'wait 1500', 'print-frames',
                               'print-extensions', 'type ok', 'print-doc'], mode='flood')
        self.assertEqual(out[0], 'ext=echo state=running')
        frames = int(out[1].split('=')[1])
        self.assertGreater(frames, 5, out)
        self.assertIn('state=stopped reason=flooding', out[2])
        self.assertEqual(out[3], 'okhello world')

    def test_garbage_without_a_newline(self):
        out = self.run_editor(['cmd echo.toast', 'wait 600', 'print-extensions'], mode='garbage')
        self.assertIn('state=stopped reason=a line over 64 KB without an end', out[0])

    def test_closing_its_output_ends_it(self):
        out = self.run_editor(['cmd echo.toast', 'wait 600', 'print-extensions'], mode='eof')
        self.assertIn('state=crashed reason=exited with status 137', out[0])

    def test_three_unparsable_lines(self):
        out = self.run_editor(['cmd echo.toast', 'wait 600', 'print-extensions'], mode='syntax')
        self.assertIn('state=stopped reason=three unparsable lines in a row', out[0])

    def test_fragmented_writes_are_reassembled(self):
        out = self.run_editor(['cmd echo.hi', 'wait-ext echo running', 'wait 800', 'print-doc'], mode='fragment')
        self.assertEqual(out[1], 'hihello world')

    def test_quitting_leaves_no_program_behind(self):
        out = self.run_editor(['cmd echo.toast', 'wait-ext echo running', 'print-extensions'])
        pid = int(out[1].split('pid=')[1].split()[0])
        time.sleep(0.5)
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        log = self.echo_log()
        self.assertEqual(log[-1], '0 bye')


if __name__ == '__main__':
    unittest.main()
