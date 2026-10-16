#!/usr/bin/env python3
"""The extension host (docs/extensions/v1.md, gate 1), driven headlessly with the echo extension
(tests/ext/echo.py): discovery and commands before any process exists, the handshake with its
catch-up, versioned edits, the error replies, and the ways a program can misbehave without
taking the editor with it. Each run gets its own HOME and config; ECHO_MODE and ECHO_LOG reach
the extension through the environment (a --extensions session inherits rhun's)."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
EXTS = ROOT / 'tests/ext/exts'

CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
CMDS = 'echo.shout,echo.hi,echo.toast,echo.stale,echo.status,echo.open,echo.bad,echo.mb,echo.sel,echo.relopen'


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
        lines = self.log.read_text(encoding='utf-8', errors='replace').splitlines() if self.log.exists() else []
        return [line for line in lines if not line.startswith('pid ')]

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
        (bad / 'o' / 'notitle' / 'extension.ini').write_text('name = notitle\nowner = o\nversion = 1\nprotocol = 1\nruntime = python3\nrun = x.py\n')
        (bad / 'o' / 'v2').mkdir(parents=True)
        (bad / 'o' / 'v2' / 'extension.ini').write_text('name = v2\nowner = o\nversion = 1\ntitle = V2\nprotocol = 2\nruntime = python3\nrun = x.py\n')
        (bad / 'o' / 'noprog').mkdir(parents=True)
        (bad / 'o' / 'noprog' / 'extension.ini').write_text('name = noprog\nowner = o\nversion = 1\ntitle = No\nprotocol = 1\nrun.linux-x86_64 = none\nrun.macos-arm64 = none\n')
        (bad / 'o' / 'nortl').mkdir(parents=True)
        (bad / 'o' / 'nortl' / 'extension.ini').write_text('name = nortl\nowner = o\nversion = 1\ntitle = No\nprotocol = 1\nruntime = no-such-runtime-xyz\nrun = x.py\n')
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
        self.assertEqual(log[4], '0 cursor 2 1 1')
        self.assertEqual(log[5], '0 run echo.toast 2')
        self.assertEqual(log[6], 'ok 1')

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
        self.assertEqual(log[3], '0 cursor 1 1 1')
        self.assertEqual(log[4], '0 run echo.hi 1')

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

    def test_a_program_that_never_reads_is_stopped(self):
        out = self.run_editor(['cmd echo.toast', 'wait-ext echo running', 'wait 11000', 'print-extensions',
                               'type ok', 'print-doc'], mode='floodnoread')
        # whichever rule trips first: the message cap, or the queue it never drains
        self.assertTrue('reason=not reading for 10 s' in out[1] or 'reason=flooding' in out[1], out[1])
        self.assertIn('state=stopped', out[1])
        self.assertEqual(out[2], 'okhello world')

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

    def test_a_manifest_key_runs_the_command(self):
        out = self.run_editor(['key ctrl+alt+shift+u', 'wait-ext echo running', 'wait 400', 'print-doc'])
        self.assertEqual(out[1:3], ['HELLO WORLD', 'SECOND LINE'])

    def test_catch_up_includes_the_cursor_of_the_active_tab(self):
        self.run_editor(['key ctrl+g', 'type 2', 'key Return', 'cmd echo.toast', 'wait-ext echo running', 'wait 300'])
        log = self.echo_log()
        self.assertEqual(log[2:4], ['0 active 1', '0 cursor 1 2 1'])

    def test_a_change_then_a_save_within_one_frame_report_both(self):
        self.run_editor(['cmd echo.toast', 'wait-ext echo running', 'wait 100', 'type q', 'key ctrl+s', 'wait 300'])
        log = self.echo_log()
        changed = log.index('0 changed 1 1')
        self.assertEqual(log[changed + 1:changed + 3], ['0 saved 1 1', '0 cursor 1 1 2'])

    def test_a_collapsing_selection_is_reported_as_empty(self):
        sel = self.work / 'sel'
        dst = sel / 'rhun-tests' / 'echo'
        dst.mkdir(parents=True)
        manifest = (EXTS / 'rhun-tests/echo/extension.ini').read_text()
        manifest = manifest.replace('cursor = *', 'cursor = no\nselection = *')
        manifest = manifest.replace('run = ../../../echo.py', 'run = ' + (ROOT / 'tests/ext/echo.py').as_posix())
        (dst / 'extension.ini').write_text(manifest)
        self.run_editor(['cmd echo.toast', 'wait-ext echo running', 'wait 100', 'key shift+Right', 'wait 100',
                         'key Left', 'wait 300'], exts=sel)
        log = self.echo_log()
        self.assertIn('0 selection 1 1 1 1 2', log)
        self.assertIn('0 selection 1 1 1 1 1', log)

    def test_a_late_hello_is_caught_without_other_activity(self):
        # nothing else wakes the loop: the deadline itself must
        out = self.run_editor(['cmd echo.toast', 'wait 8000', 'print-extensions'], mode='slowhello')
        self.assertIn('state=stopped reason=no hello within 5 s', out[0])

    def test_three_requests_with_bad_arguments(self):
        out = self.run_editor(['cmd echo.toast', 'wait 600', 'print-extensions'], mode='badargs')
        self.assertIn('state=stopped reason=three unparsable lines in a row', out[0])

    def test_the_error_log_is_kept_under_its_cap(self):
        out = self.run_editor(['cmd echo.toast', 'wait-ext echo running', 'wait 2500', 'print-extensions'], mode='noisy')
        self.assertIn('state=running', out[1])
        logs = list((self.work / 'state/rhun/extensions').glob('*.log'))
        self.assertEqual(len(logs), 1, logs)
        self.assertLess(logs[0].stat().st_size, 1024 * 1024 + 65536)

    def test_a_stopped_extension_is_not_restarted_by_its_command(self):
        out = self.run_editor(['cmd echo.toast', 'wait 400', 'cmd echo.toast', 'wait 400', 'cmd echo.toast', 'wait 400',
                               'print-extensions', 'cmd echo.toast', 'wait 400', 'print-extensions', 'print-toast'],
                              mode='crash')
        states = self.state_lines(out)
        self.assertIn('state=stopped reason=crashed three times within a minute', states[0])
        self.assertIn('pid=0', states[1])
        self.assertEqual(out[-1], 'toast=crashed three times within a minute')

    def test_a_position_inside_a_character_is_refused(self):
        self.run_editor(['cmd echo.mb', 'wait-ext echo running', 'wait 300'], files=('u.txt',))
        log = self.echo_log()
        self.assertTrue(any(line.startswith('error 1 badpos') for line in log), log)

    def test_select_then_range(self):
        out = self.run_editor(['cmd echo.sel', 'wait-ext echo running', 'wait 400', 'print-state'])
        self.assertIn('line=1 col=6 sel=5', out[1])
        log = self.echo_log()
        self.assertIn('ok 1', log)
        self.assertIn('ok 2 0 5', log)
        self.assertIn('hello', log)

    def test_redo_after_an_extension_edit(self):
        out = self.run_editor(['cmd echo.shout', 'wait-ext echo running', 'wait 400', 'cmd undo', 'cmd redo', 'print-doc'])
        self.assertEqual(out[1:3], ['HELLO WORLD', 'SECOND LINE'])

    def test_a_relative_open_is_inside_the_project(self):
        out = self.run_editor(['cmd echo.relopen', 'wait-ext echo running', 'wait 400', 'print-tabs'])
        self.assertEqual(out[1], 'tabs=a.txt | *b.go')

    def manifest_variant(self, folder, **changes):
        dst = self.work / folder / 'rhun-tests' / 'echo'
        dst.mkdir(parents=True)
        manifest = (EXTS / 'rhun-tests/echo/extension.ini').read_text()
        manifest = manifest.replace('run = ../../../echo.py', 'run = ' + (ROOT / 'tests/ext/echo.py').as_posix())
        for old, new in changes.items():
            manifest = manifest.replace(old, new)
        (dst / 'extension.ini').write_text(manifest)
        return self.work / folder

    def test_lang_activation_starts_on_a_matching_document(self):
        exts = self.manifest_variant('lang', **{'on = command': 'on = lang:Go'})
        out = self.run_editor(['wait 300', 'print-extensions'], exts=exts)
        self.assertIn('state=idle', out[0])
        out = self.run_editor(['wait-ext echo running', 'print-extensions'], exts=exts, files=('a.txt', 'b.go'))
        self.assertEqual(out[0], 'ext=echo state=running')

    def test_startup_activation(self):
        exts = self.manifest_variant('startup', **{'on = command': 'on = startup'})
        out = self.run_editor(['wait-ext echo running', 'print-extensions'], exts=exts)
        self.assertEqual(out[0], 'ext=echo state=running')
        log = self.echo_log()
        self.assertTrue(log[0].startswith('0 ready '), log)

    def test_a_program_that_cannot_run_is_a_failed_start(self):
        exts = self.work / 'noexec'
        d = exts / 'rhun-tests' / 'x'
        d.mkdir(parents=True)
        (d / 'prog').write_text('not a program\n')
        (d / 'extension.ini').write_text('name = x\nowner = rhun-tests\ntitle = X\nversion = 1\nprotocol = 1\n'
                                         'run.linux-x86_64 = prog\nrun.macos-arm64 = prog\n[commands]\ngo = Go\n')
        out = self.run_editor(['print-extensions'], exts=exts)
        self.assertIn('state=failed reason=program is not executable', out[0])
        os.chmod(d / 'prog', 0o755)
        out = self.run_editor(['cmd x.go', 'wait 500', 'print-extensions'], exts=exts)
        self.assertIn('state=failed reason=failed to start: the program could not be executed', out[0])

    def test_a_manifest_whose_name_does_not_match_its_folder(self):
        exts = self.manifest_variant('badname', **{'name = echo': 'name = other'})
        out = self.run_editor(['print-extensions'], exts=exts)
        self.assertIn('state=failed reason=extension.ini name does not match the folder', out[0])

    @unittest.skipUnless(sys.platform.startswith('linux'), 'the parent-death signal is Linux')
    def test_killing_rhun_kills_the_program(self):
        script = self.work / 'k.rsc'
        script.write_text('cmd echo.toast\nwait-ext echo running\nwait 20000\nquit\n')
        proc = subprocess.Popen([str(EXE), self.proj.as_posix(), '--headless', '1000x600', '--extensions', str(EXTS),
                                 '--script', script.as_posix()], env=self.env, stdout=subprocess.PIPE)
        for _ in range(100):
            time.sleep(0.1)
            lines = self.log.read_text().splitlines() if self.log.exists() else []
            if any(line.startswith('0 ready') for line in lines):
                break
        pid = int([line for line in lines if line.startswith('pid ')][0].split()[1])
        proc.kill()
        proc.wait()
        time.sleep(0.5)
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_a_command_right_after_an_open_sees_the_document_first(self):
        # the run event for a document rhun has not yet reported waits behind opened and active
        self.run_editor(['cmd echo.toast', 'wait-ext echo running', 'wait 100',
                         'open ' + (self.proj / 'b.go').as_posix(), 'cmd echo.toast', 'wait 300'])
        log = self.echo_log()
        opened = log.index('0 opened 2 0 Go ' + (self.proj / 'b.go').as_posix())
        active = log.index('0 active 2')
        run = [i for i, line in enumerate(log) if line == '0 run echo.toast 2'][0]
        self.assertLess(opened, run)
        self.assertLess(active, run)

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
