#!/usr/bin/env python3
"""Extension lifecycle and cost (resources group): message and byte counters, slow and dropped
answers, CPU and memory of an extension's processes, idle = stop with what holds an extension
running, busy yes|no, startup pacing, print-startup, and the Extensions page's Resources block.
The fake extension is tests/ext/res.py."""
import os
from pathlib import Path
import re
import sys
import unittest

host = __import__('ext-host')
RES = Path(__file__).resolve().parent / 'ext' / 'res.py'


def fields(line):
    return dict(x.split('=', 1) for x in line.split() if '=' in x)


class Base(unittest.TestCase):
    """ext-host.py's setup and runner, without its tests"""
    setUp = host.Host.setUp
    tearDown = host.Host.tearDown
    run_editor = host.Host.run_editor


class Lifecycle(Base):
    def ext_root(self, manifest_extra='', name='res', features='', count=1, on='command'):
        root = self.work / 'exts'
        for i in range(count):
            n = name if count == 1 else f'{name}{i:03}'
            folder = root / 'rt' / n
            folder.mkdir(parents=True, exist_ok=True)
            (folder / 'extension.ini').write_text(
                f'name = {n}\nowner = rt\ntitle = Res {i}\nversion = 1\nprotocol = 1\n'
                f'runtime = python3\nrun = {RES.as_posix()}\non = {on}\n{manifest_extra}'
                '[commands]\nping = Ping\nburn = Burn\nalloc = Alloc\nchild = Child\nbusy = Busy\n'
                'unbusy = Unbusy\nbadbusy = Bad Busy\nstatus = Status\nunstatus = Unstatus\n'
                'quiet = Quiet\nrequest = Request\n'
                '[needs]\nrun = python3\n', encoding='utf-8')
        self.env['RES_FEATURES'] = features
        self.reslog = self.work / 'state/rhun/extensions/rt--res/res.log'
        if count == 1:
            self.env['RES_LOG'] = self.reslog.as_posix()
        return root

    def res_log(self):
        return self.reslog.read_text(errors='replace').splitlines() if self.reslog.exists() else []

    def cost(self, out):
        line = [x for x in out if x.startswith('cpu_ms=')]
        self.assertTrue(line, out)
        return fields(line[-1])

    def test_counters_move_with_messages(self):
        root = self.ext_root()
        out = self.run_editor(['cmd rt/res.ping', 'wait-ext res running', 'wait 300',
                               'print-ext-cost rt/res'], exts=root, files=())
        c = self.cost(out)
        self.assertEqual(c['state'], 'running')
        self.assertGreaterEqual(int(c['msgs_in']), 2)       # hello, toast
        self.assertGreaterEqual(int(c['msgs_out']), 3)      # ready, run, ok
        self.assertGreater(int(c['bytes_in']), 10)
        self.assertGreater(int(c['bytes_out']), 10)
        self.assertEqual(c['starts'], '1')
        self.assertLess(int(c['start_ms']), 5000)

    def test_cpu_and_memory_of_an_extension_and_its_child(self):
        root = self.ext_root()
        out = self.run_editor(['cmd rt/res.burn', 'wait-ext res running', 'wait 1500',
                               'cmd rt/res.alloc', 'wait 800', 'cmd rt/res.child', 'wait 800',
                               'print-ext-cost rt/res'], exts=root, files=())
        c = self.cost(out)
        self.assertGreaterEqual(int(c['cpu_ms']), 400, c)
        self.assertGreaterEqual(int(c['rss_kb']), 50000, c)
        self.assertGreaterEqual(int(c['procs']), 2, c)

    def test_idle_stop_and_restart_by_command(self):
        root = self.ext_root('idle = stop\nidle.after = 10\n')
        self.env['RHUN_IDLE_SCALE'] = '10'                  # 10 s become 1 s
        out = self.run_editor(['cmd rt/res.ping', 'wait-ext res running', 'wait 2500',
                               'print-extensions', 'cmd rt/res.ping', 'wait-ext res running',
                               'wait 200', 'print-ext-cost rt/res'], exts=root, files=())
        states = [x for x in out if x.startswith('rt/res ')]
        self.assertIn('state=idle reason=idle', states[0])
        c = self.cost(out)
        self.assertEqual(c['state'], 'running')
        self.assertEqual(c['starts'], '2')
        self.assertEqual(c['idle_after'], '10')
        self.assertEqual(sum(1 for x in self.res_log() if x.startswith('0 bye')), 2)   # idle, quit

    def test_idle_is_held_by_busy_and_status(self):
        root = self.ext_root('idle = stop\nidle.after = 10\n', features='idle')
        self.env['RHUN_IDLE_SCALE'] = '10'
        out = self.run_editor(['cmd rt/res.busy', 'wait-ext res running', 'wait 2500',
                               'print-extensions', 'cmd rt/res.unbusy', 'cmd rt/res.status',
                               'wait 2500', 'print-extensions', 'cmd rt/res.unstatus', 'wait 2500',
                               'print-extensions'], exts=root, files=())
        states = [x for x in out if x.startswith('rt/res ')]
        self.assertIn('state=running', states[0])
        self.assertIn('state=running', states[1])
        self.assertIn('state=idle reason=idle', states[2])
        log = self.res_log()
        self.assertIn('0 features idle', log)
        self.assertTrue(any(re.fullmatch(r'ok \d+', x) for x in log), log)

    def test_busy_needs_the_feature_and_valid_words(self):
        root = self.ext_root(features='')
        self.run_editor(['cmd rt/res.busy', 'wait-ext res running', 'wait 300'], exts=root, files=())
        self.assertTrue(any(re.fullmatch(r'error \d+ unknown no such request', x) for x in self.res_log()))
        root = self.ext_root(features='idle')
        self.reslog.unlink()
        self.run_editor(['cmd rt/res.badbusy', 'wait-ext res running', 'wait 300'], exts=root, files=())
        self.assertTrue(any(re.fullmatch(r'error \d+ syntax.*', x) for x in self.res_log()), self.res_log())

    def test_keep_is_the_default(self):
        root = self.ext_root()
        self.env['RHUN_IDLE_SCALE'] = '1000'
        out = self.run_editor(['cmd rt/res.ping', 'wait-ext res running', 'wait 1500',
                               'print-extensions'], exts=root, files=())
        self.assertIn('state=running', [x for x in out if x.startswith('rt/res ')][0])

    def test_startup_extensions_start_four_a_frame(self):
        root = self.ext_root(count=12, on='startup')
        out = self.run_editor(['wait 3000', 'print-extensions', 'print-startup'], exts=root, files=())
        rows = [x for x in out if x.startswith('rt/res')]
        self.assertEqual(len(rows), 12)
        self.assertTrue(all('state=running' in x for x in rows), rows)
        s = fields([x for x in out if x.startswith('first_frame_ms=')][0])
        self.assertGreater(int(s['first_frame_ms']), 0)
        self.assertGreater(int(s['ext_ready_ms']), 0)
        self.assertRegex(s['slowest'], r'^rt/res\d{3}:\d+$')

    def test_resources_block(self):
        root = self.ext_root('idle = stop\n')
        out = self.run_editor(['cmd rt/res.ping', 'wait-ext res running', 'wait 300',
                               'print-ext-resources rt/res'], exts=root, files=())
        text = '\n'.join(out)
        self.assertRegex(text, r'Running [\d.]+ (ms|s) · started in [\d,]+ ms · runs on this computer')
        self.assertRegex(text, r'CPU [\d.,]+ (ms|s) · [\d.]+% now · memory [\d.]+ (KB|MB) in \d+ process')
        self.assertRegex(text, r'Messages \d+ in · \d+ out · [\d.]+ (bytes|KB)')
        self.assertIn('Answers 0 slow · 0 dropped · 0 failed', text)
        self.assertIn('Stops after 5 min without work', text)

    def test_page_shows_resources(self):
        root = self.ext_root()
        shot = self.work / 'page.ppm'
        out = self.run_editor(['cmd rt/res.ping', 'wait-ext res running', 'ext-page rt/res',
                               'wait 2300', f'shot {shot.as_posix()}', 'print-ext-page'],
                              exts=root)
        self.assertTrue(shot.exists())
        if os.environ.get('RES_SHOTS'):
            import shutil
            shutil.copy(shot, os.environ['RES_SHOTS'] + '/resources-page.ppm')


if __name__ == '__main__':
    unittest.main()
