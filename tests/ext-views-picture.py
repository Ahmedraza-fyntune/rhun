#!/usr/bin/env python3
"""Pictures with the keyboard and images (features view-keys and view-images), driven headlessly
with the viewfake extension: a picture view in the panel, a 12a tab picture, keys, typed text,
the clipboard commands, modifiers on pointer events, double clicks, decoded images by handle."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from viewsharness import ViewsBase  # noqa: E402

PIC = 4                 # the picture view's number: todo 1, items 2, logs 3


class Pictures(ViewsBase):
    def setUp(self):
        super().setUp()
        self.env['VIEWFAKE_PIC'] = '1'

    def body_xy(self, out, name='rhun-tests/viewfake.pic'):
        line = [l for l in out if l.startswith(name + ' ')][0]
        x, y = map(int, line.split(' at=')[1].split(' ')[0].split(','))
        return x, y

    def shown(self):
        out = self.run_editor(['view-show pic', 'wait 300', 'print-panel-tabs'])
        return self.body_xy(out)

    def test_a_picture_view_opens_draws_and_hears_the_pointer(self):
        x, y = self.shown()
        out = self.run_editor(['view-show pic', 'wait 300', f'click {x + 50} {y + 30}', 'wait 100', 'print-views'])
        self.assertTrue(any(l.startswith(f'view={PIC} title=View shapes=1 ') for l in out), out)
        log = self.fake_log()
        self.assertIn(f'0 view {PIC} open picture panel pic', log)
        self.assertTrue(any(l.startswith(f'0 view {PIC} size ') for l in log), log)
        self.assertIn(f'0 view {PIC} down 50 30 -', log)
        self.assertIn(f'0 view {PIC} click 50 30 -', log)
        self.assertIn(f'0 view {PIC} focus 1', log)

    def test_keys_and_text_go_to_the_picture_with_the_keyboard(self):
        x, y = self.shown()
        self.run_editor(['view-show pic', 'wait 300', f'click {x + 50} {y + 30}', 'type a', 'key shift+Return',
                         'key Insert', 'key ctrl+a', 'wait 100'])
        log = self.fake_log()
        i = log.index(f'0 view {PIC} key - a')
        self.assertEqual(log[i + 1:i + 3], [f'0 view {PIC} text 1', 'a'])
        self.assertIn(f'0 view {PIC} key shift Return', log)
        self.assertIn(f'0 view {PIC} key - Insert', log)    # F-keys have bindings
        self.assertIn(f'0 view {PIC} selectall', log)

    def test_paired_releases_and_window_focus_are_opt_in(self):
        self.env['VIEWFAKE_KEY_STATE'] = '1'
        x, y = self.shown()
        self.run_editor(['view-show pic', 'wait 300', f'click {x + 50} {y + 30}',
                         'key w', 'key-up w', 'focus out', 'focus in', 'wait 100'])
        log = self.fake_log()
        self.assertIn(f'0 view {PIC} key - w', log)
        self.assertIn(f'0 view {PIC} key-up - w', log)
        self.assertIn(f'0 view {PIC} focus 0', log)
        self.assertIn(f'0 view {PIC} focus 1', log)

    def test_legacy_picture_does_not_receive_key_releases(self):
        x, y = self.shown()
        self.run_editor(['view-show pic', 'wait 300', f'click {x + 50} {y + 30}',
                         'key w', 'key-up w', 'wait 100'])
        self.assertFalse(any(' key-up ' in line for line in self.fake_log()))

    def test_copy_asks_the_picture_and_paste_brings_text_to_it(self):
        (self.proj / 'note.txt').write_text('pasted words', encoding='utf-8')
        x, y = self.shown()
        out = self.run_editor(['view-show pic', 'wait 300', f'click {x + 50} {y + 30}', 'key ctrl+c', 'wait 300',
                               f'open {self.proj / "note.txt"}', 'key ctrl+End', 'key ctrl+v', 'wait 100', 'print-doc',
                               'key ctrl+a', 'key ctrl+c', 'view-show pic', f'click {x + 50} {y + 30}', 'key ctrl+v',
                               'wait 200'])
        self.assertIn('pasted wordscopied text', '\n'.join(out))
        log = self.fake_log()
        self.assertTrue(any(l.endswith(f' vcopy {PIC} copy') for l in log), log)
        i = len(log) - 1 - log[::-1].index(f'0 view {PIC} paste 23')
        self.assertEqual(log[i + 1], 'pasted wordscopied text')

    def test_a_double_click_and_modifiers(self):
        x, y = self.shown()
        self.run_editor(['view-show pic', 'wait 300', f'click {x + 20} {y + 20}', f'click {x + 20} {y + 20}',
                         'wait 100'])
        log = self.fake_log()
        self.assertIn(f'0 view {PIC} dblclick 20 20 -', log)

    def test_an_image_by_handle_is_drawn_and_goes(self):
        x, y = self.shown()
        shot = self.work / 'shot.ppm'
        out = self.run_editor(['view-show pic', 'wait 300', 'cmd viewfake.img', 'wait 400', f'shot {shot}',
                               'cmd viewfake.unimg', 'wait 300'])
        data = shot.read_bytes()
        # P6 header: "P6\nW H\n255\n"
        parts = data.split(b'\n', 3)
        w = int(parts[1].split()[0])
        px = parts[3]
        off = ((y + 20) * w + (x + 20)) * 3
        self.assertEqual(tuple(px[off:off + 3]), (255, 0, 0))
        log = self.fake_log()
        oks = [l for l in log if l.startswith('ok ')]
        self.assertTrue(any(l.startswith('error ') and l.endswith('noview no such image') for l in log), log)
        self.assertTrue(oks)

    def test_bad_images_and_the_limit(self):
        self.run_editor(['cmd viewfake.badimg', 'cmd viewfake.imgs65', 'wait 800'])
        log = self.fake_log()
        self.assertEqual(sum(1 for l in log if l.startswith('error ') and ' syntax' in l), 1, log)
        self.assertEqual(sum(1 for l in log if l.endswith('toobig 64 images or 128 MB')), 1, log)

    def test_a_tab_picture_takes_the_keyboard_when_pressed(self):
        out = self.run_editor(['cmd viewfake.tabpic', 'wait 400', 'print-views'])
        line = [l for l in out if l.startswith('view=5 ')][0]
        x, y = map(int, line.split(' at=')[1].split(','))
        out = self.run_editor(['cmd viewfake.tabpic', 'wait 400', f'click {x + 30} {y + 30}', 'type b',
                               'print-state'])
        self.assertIn('focus=10', [l for l in out if l.startswith('tabs=')][0])
        log = self.fake_log()
        self.assertIn('0 view 5 focus 1', log)
        self.assertIn('0 view 5 key - b', log)

    def test_a_chord_bound_to_cut_asks_the_picture(self):
        cfg = self.work / 'config/rhun/config'
        cfg.write_text(cfg.read_text() + '[keys]\nctrl+k ctrl+x = cut\n')
        (self.proj / 'note.txt').write_text('keep me', encoding='utf-8')
        x, y = self.shown()
        out = self.run_editor([f'open {self.proj / "note.txt"}', 'view-show pic', 'wait 300',
                               f'click {x + 50} {y + 30}', 'key ctrl+k', 'key ctrl+x', 'wait 300', 'print-doc'])
        self.assertIn('keep me', '\n'.join(out))   # the document under it is untouched
        self.assertTrue(any(l.endswith(f' vcopy {PIC} cut') for l in self.fake_log()), self.fake_log())

    def test_a_picture_view_takes_title_and_badge_patches(self):
        out = self.run_editor(['cmd viewfake.pictitle', 'wait 300', 'print-views', 'print-panel-tabs'])
        self.assertTrue(any(l.startswith(f'view={PIC} kind=picture') and ' title=Drawing badge=3 ' in l for l in out),
                        out)

    def test_without_view_keys_a_picture_hears_no_keys(self):
        self.env['VIEWFAKE_PIC'] = 'nokeys'
        x, y = self.shown()
        self.run_editor(['view-show pic', 'wait 300', f'click {x + 50} {y + 30}', 'type a', 'wait 100'])
        log = self.fake_log()
        self.assertIn(f'0 view {PIC} click 50 30', log)      # no modifiers either
        self.assertFalse(any(' key ' in l for l in log), log)


if __name__ == '__main__':
    unittest.main()
