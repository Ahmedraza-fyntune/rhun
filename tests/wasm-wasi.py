#!/usr/bin/env python3
"""WASI preview 1 in `rhun --wasm-host` (src/wasm/wasi.s), call by call, with the probes of
tests/wasm/wasi (built modules kept beside their sources, so this runs anywhere): links inside an
allowed folder cannot lead out of it (reading, creating, removing, statting), a start section may
call WASI, an unknown import links only when an errno can answer it, poll_oneoff returns ready
subscriptions at once and clocks only when due (absolute realtime ones too), append mode set after
the open appends, linear memory stops at its cap. Symbolic links are made only where the system lets this user make them."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
PROBES = ROOT / 'tests/wasm/wasi'
# Windows under Wine: RHUN_WASM_HOST="wine64 Z:/path/rhun.com", RHUN_WASM_PATH_PREFIX=Z:
HOST = os.environ['RHUN_WASM_HOST'].split() if os.environ.get('RHUN_WASM_HOST') else [str(EXE)]
PREFIX = os.environ.get('RHUN_WASM_PATH_PREFIX', '')
WE_NOTCAPABLE = 76


class Wasi(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-wasi-')
        self.work = Path(self.tmp.name).resolve()

    def tearDown(self):
        self.tmp.cleanup()

    def host(self, module, args=(), dirs=(), stdin=b'', timeout=30):
        argv = HOST + ['--wasm-host']
        for kind, d in dirs:
            argv += [kind, PREFIX + d.as_posix()]
        argv += [PREFIX + (PROBES / module).as_posix(), *args]
        r = subprocess.run(argv, input=stdin, capture_output=True, timeout=timeout)
        return r.returncode, r.stdout.decode(errors='replace'), r.stderr.decode(errors='replace')

    def probe(self, *args, dirs, stdin=b''):
        code, out, err = self.host('probe.wasm', args, dirs, stdin)
        self.assertEqual(code, 0, err)
        return out.strip()

    def tree(self):
        """A (the allowed folder) with links inside it and out of it; B beside it"""
        a, b = self.work / 'A', self.work / 'B'
        (a / 'sub').mkdir(parents=True)
        b.mkdir()
        (a / 'sub/ok.txt').write_text('ok\n')
        (b / 'secret.txt').write_text('secret\n')
        try:
            os.symlink('sub', a / 'inlink')
            os.symlink('../B', a / 'outlink')
            os.symlink('../B/secret.txt', a / 'outfile')
            os.symlink('../B/new.txt', a / 'dangling')
        except (OSError, NotImplementedError) as e:
            self.skipTest('no symbolic links here: %s' % e)
        return a, b

    def test_links_cannot_lead_out_of_a_read_only_folder(self):
        a, b = self.tree()
        ro = [('--dir-ro', a)]
        self.assertEqual(self.probe('open', 'sub/ok.txt', dirs=ro), '0')
        self.assertEqual(self.probe('open', 'inlink/ok.txt', dirs=ro), '0')
        self.assertEqual(self.probe('open', 'outlink/secret.txt', dirs=ro), str(WE_NOTCAPABLE))
        self.assertEqual(self.probe('open', 'outfile', dirs=ro), str(WE_NOTCAPABLE))
        self.assertEqual(self.probe('open', 'outlink', dirs=ro), str(WE_NOTCAPABLE))
        self.assertEqual(self.probe('stat', 'outfile', dirs=ro), '%d -1' % WE_NOTCAPABLE)
        # not even the link itself is looked at when it leads out (Windows' stat sees through links)
        self.assertEqual(self.probe('lstat', 'outfile', dirs=ro), '%d -1' % WE_NOTCAPABLE)
        self.assertIn(self.probe('lstat', 'inlink', dirs=ro), ('0 7',) if not PREFIX else ('0 7', '0 3'))
        self.assertEqual(self.probe('open', '../B/secret.txt', dirs=ro), str(WE_NOTCAPABLE))

    def test_links_cannot_lead_out_of_a_writable_folder(self):
        a, b = self.tree()
        rw = [('--dir', a)]
        self.assertNotEqual(self.probe('create', 'dangling', dirs=rw), '0')
        self.assertFalse((b / 'new.txt').exists(), 'created through a dangling link')
        self.assertEqual(self.probe('create', 'outlink/made.txt', dirs=rw), str(WE_NOTCAPABLE))
        self.assertFalse((b / 'made.txt').exists())
        self.assertEqual(self.probe('mkdir', 'outlink/newdir', dirs=rw), str(WE_NOTCAPABLE))
        self.assertFalse((b / 'newdir').exists())
        self.assertEqual(self.probe('unlink', 'outlink/secret.txt', dirs=rw), str(WE_NOTCAPABLE))
        self.assertTrue((b / 'secret.txt').exists())
        # a link that leads out is not removed either (Windows may remove what it leads to)
        self.assertEqual(self.probe('unlink', 'outfile', dirs=rw), str(WE_NOTCAPABLE))
        self.assertTrue(os.path.lexists(a / 'outfile'))
        self.assertTrue((b / 'secret.txt').exists())
        if not PREFIX:                  # Wine sees a Unix link to nowhere as nothing
            self.assertEqual(self.probe('unlink', 'dangling', dirs=rw), '0')
            self.assertFalse(os.path.lexists(a / 'dangling'))
        self.assertEqual(self.probe('create', 'inlink/new.txt', dirs=rw), '0')
        self.assertTrue((a / 'sub/new.txt').exists())

    def test_a_read_only_folder_takes_no_writes(self):
        a = self.work / 'A'
        a.mkdir()
        (a / 'f.txt').write_text('abc')
        ro = [('--dir-ro', a)]
        self.assertEqual(self.probe('create', 'g.txt', dirs=ro), str(WE_NOTCAPABLE))
        self.assertEqual(self.probe('mkdir', 'd', dirs=ro), str(WE_NOTCAPABLE))
        self.assertEqual(self.probe('unlink', 'f.txt', dirs=ro), str(WE_NOTCAPABLE))
        self.assertTrue((a / 'f.txt').exists())

    def test_append_set_after_the_open(self):
        a = self.work / 'A'
        a.mkdir()
        (a / 'f.txt').write_text('abc')
        self.assertEqual(self.probe('append', 'f.txt', dirs=[('--dir', a)]), '0 1')
        self.assertEqual((a / 'f.txt').read_text(), 'abcX')

    def test_the_right_to_resize_alone(self):
        # asked for under a writable folder, it holds without the right to write
        a = self.work / 'A'
        a.mkdir()
        (a / 'f.txt').write_text('abcdef')
        self.assertEqual(self.probe('resize', 'f.txt', dirs=[('--dir', a)]), '0 0')
        self.assertEqual((a / 'f.txt').read_text(), 'a')
        # under a read-only folder the file opens, the resizing is refused
        (a / 'f.txt').write_text('abcdef')
        self.assertEqual(self.probe('resize', 'f.txt', dirs=[('--dir-ro', a)]), '0 %d' % WE_NOTCAPABLE)
        self.assertEqual((a / 'f.txt').read_text(), 'abcdef')

    def test_poll_realtime_deadline_long_past(self):
        code, out, err = self.host('probe.wasm', ['poll-past'], timeout=10)
        self.assertEqual((code, out.strip()), (0, '0 1 9'), err)

    def test_a_start_section_may_call_wasi(self):
        code, out, err = self.host('start.wasm')
        self.assertEqual((code, out), (0, 'start ok\n'), err)

    def test_memory_is_capped(self):
        code, out, err = self.host('grow.wasm')
        self.assertEqual(code, 3, err)
        code, out, err = self.host('bigmem.wasm')
        self.assertEqual(code, 1)
        self.assertIn('memory too large', err)

    def test_an_unknown_import_links_only_when_an_errno_answers_it(self):
        code, out, err = self.host('badimport.wasm')
        self.assertEqual(code, 1)
        self.assertIn('unknown import', err)
        code, out, err = self.host('goodimport.wasm')
        self.assertEqual(code, 52, err)                 # ENOSYS, through proc_exit

    @unittest.skipIf(PREFIX, 'under Wine a Unix pipe is no Windows pipe: the editor-driven tests cover it')
    def test_poll_returns_what_is_ready_without_waiting_for_input(self):
        # standard input stays open and empty: the write is ready all the same
        p = subprocess.Popen(HOST + ['--wasm-host', PREFIX + (PROBES / 'probe.wasm').as_posix(), 'poll-ready'],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        watchdog = threading.Timer(10, p.kill)
        watchdog.start()
        try:
            out = p.stdout.readline()
        finally:
            watchdog.cancel()
            p.stdin.close()
            p.wait(timeout=10)
            p.stdout.close()
        self.assertEqual(out.decode().strip(), '0 1 20', 'poll_oneoff waited on the standard input')

    def test_poll_clocks_come_when_due(self):
        self.assertEqual(self.probe('poll-clocks', dirs=()), '0 1 1 prompt')

    def test_poll_absolute_realtime_deadline(self):
        self.assertEqual(self.probe('poll-abs', dirs=()), '0 1 7 prompt')


if __name__ == '__main__':
    unittest.main()
