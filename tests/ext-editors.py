#!/usr/bin/env python3
"""Custom editors (docs/extensions/v1.1.md, "Feature: custom-editors"), driven headless with the fake
editors of tests/ext/edfake.py: an owned model (a byte flipper: editor-open, paged editor-read,
editor-dirty, saves in parts, Undo, Redo, Revert File, the close question, editor-changed when the
file changes on disk, Save As with editor-path) and a text model (rhun's document, changed by the
extension with replace; rhun's undo and save), Reopen With and its [editors] choice, and an editor
that refuses a file, which then opens as text."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
EXTS = ROOT / 'tests/ext/edexts'
CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
SETTLE = ['wait 300', 'wait 300', 'wait 300']
DATA = bytes([1, 2, 3, 4, 5, 6, 7])


def customs(out):
    return [l for l in out if l.startswith('cdoc=')]


def field(line, name):
    for f in line.split(' '):
        if f.startswith(name + '='):
            return f[len(name) + 1:]
    return None


class Editors(unittest.TestCase):
    def setUp(self):
        base = os.environ.get('RHUN_TEST_TMP')
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-ed-', dir=base)
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        self.flip = self.proj / 'a.flip'
        self.flip.write_bytes(DATA)
        self.up = self.proj / 'b.up'
        self.up.write_text('hello\nworld\n', encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.config = config
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix())
        self.env.pop('EDFAKE_MODE', None)

    def tearDown(self):
        self.tmp.cleanup()

    def log_of(self, name):
        p = self.work / f'state/rhun/extensions/rhun-tests--{name}/ed.log'
        return p.read_text(encoding='utf-8', errors='replace').splitlines() if p.exists() else []

    def run_editor(self, actions, mode=None, open_path=None):
        env = dict(self.env)
        if mode:
            env['EDFAKE_MODE'] = mode
        env['EDFAKE_LOG'] = 'ed.log'     # in each fake's own state folder
        opens = ['open ' + (open_path or self.flip).as_posix(), *SETTLE]
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', *opens, *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', '1000x600', '--scale', '1',
                                 '--extensions', str(EXTS), '--script', script.as_posix()],
                                env=env, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8', errors='replace').splitlines()

    def view_click(self):
        # the view fills the tab's area: a click near its top left
        return ['click 60 120', 'wait 300', 'wait 300']

    # --- the owned model ---

    def test_owned_opens_reads_in_pages_and_draws(self):
        out = self.run_editor(['print-custom', 'print-tabs'])
        c = customs(out)
        self.assertEqual(len(c), 1, out)
        self.assertEqual(field(c[0], 'model'), 'owned')
        self.assertEqual(field(c[0], 'state'), 'ready')
        self.assertEqual(field(c[0], 'dirty'), '0')
        self.assertEqual(field(c[0], 'ext'), 'rhun-tests/edflip')
        log = self.log_of('edflip')
        opened = [l for l in log if ' editor-open ' in l]
        self.assertEqual(len(opened), 1, log)
        self.assertEqual(opened[0].split(' ')[4:7], ['owned', 'file', str(len(self.flip.as_posix()))])

    def test_owned_flip_undo_redo_save_in_parts(self):
        out = self.run_editor([*self.view_click(), 'print-custom', 'cmd undo', *SETTLE, 'print-custom',
                               'cmd redo', *SETTLE, 'print-custom', 'key ctrl+s', *SETTLE, 'print-custom'])
        dirty = [field(c, 'dirty') for c in customs(out)]
        self.assertEqual(dirty, ['1', '0', '1', '0'], out)
        self.assertEqual(self.flip.read_bytes(), bytes([0xFE]) + DATA[1:])
        log = self.log_of('edflip')
        saves = [l.split(' ')[3:5] for l in log if ' editor-save ' in l]
        self.assertEqual(saves, [['save', '0'], ['save', '1'], ['save', '2']], log)

    def test_close_with_changes_asks_and_saves(self):
        out = self.run_editor([*self.view_click(), 'cmd close_tab', 'print-state', 'dialog yes', *SETTLE,
                               'print-custom', 'print-tabs'])
        self.assertIn('focus=5', '\n'.join(l for l in out if l.startswith('tabs=')))
        self.assertEqual(customs(out), [])
        self.assertEqual(self.flip.read_bytes(), bytes([0xFE]) + DATA[1:])
        self.assertTrue(any(' editor-closed ' in l or l.startswith('0 editor-closed ') for l in self.log_of('edflip')))

    def test_revert_and_disk_change(self):
        out = self.run_editor([*self.view_click(), 'cmd reload_file', *SETTLE, 'print-custom'])
        self.assertEqual(field(customs(out)[-1], 'dirty'), '0')
        self.assertTrue(any(' editor-revert ' in l for l in self.log_of('edflip')))

    def test_save_as_tells_the_new_path(self):
        other = self.proj / 'c.flip'
        out = self.run_editor([*self.view_click(), 'cmd save_as', 'wait 100', 'key ctrl+a',
                               'type ' + other.as_posix(), 'key Return', *SETTLE, 'print-custom'])
        self.assertEqual(other.read_bytes(), bytes([0xFE]) + DATA[1:])
        self.assertEqual(self.flip.read_bytes(), DATA)
        log = self.log_of('edflip')
        self.assertTrue(any(' editor-save ' in l and ' saveas ' in l for l in log), log)
        self.assertIn('path ' + other.as_posix(), log)
        self.assertEqual(field(customs(out)[-1], 'path'), other.as_posix())

    def test_refused_opens_as_text(self):
        self.flip.write_text('plain\n', encoding='utf-8')
        out = self.run_editor(['print-custom', 'print-state', 'print-toast'], mode='refuse')
        self.assertEqual(customs(out), [])
        self.assertIn('active=a.flip', '\n'.join(out))
        self.assertIn('this file is not for me', '\n'.join(out))

    def test_bad_part_keeps_it_dirty(self):
        out = self.run_editor([*self.view_click(), 'key ctrl+s', *SETTLE, 'print-custom', 'print-toast'],
                              mode='badpart')
        self.assertEqual(field(customs(out)[-1], 'dirty'), '1')
        self.assertEqual(self.flip.read_bytes(), DATA)

    # --- the text model and Reopen With ---

    def test_text_model_through_reopen_with(self):
        out = self.run_editor(['print-custom', 'reopen-with rhun-tests/edupper', *SETTLE, 'print-custom',
                               *self.view_click(), 'print-custom', 'cmd undo', 'print-custom', 'cmd redo',
                               'key ctrl+s', *SETTLE, 'print-custom'], open_path=self.up)
        c = customs(out)
        self.assertEqual(len(c), 4, out)                    # none before Reopen With (an option)
        self.assertEqual(field(c[0], 'model'), 'text')
        self.assertEqual([field(x, 'dirty') for x in c], ['0', '1', '0', '0'])
        self.assertEqual(self.up.read_text(encoding='utf-8'), 'HELLO\nworld\n')
        self.assertIn('*.up = rhun-tests/edupper', self.config.read_text(encoding='utf-8'))
        log = self.log_of('edupper')
        self.assertTrue(any(l.startswith('0 opened ') and l.endswith('b.up') for l in log), log)

    def test_reopen_with_text_goes_back(self):
        out = self.run_editor(['reopen-with text', *SETTLE, 'print-custom', 'print-state'])
        self.assertEqual(customs(out), [])
        self.assertIn('*.flip = text', self.config.read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
