#!/usr/bin/env python3
"""Programs in terminal tabs and the programs rhun runs as the user (tasks design 1.1, 1.3, 1.5-1.7,
4.2, 4.7; src/app/termview.s, uproc.s, runallow.s): term-run starts a program in a tab of its own,
which stays when it ends, with its exit code and a footer; Stop, closing the tab and quitting take its
whole process tree; programs get the user's login environment; the run-as-user approval asks once
per extension and project. Processes are found by a unique marker in their arguments, never by
name, and every run has its own HOME and config."""
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time
import unittest
import uuid

host = __import__('ext-host')
ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
WINDOWS = os.name == 'nt'
PY = shlex.quote(Path(sys.executable).as_posix())


def marked(seconds=300):
    """Shell words that run a process with the marker in its arguments for a while: the marker comes
    from RHUN_MARK (term-run --env), so the shell's own command line does not hold it."""
    return f"{PY} -c 'import time; time.sleep({seconds})' $RHUN_MARK"


def count(marker):
    """Live processes whose arguments hold the marker."""
    out = subprocess.run(['ps', '-A', '-o', 'command='], capture_output=True, text=True).stdout
    return sum(1 for line in out.splitlines() if marker in line)


def counter(marker):
    """A term-run whose tab prints how many processes hold the marker (the brackets keep the
    check itself out of the count)."""
    pattern = '[' + marker[0] + ']' + marker[1:]
    return f"term-run --title count --sh -- echo count=$(ps -A -o command= | grep -c '{pattern}')"


