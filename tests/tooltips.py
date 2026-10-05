#!/usr/bin/env python3
"""Hover tooltips: the delay, what hides them, the setting, and no redraw while idle."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()

# 1280x800 at scale 1: a button, and the strip below it where its tooltip appears
TERMINAL = (1040, 20, (960, 40, 1140, 80))
SETTINGS = (1112, 20, (1020, 40, 1200, 80))
EXPLORER_NEW = (162, 60, (72, 82, 272, 112))
EXPLORER_NEW_FOLDER = (190, 60, (100, 82, 300, 112))
# the branch at the left end of the status bar (774 to 800): its tooltip is above it
STATUS_BRANCH = (40, 787, (0, 740, 300, 772))
AWAY = (640, 400)


@unittest.skipIf(os.name == 'nt', 'the control socket is Unix only')
class Tooltips(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-tips-', dir='/tmp')
        self.work = Path(self.tmp.name).resolve()
        self.project = self.work / 'project'
        self.project.mkdir()
        (self.project / 'file.txt').write_text('text\n', encoding='utf-8')
        self.config = self.work / 'config/rhun/config'
        self.config.parent.mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'))
        self.process = self.client = self.reader = None

    def tearDown(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
            self.process.wait(timeout=10)
            self.process.stderr.close()
        for closable in (self.reader, self.client):
            if closable is not None:
                closable.close()
        self.tmp.cleanup()

    def start(self, tooltips=None):
        setting = '' if tooltips is None else f'tooltips = {str(tooltips).lower()}\n'
        self.config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                               '[updates]\ncheck = false\n[git]\nenabled = false\n'
                               '[editor]\ncursor_blink = false\n'
                               '[ui]\nagents_panel = false\n' + setting, encoding='utf-8')
        control = self.work / 'control'
        self.process = subprocess.Popen([str(EXE), str(self.project), '--headless', '1280x800',
                                         '--scale', '1', '--control', str(control)], env=self.env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.client.settimeout(10)
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
        self.command('wait 150')
        self.command('open ' + str(self.project / 'file.txt'))

    def command(self, line):
        self.client.sendall((line + '\n').encode('utf-8'))
        output = []
        while True:
            reply = self.reader.readline()
            if reply == 'ok\n':
                return ''.join(output)
            self.assertNotIn(reply, ('', 'error\n'), line)
            output.append(reply)

    def strip(self, box, name):
        path = self.work / (name + '.ppm')
        self.command('shot ' + str(path))
        magic, size, maximum, pixels = path.read_bytes().split(b'\n', 3)
        width = int(size.split()[0])
        x0, y0, x1, y1 = box
        return b''.join(pixels[(y * width + x0) * 3:(y * width + x1) * 3] for y in range(y0, y1))

    def hover(self, button, wait):
        """The strip under the button before hovering, and after hovering for wait ms."""
        x, y, box = button
        self.command('move %d %d' % AWAY)
        self.command('wait 60')
        before = self.strip(box, 'before')
        self.command(f'move {x} {y}')
        self.command(f'wait {wait}')
        return before, self.strip(box, 'after')

    def test_appears_after_the_delay_for_title_bar_and_explorer(self):
        self.start()
        for button in (TERMINAL, SETTINGS, EXPLORER_NEW, EXPLORER_NEW_FOLDER):
            before, early = self.hover(button, 200)
            self.assertEqual(before, early, button)
            self.command('wait 500')
            self.assertNotEqual(before, self.strip(button[2], 'late'), button)

    def test_status_bar_branch_shows_it_above(self):
        (self.project / '.git').mkdir()
        (self.project / '.git' / 'HEAD').write_text('ref: refs/heads/topic\n', encoding='utf-8')
        self.start()
        before, early = self.hover(STATUS_BRANCH, 200)
        self.assertEqual(before, early)
        self.command('wait 500')
        self.assertNotEqual(before, self.strip(STATUS_BRANCH[2], 'late'))

    def test_leaving_and_pressing_hide_it(self):
        self.start()
        before, shown = self.hover(TERMINAL, 700)
        self.assertNotEqual(before, shown)
        self.command('move %d %d' % AWAY)
        self.command('wait 30')
        self.assertEqual(before, self.strip(TERMINAL[2], 'left'))
        # a press hides it while the button is held
        before, shown = self.hover(SETTINGS, 700)
        self.assertNotEqual(before, shown)
        self.command('down')
        self.command('wait 700')
        self.assertEqual(before, self.strip(SETTINGS[2], 'pressed'))
        self.command('move %d %d' % AWAY)
        self.command('up')
        self.command('key Escape')

    def test_a_key_press_dismisses_it_until_another_button(self):
        self.start()
        self.command('move %d %d' % AWAY)
        self.command('wait 60')
        settings_hidden = self.strip(SETTINGS[2], 'settings-hidden')
        before, shown = self.hover(TERMINAL, 700)
        self.assertNotEqual(before, shown)
        self.command('type x')
        self.command('wait 900')
        self.assertEqual(before, self.strip(TERMINAL[2], 'typed'))
        # the next button gets its tooltip again
        x, y, box = SETTINGS
        self.command(f'move {x} {y}')
        self.command('wait 700')
        self.assertNotEqual(settings_hidden, self.strip(box, 'settings-shown'))

    def test_the_setting_turns_them_off(self):
        self.start(tooltips=False)
        for button in (TERMINAL, EXPLORER_NEW):
            before, after = self.hover(button, 700)
            self.assertEqual(before, after, button)

    def test_no_frames_while_shown_and_idle(self):
        self.start()
        self.hover(TERMINAL, 700)
        self.command('print-frames')
        self.command('wait 600')
        self.assertEqual(self.command('print-frames'), 'frames=0\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
