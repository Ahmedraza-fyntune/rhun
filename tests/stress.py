#!/usr/bin/env python3
"""Bounded large-file/tree and repeated-interaction checks, with timings.

Timings are measurements, not universal speed limits. All writes use a temporary
project. Set RHUN_TEST_ARTIFACTS to retain the JSON report for release comparison.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
MEASUREMENTS = []


class Stress(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-stress-')
        self.work = Path(self.tmp.name).resolve()
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                          '[editor]\ncursor_blink = false\n'
                          '[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix())

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, name, lines, file=None):
        script = self.work / 'stress.rsc'
        script.write_text('\n'.join([*lines, 'quit']) + '\n', encoding='utf-8')
        args = [str(EXE), self.work.as_posix()]
        if file:
            args.append(file.as_posix())
        before = time.monotonic()
        result = subprocess.run([*args, '--headless', '1000x700', '--script', script.as_posix()],
                                env=self.env, capture_output=True, timeout=40)
        elapsed = time.monotonic() - before
        MEASUREMENTS.append({'workload': name, 'seconds': round(elapsed, 4)})
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        self.assertNotIn(b'unknown\n', result.stdout)
        return result.stdout.decode('utf-8')

    def test_replace_undo_redo_large_unicode_document(self):
        file = self.work / 'large.txt'
        original = ('needle café αβ\n' * 20000).encode('utf-8')
        file.write_bytes(original)
        output = self.run_editor('replace-20000-lines', ['cmd replace', 'type needle', 'key Tab',
            'type replacement', 'key ctrl+Return', 'key Escape', 'cmd save', 'print-state'], file)
        replaced = original.replace(b'needle', b'replacement')
        self.assertEqual(file.read_bytes(), replaced)
        self.assertIn('dirty=0 ', output)
        # Undo and redo must each restore the complete transaction, before saving.
        file.write_bytes(original)
        self.run_editor('replace-undo-20000-lines', ['cmd replace', 'type needle', 'key Tab',
            'type replacement', 'key ctrl+Return', 'key Escape', 'cmd undo', 'cmd save'], file)
        self.assertEqual(file.read_bytes(), original)
        self.run_editor('replace-redo-20000-lines', ['cmd replace', 'type needle', 'key Tab',
            'type replacement', 'key ctrl+Return', 'key Escape', 'cmd undo', 'cmd redo', 'cmd save'], file)
        self.assertEqual(file.read_bytes(), replaced)

    def test_long_line_wrapping_keeps_bytes_and_cursor(self):
        file = self.work / 'long.txt'
        original = ('word café ' * 10000 + '\nend\n').encode('utf-8')
        file.write_bytes(original)
        output = self.run_editor('wrap-100000-characters', ['cmd toggle_word_wrap',
            'key ctrl+End', 'print-state', 'resize 640 480', 'cmd toggle_word_wrap',
            'cmd save', 'print-state'], file)
        self.assertEqual(file.read_bytes(), original)
        self.assertIn('line=3 col=1 ', output)

    def test_large_file_tree_search_and_exclusions(self):
        tree = self.work / 'tree'
        tree.mkdir()
        for index in range(3000):
            (tree / f'file-{index:04d}.txt').write_text('text\n', encoding='utf-8')
        excluded = self.work / 'node_modules'
        excluded.mkdir()
        (excluded / 'excluded-target.txt').write_text('private\n', encoding='utf-8')
        output = self.run_editor('quick-open-3000-files', ['cmd quick_open', 'type file-2999',
            'print-palette', 'key Return', 'print-state', 'cmd quick_open',
            'type excluded-target', 'print-palette', 'key Escape'])
        self.assertIn('active=file-2999.txt ', output)
        self.assertNotIn('> node_modules', output)
        self.assertNotIn('  node_modules', output)

    def test_repeated_palette_and_tab_lifecycle(self):
        file = self.work / 'stable.txt'
        file.write_text('stable\n', encoding='utf-8')
        actions = []
        for _ in range(100):
            actions += ['cmd quick_open', 'type stable', 'key Escape', 'cmd command_palette',
                        'type undo', 'key Escape', 'cmd settings', 'cmd close_tab']
        # Let config-watch notifications and hover timers settle before measuring idle.
        actions += ['print-state', 'print-doc', 'move 500 500', 'wait 1500',
                    'print-frames', 'wait 1100', 'print-frames']
        output = self.run_editor('100-palette-and-settings-cycles', actions, file)
        self.assertIn('tabs=1 active=stable.txt ', output)
        self.assertIn('stable\n\n<eod>', output)
        frames = [int(line[7:]) for line in output.splitlines() if line.startswith('frames=')]
        self.assertEqual(frames[-1], 0, 'Idle editor continues drawing without blinking or agents')


if __name__ == '__main__':
    suite = unittest.main(verbosity=2, exit=False)
    report = {'binary': str(EXE), 'platform': os.name, 'measurements': MEASUREMENTS,
              'passed': suite.result.wasSuccessful()}
    if os.environ.get('RHUN_TEST_ARTIFACTS'):
        directory = Path(os.environ['RHUN_TEST_ARTIFACTS'])
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'performance.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if suite.result.wasSuccessful() else 1)