class Terminals(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-terminals-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        (self.proj / 'sub').mkdir(parents=True)
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(host.CONFIG, encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(),
                        XDG_DATA_HOME=(self.work / 'data').as_posix(),
                        TERM='xterm-256color')
        self.marker = 'rhun-test-' + uuid.uuid4().hex

    def tearDown(self):
        if not WINDOWS:
            out = subprocess.run(['ps', '-A', '-o', 'pid=,command='], capture_output=True, text=True).stdout
            for line in out.splitlines():
                if self.marker in line:
                    os.kill(int(line.split()[0]), 9)
        self.tmp.cleanup()

    def run_editor(self, actions, env=None, timeout=60):
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', '1000x700', '--scale', '1',
                                 '--script', script.as_posix()], env=env or self.env, capture_output=True,
                                timeout=timeout)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8', errors='replace').splitlines()

    def terminals(self, out):
        return [line for line in out if line.lstrip('*').startswith('term=') and ' kind=' in line]

    # --- a program's tab ---

    def test_exit_code_footer_and_the_tab_stays(self):
        out = self.run_editor(["term-run --title t --sh -- printf '\\033[32mok\\033[0m\\n'; exit 3",
                               'wait-terminal 1 ended', 'print-terminals', 'print-term', 'print-state'])
        self.assertEqual(out[0], 'term=1')
        self.assertIn('kind=terminal owner=- task=- state=exited code=3', out[1])
        self.assertIn(' runs=1 title=t', out[1])
        self.assertIn('ok', out)                          # what it printed, its escapes applied
        foot = [line for line in out if 'exited with code' in line]
        self.assertEqual(len(foot), 1, out)
        self.assertTrue(foot[0].startswith('── t exited with code 3 after '), foot)

    def test_typing_into_an_ended_program_does_nothing(self):
        out = self.run_editor(['term-run --title done -- true', 'wait-terminal 1 ended', 'focus in', 'type hello',
                               'key Return', 'wait 200', 'print-term'])
        self.assertNotIn('hello', '\n'.join(out))

    def test_a_program_that_cannot_start_says_why(self):
        out = self.run_editor(['term-run -- no-such-program-for-rhun', 'wait 300', 'print-terminals',
                               'print-term', 'term-run --cwd missing-folder -- true', 'wait 300',
                               'print-terminals', 'print-term'])
        terms = self.terminals(out)
        self.assertIn('state=failed code=- pid=0', terms[0])
        self.assertIn('Could not start "no-such-program-for-rhun": not found on PATH', out)
        self.assertIn('state=failed', terms[2])
        self.assertIn('the folder ' + (self.proj / 'missing-folder').as_posix() + ' does not exist',
                      ''.join(out))                # (wrapped at the panel's width)

    @unittest.skipIf(WINDOWS, 'POSIX shell')
    def test_environment_and_folder(self):
        out = self.run_editor(['term-run --cwd sub --env RHUN_T1=hello --unset HOME --sh -- '
                               'pwd; echo "[$RHUN_T1]"; echo "home=${HOME-none}"; echo "term=$TERM"',
                               'wait-terminal 1 ended', 'print-term'])
        self.assertIn((self.proj / 'sub').as_posix(), ''.join(out))     # a long path wraps
        self.assertIn('[hello]', out)
        self.assertIn('home=none', out)
        self.assertIn('term=xterm-256color', out)

    @unittest.skipIf(WINDOWS, 'POSIX shell')
    def test_restart_runs_again_in_the_same_tab(self):
        out = self.run_editor(['term-run --title r --sh -- echo run-$$; sleep 30', 'wait-term run-',
                               'print-terminals', 'term-restart 1', 'wait-terminal 1 running 2', 'wait-term run-',
                               'print-terminals', 'print-term'])
        terms = self.terminals(out)
        self.assertIn('term=1 kind=terminal', terms[0])
        self.assertIn('term=1 kind=terminal', terms[1])
        self.assertIn('state=running', terms[1])
        first = terms[0].split(' pid=')[1].split()[0]
        second = terms[1].split(' pid=')[1].split()[0]
        self.assertNotEqual(first, second)
        runs = [line for line in out if line.startswith('run-')]
        self.assertEqual(runs, ['run-' + second], out)   # cleared: only the new run's output

    # --- process trees ---

    @unittest.skipIf(WINDOWS, 'ps')
    def test_stop_ends_the_whole_tree(self):
        m = self.marker
        out = self.run_editor([f'term-run --env RHUN_MARK={m} --title tree --sh -- {marked()} & {marked()} & wait',
                               'wait 800',
                               counter(m), 'wait-terminal 2 ended', 'print-term', 'term-select 1', 'term-stop 1',
                               'wait-terminal 1 ended', 'print-terminals', counter(m), 'wait-terminal 3 ended',
                               'print-term'])
        self.assertIn('count=2', out)
        self.assertIn('state=stopped', self.terminals(out)[0])
        self.assertEqual([line for line in out if line.startswith('count=')], ['count=2', 'count=0'])

    @unittest.skipIf(WINDOWS, 'ps')
    def test_stop_kills_what_ignores_ctrl_c_after_two_seconds(self):
        m = self.marker
        out = self.run_editor([f"term-run --env RHUN_MARK={m} --title deaf --sh -- trap '' INT; {marked()}",
                               'wait 800',
                               'term-stop 1', 'wait 800', counter(m), 'wait-terminal 2 ended', 'print-term',
                               'wait-terminal 1 ended', counter(m), 'wait-terminal 3 ended', 'print-term',
                               'print-terminals'])
        self.assertEqual([line for line in out if line.startswith('count=')], ['count=1', 'count=0'])
        self.assertIn('term=1 kind=terminal owner=- task=- state=stopped', '\n'.join(out))

    @unittest.skipIf(WINDOWS, 'ps')
    def test_closing_the_tab_kills_the_tree(self):
        m = self.marker
        out = self.run_editor([f"term-run --env RHUN_MARK={m} --title deaf --sh -- trap '' INT TERM HUP; "
                               f"{marked()} & wait",
                               'wait 800', 'term-close 1', 'wait 2600', counter(m), 'wait-terminal 2 ended',
                               'print-term', 'print-terminals'])
        self.assertIn('count=0', out)
        self.assertNotIn('term=1 ', '\n'.join(self.terminals(out)))

    @unittest.skipIf(WINDOWS, 'ps')
    def test_a_leader_that_exits_takes_what_it_left(self):
        m = self.marker
        out = self.run_editor([f'term-run --env RHUN_MARK={m} --title leader --sh -- {marked()} & exit 4',
                               'wait-terminal 1 ended',
                               'print-terminals', counter(m), 'wait-terminal 2 ended', 'print-term'])
        self.assertIn('state=exited code=4', self.terminals(out)[0])
        self.assertIn('count=0', out)

    @unittest.skipIf(WINDOWS, 'ps')
    def test_quitting_leaves_no_program_behind(self):
        m = self.marker
        self.run_editor([f"term-run --env RHUN_MARK={m} --sh -- trap '' INT TERM HUP; {marked()} & wait",
                         'wait 800'])
        time.sleep(0.2)
        self.assertEqual(count(m), 0)

    # a leader that does not ignore SIGTERM, a child that ignores it and SIGHUP: the group outlives
    # its leader, and is killed all the same (reviews: the group stays until it is empty)
    def deaf_child(self, redirect=''):
        return f"( trap '' INT TERM HUP; exec {marked()}{redirect} )"

    @unittest.skipIf(WINDOWS, 'ps')
    def test_closing_the_tab_kills_what_outlives_the_leader(self):
        m = self.marker
        out = self.run_editor([f'term-run --env RHUN_MARK={m} --title deaf --sh -- {self.deaf_child()} & wait',
                               'wait 800', 'term-close 1', 'wait 500', 'print-uproc', 'wait 2200', counter(m),
                               'wait-terminal 2 ended', 'print-term', 'print-uproc'])
        self.assertIn('count=0', out)
        uprocs = [line for line in out if line.startswith('uproc=')]
        self.assertIn('+', uprocs[0])                   # the leader went, its group is still watched
        self.assertNotIn('+', uprocs[1])

    @unittest.skipIf(WINDOWS, 'ps')
    def test_quitting_kills_what_outlives_the_leader(self):
        m = self.marker
        self.run_editor([f'term-run --env RHUN_MARK={m} --sh -- {self.deaf_child()} & wait', 'wait 800'])
        time.sleep(0.2)
        self.assertEqual(count(m), 0)

    @unittest.skipIf(WINDOWS, 'ps')
    def test_what_let_go_of_the_terminal_is_killed_after_the_leader(self):
        # the child's output goes elsewhere, so the terminal ends with the leader: the tab ends at once
        m = self.marker
        child = self.deaf_child(' </dev/null >/dev/null 2>&1')
        out = self.run_editor([f'term-run --env RHUN_MARK={m} --title gone --sh -- {child} & sleep 0.5; exit 5',
                               'wait-terminal 1 ended', 'print-terminals', 'wait 2600', counter(m),
                               'wait-terminal 2 ended', 'print-term'])
        self.assertIn('state=exited code=5', self.terminals(out)[0])
        self.assertIn('count=0', out)

    @unittest.skipIf(WINDOWS, 'ps')
    def test_quitting_kills_what_let_go_of_the_terminal(self):
        m = self.marker
        child = self.deaf_child(' </dev/null >/dev/null 2>&1')
        self.run_editor([f'term-run --env RHUN_MARK={m} --sh -- {child} & sleep 0.5; exit 0',
                         'wait-terminal 1 ended'])
        time.sleep(0.2)
        self.assertEqual(count(m), 0)

    # --- the panel ---

    def test_a_program_shows_the_terminals_over_another_view(self):
        out = self.run_editor(['cmd toggle_problems', 'print-panel-tabs', 'term-run --title t -- true',
                               'wait-terminal 1 ended', 'print-panel-tabs', 'cmd toggle_problems',
                               'print-panel-tabs', 'term-select 1', 'print-panel-tabs'])
        heads = [line for line in out if line.startswith('terminals=')]
        self.assertEqual(len(heads), 4, out)
        self.assertNotIn(' chosen', heads[0])
        self.assertIn(' chosen', heads[1])
        self.assertNotIn(' chosen', heads[2])
        self.assertIn(' chosen', heads[3])

    # --- finding the program ---

    def test_a_program_is_found_on_its_own_path(self):
        # the tool is only on the PATH the program gets (Windows too: not rhun's own PATH)
        bin_dir = self.work / 'only-here'
        bin_dir.mkdir()
        if WINDOWS:
            import shutil
            shutil.copy(Path(os.environ.get('SystemRoot', 'C:/Windows')) / 'System32/hostname.exe',
                        bin_dir / 'rhun-path-tool.exe')
        else:
            tool = bin_dir / 'rhun-path-tool'
            tool.write_text('#!/bin/sh\necho found-on-path\n', encoding='utf-8')
            tool.chmod(0o755)
        path = str(bin_dir) if WINDOWS else bin_dir.as_posix()
        out = self.run_editor([f'term-run --env PATH={path} --title p -- rhun-path-tool',
                               'wait-terminal 1 ended', 'print-terminals', 'print-term'])
        self.assertIn('state=exited code=0', self.terminals(out)[0])
        if not WINDOWS:
            self.assertIn('found-on-path', out)

    # --- the login environment ---

    def fake_shell(self, body):
        shell = self.work / 'fake-shell'
        shell.write_text('#!/bin/sh\n' + body, encoding='utf-8')
        shell.chmod(0o755)
        env = dict(self.env, SHELL=shell.as_posix())
        env.pop('TERM', None)
        return env

    @unittest.skipIf(WINDOWS, 'login shells')
    def test_programs_get_the_login_shells_environment(self):
        # a login shell's profile exports a variable; it runs its last argument, as sh -c does
        env = self.fake_shell('export RHUN_LOGIN_MARK=from-login\nwhile [ $# -gt 1 ]; do shift; done\neval "$1"\n')
        out = self.run_editor(['term-run --sh -- echo "[$RHUN_LOGIN_MARK]"', 'wait-terminal 1 ended', 'print-term',
                               'print-uproc'], env=env)
        self.assertIn('[from-login]', out)
        self.assertTrue(any(line.startswith('uproc=') and line.endswith(' env=known') for line in out), out)

    @unittest.skipIf(WINDOWS, 'login shells')
    def test_a_login_shell_that_hangs_is_given_up_after_five_seconds(self):
        env = self.fake_shell(f'RHUN_MARK={self.marker}; exec {marked(60)}\n')
        start = time.monotonic()
        out = self.run_editor(['term-run --sh -- echo "[${RHUN_LOGIN_MARK-none}]"', 'wait-terminal 1 ended',
                               'print-term', 'print-uproc'], env=env)
        self.assertGreater(time.monotonic() - start, 4.5)
        self.assertIn('[none]', out)
        self.assertTrue(any('could not read your login shell' in line for line in out), out)
        self.assertTrue(any(line.endswith(' env=failed') for line in out), out)
        self.assertEqual(count(self.marker), 0)

    @unittest.skipIf(WINDOWS, 'login shells')
    def test_started_from_a_terminal_its_environment_is_kept(self):
        env = self.fake_shell('export RHUN_LOGIN_MARK=from-login\nwhile [ $# -gt 1 ]; do shift; done\neval "$1"\n')
        env['TERM'] = 'xterm'
        out = self.run_editor(['term-run --sh -- echo "[${RHUN_LOGIN_MARK-none}]"', 'wait-terminal 1 ended',
                               'print-term'], env=env)
        self.assertIn('[none]', out)

    def test_print_env_prints_between_markers(self):
        env = dict(self.env, RHUN_PRINT_ENV_T='a b=c')
        out = subprocess.run([str(EXE), '--print-env'], env=env, capture_output=True, timeout=10).stdout
        self.assertTrue(out.startswith(b'RHUN-ENV-BEGIN\0'), out[:40])
        self.assertTrue(out.endswith(b'RHUN-ENV-END\0'))
        self.assertIn(b'\0RHUN_PRINT_ENV_T=a b=c\0', out)


