#!/usr/bin/env python3
"""Notebooks (docs/extensions/v1.1.md, "Feature: notebooks"), driven headless with the fake
notebook extension tests/ext/nbfake.py (a line-based toy format, .nbt): opening through nb-open,
the cells and their outputs, Jupyter's command and edit modes, cell operations and their undo,
saving through nb-save byte for byte, runs with their states and streamed outputs, interrupt,
restart and the kernel button, the outputs rhun draws, caps, failures that offer the text, and a
reload when the file changes on disk."""
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
EXTS = ROOT / 'tests/ext/nbexts'

CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
NOTEBOOK = ('%% notebook {"k":1}\n'
            '%% code python 3\nprint("hi")\nx = 1\n'
            '%% out stdout text -\nhi\n'
            '%% markup\n# Title\nSome *text*\n'
            '%% code python -\ny = 2\n')
SETTLE = ['wait 300', 'wait 300', 'wait 300']


def cells(out):
    return [l for l in out if l.startswith('cell=')]


def dumps(out):
    """The print-notebook dumps in the output, each a list of its cell lines."""
    groups, cur = [], []
    for l in out:
        if l.startswith('cell='):
            cur.append(l)
        elif l.startswith('dirty='):
            groups.append(cur)
            cur = []
    return groups


def cells_of(out, i):
    return next(l for l in out if l.startswith('cell=%d ' % i))


def field(line, name):
    m = re.search(r'(?:^| )' + name + r'=(\S*)', line)
    return m.group(1) if m else None


