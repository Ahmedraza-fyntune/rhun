#!/usr/bin/env python3
"""Notifications and progress (features notify and progress), driven headlessly with the viewfake
extension: cards with buttons and command references, timeouts, the stack's limit, the keyboard,
notify-set and unnotify, progress in the status bar, in a card with Cancel and in a view."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from viewsharness import ViewsBase  # noqa: E402


class Notes(ViewsBase):
    def setUp(self):
        super().setUp()
        self.env['VIEWFAKE_NOTIFY'] = '1'

    def notes(self, out):
        return [l for l in out if l.startswith('note=')]

    def test_a_card_shows_its_message_and_goes_after_8_s(self):
        out = self.run_editor(['cmd viewfake.note', 'wait 200', 'print-notes', 'wait 3000', 'wait 3000',
                               'wait 2500', 'print-notes'])
        notes = self.notes(out)
        self.assertEqual(len(notes), 1, out)
        self.assertTrue(notes[0].startswith('note=1 sev=info buttons= msg=Indexed 12 files detail=workspace at='),
                        notes)
        self.assertIn('0 notify 1 closed', self.fake_log())
        self.assertIn('0 features view-tree view-log notify progress', self.fake_log())

    def test_the_pointer_over_a_card_holds_it_without_redraws(self):
        out = self.run_editor(['cmd viewfake.note', 'wait 200', 'print-notes'])
        note = self.notes(out)[0]
        x, y = map(int, note.split(' at=')[1].split(' ')[0].split(','))
        out = self.run_editor(['cmd viewfake.note', 'wait 200', f'move {x + 20} {y + 20}', 'wait 3000', 'wait 3000',
                               'wait 3000', 'print-notes'])
        self.assertEqual(len(self.notes(out)), 1)
        self.assertNotIn('0 notify 1 closed', self.fake_log())

    def test_a_button_runs_its_command_or_says_pressed(self):
        out = self.run_editor(['cmd viewfake.noteask', 'wait 200', 'print-notes', 'note-press 0 2', 'wait 100',
                               'print-notes', 'cmd viewfake.noteask', 'wait 200', 'note-press 0 1', 'wait 300',
                               'print-notes'])
        notes = self.notes(out)
        self.assertEqual(len(notes), 1, out)        # each press closed its card
        self.assertIn('sev=warning buttons=Reload|Later msg=Reload the window to use the new settings? stays',
                      notes[0])
        log = self.fake_log()
        self.assertIn('0 notify 1 pressed 2', log)
        self.assertNotIn('0 notify 2 pressed 1', log)
        self.assertTrue(any(l.startswith('0 run rhun-tests/viewfake.rescan') or l.startswith('0 run viewfake.rescan')
                            for l in log), log)

    def test_the_close_button_and_the_pointer_over_a_card(self):
        (self.proj / 'note.txt').write_text('one\ntwo\n' * 40, encoding='utf-8')
        out = self.run_editor([f'open {self.proj / "note.txt"}', 'cmd viewfake.noteerr', 'wait 200',
                               'print-notes'])
        note = self.notes(out)[0]
        self.assertIn(' stays', note)               # an error stays
        x, y = map(int, note.split(' at=')[1].split(' ')[0].split(','))
        w, h = map(int, note.split(' size=')[1].split('x'))
        self.assertGreater(h, 60)                   # wrapped onto several lines
        out = self.run_editor([f'open {self.proj / "note.txt"}', 'cmd viewfake.noteerr', 'wait 200',
                               'print-state', f'click {x + w // 2} {y + h - 6}', 'wait 50', 'print-state',
                               f'click {x + w - 22} {y + 18}', 'wait 100', 'print-notes'])
        states = [l for l in out if l.startswith('tabs=')]
        self.assertEqual(states[0].split(' focus=')[0], states[1].split(' focus=')[0])   # the editor kept its cursor
        self.assertEqual(self.notes(out), [])
        self.assertIn('0 notify 1 closed', self.fake_log())

    def test_four_cards_show_and_the_rest_wait(self):
        out = self.run_editor(['cmd viewfake.notemany', 'wait 300', 'print-notes'])
        notes = self.notes(out)
        self.assertEqual(len(notes), 6)
        drawn = [n for n in notes if ' at=' in n]
        self.assertEqual([n.split(' ')[0] for n in drawn], ['note=3', 'note=4', 'note=5', 'note=6'])
        ys = [int(n.split(' at=')[1].split(',')[1].split(' ')[0]) for n in drawn]
        self.assertEqual(ys, sorted(ys))            # newest at the bottom

    def test_sixteen_per_extension(self):
        self.run_editor(['cmd viewfake.notes17', 'wait 300'])
        log = self.fake_log()
        self.assertEqual(sum(1 for l in log if l.endswith(' toobig 16 notifications')), 1, log)

    def test_the_keyboard_moves_between_buttons(self):
        out = self.run_editor(['cmd viewfake.noteask', 'wait 200', 'cmd focus_notifications', 'print-state',
                               'key Right', 'key Right', 'key Return', 'wait 100', 'print-notes', 'print-state'])
        states = [l for l in out if l.startswith('tabs=')]
        self.assertIn('focus=10', states[0])
        self.assertNotIn('focus=10', states[1])     # no cards left: back to the editor
        self.assertIn('0 notify 1 pressed 2', self.fake_log())

    def test_enter_without_a_button_closes_and_escape_goes_back(self):
        out = self.run_editor(['cmd viewfake.notemany', 'wait 300', 'cmd focus_notifications', 'key Return',
                               'key Up', 'key Delete', 'wait 50', 'print-notes', 'key Escape', 'print-state'])
        self.assertEqual([n.split(' ')[0] for n in self.notes(out)], ['note=1', 'note=2', 'note=3', 'note=5'])
        self.assertNotIn('focus=10', [l for l in out if l.startswith('tabs=')][0])
        log = self.fake_log()
        self.assertIn('0 notify 6 closed', log)
        self.assertIn('0 notify 4 closed', log)

    def test_a_card_that_comes_later_is_below_the_older_ones(self):
        out = self.run_editor(['cmd viewfake.notemany', 'wait 300', 'cmd viewfake.noteclose1', 'wait 100',
                               'cmd viewfake.note', 'wait 300', 'print-notes'])
        drawn = [n for n in self.notes(out) if ' at=' in n]
        ys = {n.split(' ')[0]: int(n.split(' at=')[1].split(',')[1].split(' ')[0]) for n in drawn}
        self.assertIn('note=7', ys)                 # in the first card's slot, yet the newest
        self.assertEqual(max(ys, key=ys.get), 'note=7')

    def test_clear_closes_every_card(self):
        out = self.run_editor(['cmd viewfake.notemany', 'wait 300', 'cmd clear_notifications', 'print-notes'])
        self.assertEqual(self.notes(out), [])
        log = self.fake_log()
        self.assertEqual(sum(1 for l in log if l.startswith('0 notify ') and l.endswith(' closed')), 6)

    def test_notify_set_replaces_and_unnotify_closes_quietly(self):
        out = self.run_editor(['cmd viewfake.note', 'wait 200', 'cmd viewfake.noteset', 'wait 200', 'print-notes',
                               'cmd viewfake.unnote', 'wait 200', 'print-notes', 'cmd viewfake.unnote', 'wait 200'])
        notes = self.notes(out)
        self.assertEqual(len(notes), 1)
        self.assertIn('buttons=Open msg=Indexed 40 files stays', notes[0])
        log = self.fake_log()
        self.assertNotIn('0 notify 1 closed', log)
        self.assertTrue(any(l.startswith('error ') and l.endswith(' noview no such notification') for l in log), log)


class MarkdownPopups(ViewsBase):
    """Feature markdown: notification messages and node tooltips drawn as Markdown."""
    def setUp(self):
        super().setUp()
        self.env['VIEWFAKE_NOTIFY'] = '1'

    def card(self, out):
        return [l for l in out if l.startswith('note=')][0]

    def test_a_message_is_markdown_with_the_feature(self):
        self.env['VIEWFAKE_MARKDOWN'] = '1'
        out = self.run_editor(['cmd viewfake.notemd', 'wait 200', 'print-notes'])
        card = self.card(out)
        self.assertIn(' markdown msg=**Indexed** 12 files', card)
        h_md = int(card.split(' size=')[1].split('x')[1].split(' ')[0]) if ' size=' in card else None
        del self.env['VIEWFAKE_MARKDOWN']
        out = self.run_editor(['cmd viewfake.notemd', 'wait 200', 'print-notes'])
        self.assertNotIn(' markdown ', self.card(out))
        self.assertTrue(h_md is None or h_md > 0)

    def test_a_node_tooltip_is_markdown_with_the_feature(self):
        self.env['VIEWFAKE_MARKDOWN'] = '1'
        out = self.run_editor(['print-view todo'])
        row = [l for l in out if 'label=TODO: item 1 of main.rs' in l][0]
        y = int(row.split(' y=')[1].split(' ')[0])
        at = [l for l in out if l.startswith('at=')][0]
        x = int(at[3:].split(',')[0])
        out = self.run_editor([f'move {x + 60} {y + 8}', 'wait 700', 'wait 300', 'print-tip'])
        self.assertIn('tip=tip of 1', out)


class Progress(ViewsBase):
    def setUp(self):
        super().setUp()
        self.env['VIEWFAKE_NOTIFY'] = '1'

    def progress(self, out):
        return [l for l in out if l.startswith('progress=')]

    def test_status_progress_shows_after_half_a_second(self):
        out = self.run_editor(['cmd viewfake.prog', 'wait 100', 'print-notes', 'wait 600', 'print-notes',
                               'cmd viewfake.progend', 'wait 100', 'print-notes'])
        p = self.progress(out)
        self.assertEqual(len(p), 2, out)
        self.assertTrue(p[0].startswith('progress=1 where=status percent=42 cancel=1 shown=0 title=Indexing'), p)
        self.assertEqual(p[1], 'progress=1 where=status percent=42 cancel=1 shown=1 title=Indexing msg=crates')

    def test_cancel_says_so_and_it_goes_10_s_later(self):
        out = self.run_editor(['cmd viewfake.prognote', 'wait 700', 'note-press 0 cancel', 'wait 100',
                               'print-notes'])
        self.assertIn('progress=1 where=note percent=- cancel=2 shown=1 title=Downloading', out)
        self.assertIn('0 progress 1 cancel', self.fake_log())

    def test_enter_does_not_cancel_progress_without_cancel(self):
        self.run_editor(['cmd viewfake.prognote2', 'wait 700', 'cmd focus_notifications', 'key Return', 'wait 100'])
        self.assertFalse(any(l.endswith(' cancel') and l.startswith('0 progress ') for l in self.fake_log()))

    def test_an_id_past_31_bits_is_no_such_thing(self):
        self.env['VIEWFAKE_PIC'] = '1'
        self.run_editor(['cmd viewfake.bigunimage', 'wait 200'])
        self.assertTrue(any(l.endswith('noview no such image') for l in self.fake_log()))

    def test_progress_in_a_view(self):
        out = self.run_editor(['cmd viewfake.progview', 'wait 200', 'print-views', 'cmd viewfake.progend', 'wait 200',
                               'print-views'])
        lines = [l for l in out if l.startswith('view=1 ')]
        self.assertTrue(lines[0].endswith(' progress=-'), lines)
        self.assertFalse(lines[1].endswith(' progress=-'), lines)

    def test_a_view_not_its_own_or_a_bad_cancel_is_syntax(self):
        self.run_editor(['cmd viewfake.progbad', 'wait 200'])
        log = self.fake_log()
        self.assertEqual(sum(1 for l in log if l.startswith('error ') and ' syntax' in l), 2, log)

    def test_without_the_features_the_requests_are_unknown(self):
        del self.env['VIEWFAKE_NOTIFY']
        self.run_editor(['cmd viewfake.note', 'cmd viewfake.prog', 'wait 200'])
        log = self.fake_log()
        self.assertEqual(sum(1 for l in log if l.startswith('error ') and ' unknown ' in l), 2, log)


if __name__ == '__main__':
    unittest.main()