class Approval(unittest.TestCase):
    """One approval per extension and project (DECISIONS.md decision 1): run-approve asks as an
    extension's first program in a project would. The echo extension's host (ext-host.py)."""
    setUp = host.Host.setUp
    tearDown = host.Host.tearDown
    run_editor = host.Host.run_editor

    def ini(self):
        path = self.work / 'config/rhun/extensions.ini'
        return path.read_text(encoding='utf-8') if path.exists() else ''

    def test_allow_is_remembered_for_the_extension_and_project(self):
        out = self.run_editor(drop_waits=True, actions=[
            'run-approve rhun-tests/echo go build ./...', 'print-dialog', 'dialog yes', 'print-approve',
            'print-allowed', 'run-approve rhun-tests/echo go test ./...', 'print-dialog'])
        self.assertEqual(out[0], 'approve=asked')
        self.assertEqual(out[1], 'dialog=Let Echo run programs in proj?')
        self.assertEqual(out[2], 'text=go build ./...   in ~/proj')
        self.assertEqual(out[3], 'button=Allow')
        self.assertEqual(out[4], 'approve=yes')
        self.assertEqual(out[5], 'rhun-tests/echo ' + self.proj.as_posix())
        self.assertEqual(out[6:8], ['approve=allowed', 'dialog=none'])
        self.assertIn('[rhun-tests/echo]\nallow_run = ' + self.proj.as_posix() + '\n', self.ini())
        # a later session still has it
        out = self.run_editor(drop_waits=True, actions=['print-allowed', 'run-approve rhun-tests/echo make',
                                                        'print-ext-page rhun-tests/echo'])
        self.assertEqual(out[:2], ['rhun-tests/echo ' + self.proj.as_posix(), 'approve=allowed'])

    def test_cancel_remembers_nothing(self):
        out = self.run_editor(drop_waits=True, actions=[
            'run-approve rhun-tests/echo cargo build', 'dialog no', 'print-approve', 'print-allowed',
            'run-approve rhun-tests/echo cargo build', 'print-approve'])
        self.assertEqual(out, ['approve=asked', 'approve=no', 'approve=asked', 'approve=none'])
        self.assertNotIn('allow_run', self.ini())

    def test_one_question_at_a_time(self):
        out = self.run_editor(drop_waits=True, actions=[
            'run-approve rhun-tests/echo one', 'run-approve rhun-tests/echo two', 'print-dialog'])
        self.assertEqual(out[:3], ['approve=asked', 'approve=busy', 'dialog=Let Echo run programs in proj?'])
        self.assertEqual(out[3], 'text=one   in ~/proj')

    def test_forget(self):
        out = self.run_editor(drop_waits=True, actions=[
            'run-approve rhun-tests/echo make', 'dialog yes', 'ext-page rhun-tests/echo', 'print-ext-page',
            'ext-set rhun-tests/echo forget', 'print-allowed', 'run-approve rhun-tests/echo make'])
        self.assertIn('runs-in=~/proj', out)
        self.assertEqual(out[-1], 'approve=asked')
        self.assertFalse(any(line.startswith('rhun-tests/echo /') for line in out), out)
        self.assertNotIn('allow_run', self.ini())

    def test_a_long_command_loses_its_middle(self):
        long = 'run ' + 'x' * 200 + ' end'
        out = self.run_editor(drop_waits=True, actions=['run-approve rhun-tests/echo ' + long, 'print-dialog'])
        text = out[2]
        self.assertTrue(text.startswith('text=run xxx'), text)
        self.assertIn('…', text)
        self.assertTrue(text.endswith('x end   in ~/proj'), text)
        self.assertLess(len(text), 120)

    def test_v1_term_still_types_into_a_user_shell(self):
        # with a program's tab current, the suggestion goes to a shell (a new one here)
        out = self.run_editor(drop_waits=True, actions=[
            'term-run --title prog -- sleep 30', 'wait 300', 'cmd echo.term', 'wait-ext echo running',
            'wait 600', 'key Return', 'wait-term ext-ran-ok', 'print-terminals'])
        terms = [line for line in out if ' kind=' in line]
        self.assertEqual(len(terms), 2, out)
        self.assertTrue(terms[1].startswith('*term=2 kind=shell'), terms)


if __name__ == '__main__':
    unittest.main(verbosity=2)