class Notebooks(unittest.TestCase):
    def setUp(self):
        base = os.environ.get('RHUN_TEST_TMP')
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-nb-', dir=base)
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        self.nb = self.proj / 'a.nbt'
        self.nb.write_text(NOTEBOOK, encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.log = self.work / 'state/rhun/extensions/rhun-tests--nbfake/nb.log'
        self.cells_log = self.work / 'state/rhun/extensions/rhun-tests--cellfake/cells.log'
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(),
                        NBFAKE_LOG=self.log.as_posix(), CELLFAKE_LOG=self.cells_log.as_posix())
        self.env.pop('NBFAKE_MODE', None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions, mode=None, open_nb=True, exts=EXTS, size='1000x600'):
        env = dict(self.env)
        if mode:
            env['NBFAKE_MODE'] = mode
        opens = ['open ' + self.nb.as_posix(), *SETTLE] if open_nb else []
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', *opens, *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', size, '--scale', '1',
                                 '--extensions', str(exts), '--script', script.as_posix()],
                                env=env, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return result.stdout.decode('utf-8', errors='replace').splitlines()

    def fake_log(self):
        return self.log.read_text(encoding='utf-8', errors='replace').splitlines() if self.log.exists() else []

    # --- opening ---

    def test_open_shows_cells_outputs_and_kernel(self):
        out = self.run_editor(['print-notebook', 'print-nb-output 0 0', 'print-state'])
        cs = cells(out)
        self.assertEqual(len(cs), 3)
        self.assertEqual([field(c, 'kind') for c in cs], ['code', 'markup', 'code'])
        self.assertEqual([field(c, 'lang') for c in cs], ['Python', 'Markdown', 'Python'])
        self.assertEqual([field(c, 'count') for c in cs], ['3', '-', '-'])
        self.assertEqual([field(c, 'outputs') for c in cs], ['1', '0', '0'])
        self.assertEqual(field(cs[0], 'sel'), '1')
        self.assertIn('dirty=0 mode=command undo=0 kstate=idle kernel=Fake Kernel', out)
        i = out.index('output kind=stdout id=- items=text show=0 lines=1 bytes=27 keep=24')
        self.assertEqual(out[i + 1:i + 3], ['hi', '<eoo>'])
        # the active document is the selected cell's, which no v1 extension hears of
        state = next(l for l in out if l.startswith('tabs='))
        self.assertIn('active=cell', state)
        self.assertIn('lang=Python', state)
        log = self.fake_log()
        self.assertIn('0 features notebooks', log)
        self.assertIn('0 active 0', log)
        self.assertFalse(any(l.startswith('0 opened') for l in log), log)

    def test_save_round_trip_byte_for_byte(self):
        self.run_editor(['key ctrl+s', *SETTLE])
        self.assertEqual(self.nb.read_text(encoding='utf-8'), NOTEBOOK)
        self.assertTrue(any(l.startswith('1 nb-open 1 ') for l in self.fake_log()))
        self.assertTrue(any(l.startswith('2 nb-save 1 ') for l in self.fake_log()))

    def test_edit_a_cell_then_save(self):
        out = self.run_editor(['key Return', 'type z = 3', 'key Return', 'print-notebook', 'print-doc',
                               'key ctrl+s', *SETTLE, 'print-notebook'])
        self.assertIn('z = 3\nprint("hi")\nx = 1', '\n'.join(out))
        dirty = [l for l in out if l.startswith('dirty=')]
        self.assertTrue(dirty[0].startswith('dirty=1 mode=edit'))
        self.assertTrue(dirty[1].startswith('dirty=0'))
        self.assertEqual(self.nb.read_text(encoding='utf-8'), NOTEBOOK.replace('print("hi")', 'z = 3\nprint("hi")'))

    def test_missing_file_opens_empty_and_saves(self):
        self.nb.unlink()
        out = self.run_editor(['print-notebook', 'key Return', 'type x = 1', 'key ctrl+s', *SETTLE])
        self.assertEqual(len(cells(out)), 1)
        self.assertEqual(self.nb.read_text(encoding='utf-8'), '%% code - -\nx = 1\n')

    # --- the keyboard ---

    def test_command_mode_keys(self):
        out = self.run_editor(['key j', 'key j', 'key k', 'print-notebook',
                               'key b', 'print-notebook', 'key a', 'print-notebook',
                               'key d', 'key d', 'print-notebook', 'key z', 'print-notebook',
                               'key m', 'print-notebook', 'key y', 'print-notebook',
                               'key alt+Up', 'print-notebook', 'key z', 'key z', 'key z', 'key z', 'key z',
                               'print-notebook', 'type q', 'print-notebook'])
        runs = dumps(out)
        sel = lambda cs: next(i for i, c in enumerate(cs) if field(c, 'sel') == '1')
        self.assertEqual(sel(runs[0]), 1)                       # j j k
        self.assertEqual((len(runs[1]), sel(runs[1])), (4, 2))  # b
        self.assertEqual((len(runs[2]), sel(runs[2])), (5, 2))  # a: above the new one
        self.assertEqual(len(runs[3]), 4)                       # d d
        self.assertEqual(len(runs[4]), 5)                       # z brings it back
        self.assertEqual(field(runs[5][2], 'kind'), 'markup')   # m
        self.assertEqual(field(runs[6][2], 'kind'), 'code')     # y
        self.assertEqual(sel(runs[7]), 1)                       # alt+Up moved it
        self.assertEqual([field(c, 'id') for c in runs[8]], ['1', '2', '3'])   # five z: back to the file
        self.assertEqual(runs[9], runs[8])                      # a letter in command mode types nothing
        self.assertIn('dirty=1', '\n'.join(out))

    def test_edit_mode_crosses_cells(self):
        out = self.run_editor(['key Return', 'key Down', 'key Down', 'print-notebook', 'print-state',
                               'key Down', 'key Down', 'print-notebook', 'key Up', 'print-notebook',
                               'key Escape', 'print-notebook'])
        runs = dumps(out)
        sel = lambda cs: next(i for i, c in enumerate(cs) if field(c, 'sel') == '1')
        self.assertEqual(sel(runs[0]), 1)
        self.assertEqual(field(runs[0][1], 'editing'), '1')
        self.assertIn('lang=Markdown', next(l for l in out if l.startswith('tabs=')))
        self.assertEqual(sel(runs[1]), 2)
        self.assertEqual(sel(runs[2]), 1)
        self.assertIn('mode=command', [l for l in out if l.startswith('dirty=')][-1])

    def test_palette_commands(self):
        out = self.run_editor(['cmd notebook.insert_below', 'cmd notebook.to_markup', 'print-notebook',
                               'cmd notebook.delete_cell', 'cmd notebook.undo_cell', 'print-notebook'])
        runs = dumps(out)
        self.assertEqual(len(runs[0]), 4)
        self.assertEqual(field(runs[0][1], 'kind'), 'markup')
        self.assertEqual(len(runs[1]), 4)

    def test_mouse_selects_edits_runs_and_scrolls(self):
        out = self.run_editor(['print-notebook'])
        x, y = map(int, field(cells(out)[2], 'at').split(','))
        # past "y " in the third cell: the fold lane (12 px) and the margin come before the text
        out = self.run_editor([f'click {x + 46} {y + 10}', 'type Z', 'print-notebook', 'print-doc',
                               f'click {x - 26} {y + 10}', *SETTLE, 'print-notebook'])
        runs = dumps(out)
        self.assertEqual((field(runs[0][2], 'sel'), field(runs[0][2], 'editing')), ('1', '1'))
        self.assertIn('y Z= 2', out)
        self.assertEqual(field(runs[1][2], 'state'), 'done')    # the count column runs the cell
        # a long notebook scrolls with the wheel; cells above the view are not drawn
        self.nb.write_text(''.join(f'%% code python -\nx{i} = {i}\n' for i in range(40)), encoding='utf-8')
        out = self.run_editor(['print-notebook', 'move 500 300', 'scroll 600', 'print-notebook', 'key End', 'print-notebook'])
        runs = dumps(out)
        self.assertEqual(field(runs[0][20], 'at'), '-1')
        self.assertEqual(field(runs[1][0], 'at'), '-1')
        self.assertNotEqual(field(runs[1][20], 'at'), '-1')
        self.assertNotEqual(field(runs[2][39], 'at'), '-1')    # End brings the last cell into view

    def test_context_keys(self):
        out = self.run_editor(['print-context notebookFocus', 'print-context activeTab',
                               'print-context notebookCellType', 'print-context notebookKernelState',
                               'key Return', 'print-context notebookCellEditing',
                               'when notebookFocus && !notebookCellEditing', 'key Escape', 'key j',
                               'print-context notebookCellType', 'when notebookFocus && !notebookCellEditing'])
        self.assertEqual(out, ['notebookFocus=true', 'activeTab=notebook', 'notebookCellType=code',
                               'notebookKernelState=idle', 'notebookCellEditing=true', 'when=0',
                               'notebookCellType=markup', 'when=1'])

    # --- runs ---

    def test_run_states_count_and_stream(self):
        out = self.run_editor(['nb-select 2', 'key ctrl+Return', *SETTLE, 'print-notebook', 'print-nb-output 2 0'])
        c = cells(out)[2]
        self.assertEqual((field(c, 'count'), field(c, 'state'), field(c, 'outputs')), ('1', 'done', '1'))
        i = out.index('output kind=stdout id=- items=ansi show=0 lines=1 bytes=12 keep=0')
        self.assertEqual(out[i + 1], 'echo: y = 2')
        log = self.fake_log()
        self.assertIn('0 nb-run 1 3 1 python 5', log)

    def test_shift_enter_on_the_last_cell_adds_one(self):
        out = self.run_editor(['nb-select 2', 'key shift+Return', *SETTLE, 'print-notebook'])
        cs = cells(out)
        self.assertEqual(len(cs), 4)
        self.assertEqual((field(cs[3], 'sel'), field(cs[3], 'editing')), ('1', '1'))

    def test_run_all_and_clear(self):
        out = self.run_editor(['cmd notebook.run_all', *SETTLE, 'wait 300', 'print-notebook',
                               'cmd notebook.clear_outputs', 'print-notebook'])
        runs = dumps(out)
        self.assertEqual([field(c, 'count') for c in runs[0]], ['1', '-', '2'])
        self.assertEqual([field(c, 'outputs') for c in runs[0]], ['1', '0', '1'])
        self.assertEqual([field(c, 'outputs') for c in runs[1]], ['0', '0', '0'])

    def test_interrupt(self):
        self.nb.write_text('%% code python -\nsleep()\n', encoding='utf-8')
        out = self.run_editor(['key ctrl+Return', *SETTLE, 'print-notebook', 'key i', 'key i', *SETTLE,
                               'print-notebook', 'print-nb-output 0 0', 'print-nb-output 0 1'])
        runs = dumps(out)
        self.assertEqual(field(runs[0][0], 'state'), 'running')
        self.assertEqual(field(runs[1][0], 'state'), 'failed')
        self.assertIn('0 nb-interrupt 1', self.fake_log())
        self.assertIn('KeyboardInterrupt', out)
        self.assertIn('output kind=stderr id=- items=ansi show=0 lines=1 bytes=18 keep=0', out)

    def test_restart_asks_first(self):
        out = self.run_editor(['key 0', 'key 0', 'print-dialog', 'dialog yes', *SETTLE, 'print-notebook'])
        self.assertTrue(any('Restart the kernel?' in l for l in out), out)
        self.assertIn('0 nb-restart 1', self.fake_log())
        self.assertIn('kstate=idle kernel=Fake Kernel', '\n'.join(out))

    def test_kernel_button_lets_the_extension_choose(self):
        out = self.run_editor(['cmd notebook.select_kernel', *SETTLE, 'print-palette', 'key Down', 'key Return',
                               *SETTLE, 'print-notebook'])
        self.assertIn('choose=Pick a kernel', out)
        self.assertIn('0 nb-kernel 1', self.fake_log())
        self.assertIn('kernel=Other Kernel', [l for l in out if l.startswith('dirty=')][-1])

    # --- find across the cells (A4) ---

    def test_find_next_and_previous_cross_cells(self):
        # typing in the find bar selects the first match; Find Next goes on to the next cell's
        out = self.run_editor(['key Return', 'cmd find', 'type =', 'print-notebook', 'print-state',
                               'cmd find_next', 'print-notebook', 'print-state', 'cmd find_next', 'print-notebook',
                               'cmd find_prev', 'print-notebook'])
        runs = dumps(out)
        sel = [[field(c, 'sel') for c in r] for r in runs]
        self.assertEqual(sel, [['1', '0', '0'], ['0', '0', '1'], ['1', '0', '0'], ['0', '0', '1']], out)
        self.assertEqual(field(runs[1][2], 'editing'), '1')
        states = [l for l in out if l.startswith('tabs=')]
        self.assertIn('line=2 col=4 sel=1 ', states[0])       # x =| in the first cell
        self.assertIn('line=1 col=4 sel=1 ', states[1])       # y =| in the third
        self.assertIn('focus=2', states[1])                   # the find bar keeps the keys

    # --- cells for language providers (A3) ---

    def test_cells_reach_language_providers(self):
        out = self.run_editor(['wait 300', 'key Return', 'key End', 'type  + ', 'cmd complete', 'wait 500',
                               'print-complete', 'key Return', *SETTLE, 'print-notebook', 'key Escape', 'nb-select 2',
                               'key d', 'key d', *SETTLE, 'wait 300'])
        log = self.cells_log.read_text(encoding='utf-8').splitlines()
        opened = [l.split(' ') for l in log if l.startswith('0 opened ')]
        # the Python cells (not the Markdown one), with no path
        self.assertEqual([(o[4], o[5]) for o in opened], [('Python', '-'), ('Python', '-')], log)
        d0, d2 = opened[0][2], opened[1][2]
        cell = [l for l in log if l.startswith('0 cell ')]
        self.assertEqual([c.split(' ')[3] for c in cell[:2]], ['1', '1'])          # notebook 1
        self.assertEqual([(c.split(' ')[2], c.split(' ')[5]) for c in cell[:2]], [(d0, '0'), (d2, '2')])
        cells = [l for l in log if l.startswith('0 cells ')]
        self.assertEqual(cells[0], '0 cells 1 %s %s' % (d0, d2))
        self.assertIn('0 cells 1 %s' % d0, cells)                                   # after the delete
        self.assertTrue(any(l.startswith('0 edits %s ' % d0) for l in log), log)
        self.assertIn('0 closed %s' % d2, log)
        self.assertIn('text print("hi")+|x = 1', log)                              # its text request
        self.assertTrue(any(l.startswith('1 complete %s ' % d0) for l in log), log)
        self.assertIn('cell_item', '\n'.join(out))
        self.assertIn('lines=2 ', cells_of(out, 0))
        self.assertNotIn('0 opened', '\n'.join(self.fake_log()))                  # nbfake did not agree to cells

    # --- kernels that run as the user (nb-exec) ---

    def test_kernel_runs_as_the_user_after_approval(self):
        self.nb.write_text('%% code python -\nexec()\n%% code python -\nexec()\n', encoding='utf-8')
        out = self.run_editor(['key ctrl+Return', 'wait 300', 'print-dialog', 'dialog yes', *SETTLE, 'wait 500',
                               'print-notebook', 'print-nb-output 0 0', 'nb-select 1', 'key ctrl+Return',
                               *SETTLE, 'wait 500', 'print-dialog', 'print-notebook', 'print-nb-output 1 0',
                               'print-nb-exec'])
        dialogs = [l for l in out if l.startswith('dialog=') and l != 'dialog=none']
        self.assertEqual(dialogs[0], 'dialog=Let Fake Notebooks run programs in proj?', out)
        self.assertEqual(len(dialogs), 1, out)  # once per extension and project
        runs = dumps(out)
        self.assertEqual(field(runs[0][0], 'state'), 'done')
        self.assertEqual(field(runs[1][1], 'state'), 'done')
        text = '\n'.join(out)
        self.assertIn('exit=3 log=kernel in %s from-rhun' % self.proj, text)
        self.assertEqual(text.count('exit=3 log='), 2)
        self.assertNotIn('state=running', '\n'.join(l for l in out if l.startswith('exec=')))
        ini = (self.work / 'config/rhun/extensions.ini').read_text(encoding='utf-8')
        self.assertIn('allow_run = ' + str(self.proj), ini)

    def test_kernel_refused_or_not_in_needs(self):
        self.nb.write_text('%% code python -\nexec()\n%% code python -\nexecbad()\n', encoding='utf-8')
        out = self.run_editor(['key ctrl+Return', 'wait 300', 'dialog no', *SETTLE, 'print-nb-output 0 0',
                               'nb-select 1', 'key ctrl+Return', *SETTLE, 'print-dialog', 'print-notebook',
                               'print-nb-output 1 0'])
        self.assertIn('exec: refused the user did not allow it', '\n'.join(out))
        self.assertIn('exec: needs kernels=sh', '\n'.join(out))
        self.assertEqual([field(c, 'state') for c in dumps(out)[0]], ['failed', 'failed'])

    def test_interrupt_stops_a_kernel_and_closing_ends_it(self):
        self.nb.write_text('%% code python -\nexecsleep()\n', encoding='utf-8')
        out = self.run_editor(['key ctrl+Return', 'wait 300', 'dialog yes', *SETTLE, 'print-nb-exec',
                               'key i', 'key i', *SETTLE, 'wait 500', 'print-notebook', 'print-nb-output 0 0',
                               'print-nb-exec'])
        execs = [l for l in out if l.startswith('exec=')]
        self.assertEqual(len(execs), 1, out)
        self.assertIn('state=running', execs[0])
        self.assertEqual(field(dumps(out)[0][0], 'state'), 'cancelled')
        self.assertIn('exit=137 log=', '\n'.join(out))

    def test_outputs_rhun_draws(self):
        self.nb.write_text('%% code python -\npng()\n%% code python -\nerror()\n%% code python -\nprogress()\n'
                           '%% code python -\nclearwait()\n%% code python -\nreplace()\n%% code python -\ncolors()\n',
                           encoding='utf-8')
        out = self.run_editor(['cmd notebook.run_all', *SETTLE, 'wait 500', 'print-notebook',
                               *[f'print-nb-output {i} 0' for i in range(6)],
                               'shot ' + (self.work / 'outputs.ppm').as_posix()])
        text = '\n'.join(out)
        self.assertIn('output kind=display id=- items=png,text show=0 lines=0', text)
        self.assertIn('image=40x20', text)
        self.assertIn('output kind=error id=- items=ansi', text)
        self.assertIn('\\e[0;31mValueError\\e[0m: bad value', text)
        self.assertIn('30%\ndone\n<eoo>', text)
        self.assertIn('second\n<eoo>', text)
        self.assertNotIn('first\n', text)
        self.assertIn('output kind=display id=d1 items=text show=0 lines=1', text)
        self.assertIn('new\n<eoo>', text)
        self.assertIn('\\e[1;32mgreen\\e[0m', text)
        colors = ppm_colors(self.work / 'outputs.ppm')
        self.assertIn((0, 200, 0), colors)          # the PNG, 1:1

    def test_long_output_opens_in_a_tab(self):
        self.nb.write_text('%% code python -\nmany()\n', encoding='utf-8')
        out = self.run_editor(['key ctrl+Return', *SETTLE, 'print-nb-output 0 0', 'nb-output-tab 0 0',
                               'print-state', 'cmd goto_line', 'type 1000', 'key Return', 'print-state'])
        self.assertIn('lines=1000', [l for l in out if l.startswith('output kind=')][0])
        states = [l for l in out if l.startswith('tabs=')]
        self.assertTrue(states[0].startswith('tabs=2 active=Output'), states)
        self.assertIn('line=1000', states[1])

    def test_stale_answers_and_caps(self):
        self.nb.write_text('%% code python -\nstale()\n%% code python -\ntoobig()\n', encoding='utf-8')
        out = self.run_editor(['cmd notebook.run_all', *SETTLE, 'wait 2000', 'print-notebook'])
        log = self.fake_log()
        self.assertTrue(any(re.match(r'error \d+ stale', l) for l in log), log)
        self.assertTrue(any(re.match(r'error \d+ toobig', l) for l in log), log)
        c = cells(out)[1]
        self.assertEqual(field(c, 'outputs'), '1000')

    # --- failures ---

    def test_open_error_offers_the_text(self):
        out = self.run_editor(['print-notebook', 'cmd notebook.reopen_as_text', 'print-state', 'print-doc'],
                              mode='openerror')
        self.assertEqual(out[0], 'notebook=failed error=Fake Notebooks: this is not a toy notebook')
        self.assertTrue(next(l for l in out if l.startswith('tabs=')).startswith('tabs=1 active=a.nbt'))
        self.assertIn('%% markup', out)

    def test_bad_body_and_no_feature(self):
        out = self.run_editor(['print-notebook'], mode='badbody')
        self.assertEqual(out[0], "notebook=failed error=The extension's notebook cannot be read")
        for mode in ('wideheader', 'widerheader'):      # more fields than a body line has
            out = self.run_editor(['print-notebook'], mode=mode)
            self.assertEqual(out[0], "notebook=failed error=The extension's notebook cannot be read")
        out = self.run_editor(['print-notebook'], mode='nofeature')
        self.assertEqual(out[0], 'notebook=failed error=Fake Notebooks does not read notebooks (the notebooks feature)')

    def test_save_error_keeps_it_dirty(self):
        out = self.run_editor(['key Return', 'type q', 'key ctrl+s', *SETTLE, 'print-toast', 'print-notebook'],
                              mode='saveerror')
        self.assertIn('toast=Fake Notebooks: the disk is full', out)
        self.assertTrue([l for l in out if l.startswith('dirty=')][-1].startswith('dirty=1'))
        self.assertEqual(self.nb.read_text(encoding='utf-8'), NOTEBOOK)

    def test_typing_while_a_save_is_answered_stays_dirty(self):
        out = self.run_editor(['key Return', 'type x', 'key ctrl+s', 'type y', 'wait 2500', *SETTLE,
                               'print-notebook', 'key ctrl+s', 'wait 2500', *SETTLE, 'print-notebook'],
                              mode='slowsave')
        dirty = [l for l in out if l.startswith('dirty=')]
        self.assertTrue(dirty[0].startswith('dirty=1'), dirty)  # the file has x, the cell xy
        self.assertTrue(dirty[1].startswith('dirty=0'), dirty)
        self.assertEqual(self.nb.read_text(encoding='utf-8'), NOTEBOOK.replace('print("hi")', 'xyprint("hi")'))

    def test_typing_while_a_reload_is_answered_keeps_it(self):
        out = self.run_editor(['wait 2500', 'cmd reload_file', 'key Return', 'type q', 'wait 2500', *SETTLE,
                               'print-notebook', 'print-doc'], mode='slowopen')
        self.assertTrue([l for l in out if l.startswith('dirty=')][-1].startswith('dirty=1'), out)
        self.assertIn('qprint("hi")', '\n'.join(out))
        self.assertEqual(sum(1 for l in self.fake_log() if ' nb-open ' in l), 2)

    def test_deleting_the_only_cell_undoes_in_one_z(self):
        self.nb.write_text('%% code python -\nonly = 1\n', encoding='utf-8')
        out = self.run_editor(['key d', 'key d', 'print-notebook', 'key z', 'print-notebook', 'print-doc'])
        runs = dumps(out)
        self.assertEqual(len(runs[0]), 1)
        self.assertNotEqual(field(runs[0][0], 'id'), '1')       # a blank one in its place
        self.assertEqual([field(c, 'id') for c in runs[1]], ['1'])
        self.assertIn('only = 1', out)

    def test_command_mode_leaves_the_text_alone(self):
        out = self.run_editor(['key Return', 'key Right', 'key Escape', 'key BackSpace', 'key Delete', 'key Tab',
                               'print-notebook', 'print-doc'])
        self.assertTrue([l for l in out if l.startswith('dirty=')][-1].startswith('dirty=0 mode=command'), out)
        self.assertIn('print("hi")', out)

    def test_clear_wait_before_any_output(self):
        self.nb.write_text('%% code python -\nclearfirst()\n%% code python -\npngwide()\n', encoding='utf-8')
        out = self.run_editor(['cmd notebook.run_all', *SETTLE, 'wait 500', 'print-nb-output 0 0',
                               'print-nb-output 1 0'])
        text = '\n'.join(out)
        self.assertIn('first\nsecond\n<eoo>', text)
        self.assertIn('image=80x40', text)                      # a width alone keeps the proportions

    def test_save_as_onto_a_read_only_file(self):
        target = self.proj / 'b.nbt'
        target.write_text('old\n', encoding='utf-8')
        os.chmod(target, 0o444)
        try:
            out = self.run_editor(['key Return', 'type q', 'key Escape', 'cmd save_as', 'key ctrl+a',
                                   'type ' + target.as_posix(), 'key Return', 'key Return', *SETTLE, 'wait 500',
                                   'print-notebook'])
            self.assertEqual(target.read_text(encoding='utf-8'), NOTEBOOK.replace('print("hi")', 'qprint("hi")'))
            self.assertTrue([l for l in out if l.startswith('dirty=')][-1].startswith('dirty=0'), out)
        finally:
            os.chmod(target, 0o644)

    def test_close_with_changes_asks_and_saves(self):
        out = self.run_editor(['key Return', 'type q', 'key ctrl+w', 'print-state', 'dialog yes', *SETTLE,
                               'print-state'])
        states = [l for l in out if l.startswith('tabs=')]
        self.assertIn('focus=5', states[0])         # the unsaved-changes dialog
        self.assertTrue(states[1].startswith('tabs=0'), states)
        self.assertEqual(self.nb.read_text(encoding='utf-8'), NOTEBOOK.replace('print("hi")', 'qprint("hi")'))
        self.assertIn('0 nb-closed 1', self.fake_log())

    def test_large_answer_passes_the_usual_cap(self):
        big = 'x' * 1000 + '\n'
        self.nb.write_text('%% code python -\nbig\n%% out stdout text -\n' + big * 6000, encoding='utf-8')
        out = self.run_editor(['print-notebook', 'key ctrl+s', *SETTLE, 'wait 500'])
        self.assertEqual(len(cells(out)), 1)
        self.assertEqual(field(cells(out)[0], 'outputs'), '1')
        self.assertEqual(self.nb.stat().st_size, len(('%% code python -\nbig\n%% out stdout text -\n' + big * 6000).encode()))


