#!/usr/bin/env python3
"""How debug sessions end (src/app/dap.s): Stop's escalation (terminate, then disconnect with
terminateDebuggee, then the adapter's process group killed), a second Stop skipping ahead, attach
sessions left running, quitting rhun with a session, and rhun killed outright (the adapter sees its
input close and exits). Adapter processes are found by the pid the fake adapter logs, never by
name."""
import os
from pathlib import Path
import subprocess
import time
import unittest
import debughost


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    # a zombie is gone for this purpose
    try:
        out = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)], capture_output=True, text=True).stdout
        return bool(out.strip()) and not out.strip().startswith('Z')
    except OSError:
        return True


class Lifetime(debughost.DebugHost):
    def adapter_pid(self):
        for line in self.dap_log():
            if line.startswith('pid '):
                return int(line[4:])
        return None

    def stop_run(self, mode, presses=1, wait='wait-debug ended 10000', request=None):
        self.scenario()
        body = '[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n'
        if request:
            body += 'request = %s\n' % request
        self.launch_ini(body)
        t0 = time.time()
        out = self.run_editor([*self.start(), 'wait-debug paused', *(['debug-stop'] * presses), wait,
                               'print-debug'], mode=mode)
        return out, time.time() - t0

    def cmds(self):
        return [r.split(' ')[0] for r in self.requests()]

    def test_stop_terminates_first(self):
        out, took = self.stop_run(None)
        session = self.debug_lines(out)[-1]
        self.assertEqual(self.field(session, 'state'), 'ended', out)
        self.assertEqual(self.field(session, 'exit'), '143')
        cmds = self.cmds()
        self.assertLess(cmds.index('terminate'), cmds.index('disconnect'), cmds)
        self.assertIn('disconnect {"terminateDebuggee": true}', self.requests())
        self.assertFalse(alive(self.adapter_pid()))

    def test_terminate_ignored_then_disconnect(self):
        out, took = self.stop_run('ignore-terminate')
        session = self.debug_lines(out)[-1]
        self.assertEqual(self.field(session, 'state'), 'ended', out)
        self.assertGreater(took, 2.5)
        self.assertEqual(self.cmds()[-2:], ['terminate', 'disconnect'])

    def test_both_ignored_then_killed(self):
        out, took = self.stop_run('ignore-terminate,ignore-disconnect')
        session = self.debug_lines(out)[-1]
        self.assertEqual(self.field(session, 'state'), 'ended', out)
        self.assertEqual(self.field(session, 'reason'), 'stopped')
        self.assertGreater(took, 4.5)
        pid = self.adapter_pid()
        for _ in range(30):
            if not alive(pid):
                break
            time.sleep(0.1)
        self.assertFalse(alive(pid))

    def test_second_stop_skips_ahead(self):
        out, took = self.stop_run('ignore-terminate', presses=2)
        self.assertEqual(self.field(self.debug_lines(out)[-1], 'state'), 'ended', out)
        self.assertLess(took, 2.5)
        self.assertEqual(self.cmds()[-2:], ['terminate', 'disconnect'])

    def test_without_terminate_support(self):
        out, took = self.stop_run('no-terminate-cap')
        self.assertEqual(self.field(self.debug_lines(out)[-1], 'state'), 'ended', out)
        self.assertNotIn('terminate', self.cmds())
        self.assertIn('disconnect {"terminateDebuggee": true}', self.requests())

    def test_attach_leaves_the_program(self):
        out, took = self.stop_run(None, request='attach')
        self.assertEqual(self.field(self.debug_lines(out)[-1], 'state'), 'ended', out)
        self.assertNotIn('terminate', self.cmds())
        self.assertIn('disconnect {"terminateDebuggee": false}', self.requests())

    def test_quit_ends_sessions(self):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')
        self.run_editor([*self.start(), 'wait-debug paused'])
        self.assertEqual(self.cmds()[-1], 'disconnect')
        self.assertIn('EXIT', self.dap_log())
        self.assertFalse(alive(self.adapter_pid()))

    def test_quit_kills_an_adapter_that_does_not_answer(self):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')
        self.run_editor([*self.start(), 'wait-debug paused'], mode='ignore-disconnect')
        pid = self.adapter_pid()
        for _ in range(30):
            if not alive(pid):
                break
            time.sleep(0.1)
        self.assertFalse(alive(pid))

    def test_rhun_killed(self):
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', 'open ' + self.src.as_posix(), *self.start(),
                                     'wait-debug paused', 'wait 30000', 'quit']) + '\n')
        proc = subprocess.Popen([str(debughost.EXE), self.proj.as_posix(), '--headless', '1000x600',
                                 '--extensions', str(debughost.EXTS), '--script', script.as_posix()],
                                env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            pid = None
            for _ in range(100):
                if 'stopped' in ' '.join(self.dap_log()):
                    pid = self.adapter_pid()
                    break
                time.sleep(0.1)
            self.assertIsNotNone(pid, self.dap_log())
            proc.kill()
            proc.wait()
            for _ in range(50):
                if not alive(pid):
                    break
                time.sleep(0.1)
            self.assertFalse(alive(pid), 'the adapter outlived rhun by 5 s')
        finally:
            if proc.poll() is None:
                proc.kill()

    def orphan_dies(self, mode, actions):
        """the fake adapter's child ignores SIGTERM; after the session ends it must still go (SIGKILL to
        the group a second later) while rhun runs on"""
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', 'open ' + self.src.as_posix(), *self.start(), *actions,
                                     'wait-debug ended', 'wait 30000', 'quit']) + '\n')
        env = dict(self.env, FAKEDAP_MODE=mode)
        proc = subprocess.Popen([str(debughost.EXE), self.proj.as_posix(), '--headless', '1000x600',
                                 '--extensions', str(debughost.EXTS), '--script', script.as_posix()],
                                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            orphan = None
            for _ in range(100):
                for line in self.dap_log():
                    if line.startswith('orphan '):
                        orphan = int(line[7:])
                if orphan and ('EXIT' in self.dap_log() or 'CRASH' in self.dap_log()):
                    break
                time.sleep(0.1)
            self.assertIsNotNone(orphan, self.dap_log())
            for _ in range(40):
                if not alive(orphan):
                    break
                time.sleep(0.1)
            self.assertFalse(alive(orphan), 'the adapter\'s child outlived its session by 4 s')
            self.assertIsNone(proc.poll(), 'rhun still runs: its quit did not do it')
        finally:
            proc.kill()
            proc.wait()

    def test_group_killed_after_a_crash(self):
        # review: reaping the adapter cancelled the SIGKILL to its group
        self.orphan_dies('orphan,crash-at=3', ['wait-debug paused', 'debug-continue'])

    def test_group_killed_after_a_normal_end(self):
        self.orphan_dies('orphan', ['wait-debug paused', 'debug-stop'])

    def test_incomplete_frame_does_not_spin(self):
        # review: a partial message in the buffer made the loop poll without waiting
        self.launch_ini()
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', *self.start(), 'wait-console after the pause', 'quit']) + '\n')
        env = dict(self.env, FAKEDAP_MODE='partial-pause')
        proc = subprocess.Popen([str(debughost.EXE), self.proj.as_posix(), '--headless', '1000x600',
                                 '--extensions', str(debughost.EXTS), '--script', script.as_posix()],
                                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        _, status, usage = os.wait4(proc.pid, 0)
        proc.returncode = 0
        cpu = usage.ru_utime + usage.ru_stime
        self.assertLess(cpu, 1.5, 'rhun spent %.2f s of CPU waiting 2 s for the rest of a message' % cpu)


if __name__ == '__main__':
    unittest.main()