def ppm_colors(path):
    data = path.read_bytes()
    fields, pos = [], 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(data[start:pos])
    pixels = data[pos + 1:]
    return {tuple(pixels[i:i + 3]) for i in range(0, len(pixels) - 2, 3)}


@unittest.skipIf(os.name == 'nt', 'the control socket is Unix only')
class Reload(unittest.TestCase):
    """A notebook whose file changes on disk: read again while clean, kept with a warning while dirty."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-nbr-', dir='/tmp')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'p'
        self.proj.mkdir()
        self.nb = self.proj / 'a.nbt'
        self.nb.write_text(NOTEBOOK, encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'))
        control = self.work / 'c'
        self.process = subprocess.Popen([str(EXE), str(self.proj), '--headless', '1000x600', '--scale', '1',
                                         '--extensions', str(EXTS), '--control', str(control)], env=self.env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.client.settimeout(15)
        deadline = time.monotonic() + 10
        while True:
            try:
                self.client.connect(str(control))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if self.process.poll() is not None or time.monotonic() > deadline:
                    self.fail('editor did not start')
                time.sleep(0.01)
        self.reader = self.client.makefile('r', encoding='utf-8')

    def tearDown(self):
        if self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=10)
        self.process.stderr.close()
        self.reader.close()
        self.client.close()
        self.tmp.cleanup()

    def command(self, line):
        self.client.sendall((line + '\n').encode('utf-8'))
        output = []
        while True:
            reply = self.reader.readline()
            if reply == 'ok\n':
                return ''.join(output)
            self.assertNotIn(reply, ('', 'error\n'), line)
            output.append(reply)

    def wait_for(self, text, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            out = self.command('print-notebook')
            if text in out:
                return out
            self.command('wait 100')
        self.fail(f'{text!r} not in {out!r}')

    def test_reload_when_clean_warning_when_dirty(self):
        self.command('open ' + str(self.nb))
        self.wait_for('kernel=Fake Kernel')
        self.nb.write_text(NOTEBOOK + '%% code python -\nnew = 1\n', encoding='utf-8')
        out = self.wait_for('cell=3 ')
        self.assertIn('dirty=0', out)
        # with a change of its own, the notebook keeps its cells
        self.command('key Return')
        self.command('type q')
        self.nb.write_text(NOTEBOOK, encoding='utf-8')
        time.sleep(1.5)
        self.command('wait 500')
        out = self.command('print-notebook')
        self.assertIn('cell=3 ', out)
        self.assertIn('dirty=1', out)
        # Revert File reads it again
        self.command('cmd reload_file')
        out = self.wait_for('dirty=0')
        self.assertNotIn('cell=3 ', out)


if __name__ == '__main__':
    unittest.main()
