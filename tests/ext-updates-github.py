#!/usr/bin/env python3
"""Extension updates against github.com itself (network): rhun-editor/showcase installed at v0.1.0,
the update check finding v0.1.2 (through GitHub's /releases/latest redirect until
rhun-editor/extensions publishes its index, then from the index), the update, Roll back to 0.1.0
(automatic updates then leave v0.1.2 alone) and the update again. Each run gets its own HOME.
SHOTS=DIR keeps screenshots of the details page with its Update and Roll back buttons."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')


class GitHubUpdates(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-updates-github-')
        self.work = Path(self.tmp.name).resolve()
        (self.work / 'proj').mkdir()
        (self.work / 'proj/a.txt').write_text('hello\n', encoding='utf-8')
        cfg = self.work / 'config/rhun'
        cfg.mkdir(parents=True)
        (cfg / 'config').write_text(CONFIG, encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(), XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix())
        self.env.pop('RHUN_EXT_BASE', None)
        self.shots = os.environ.get('SHOTS')

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, lines, env=None):
        script = self.work / 'script.rsc'
        script.write_text('\n'.join(['wait 100', *lines, 'quit']) + '\n', encoding='utf-8')
        r = subprocess.run([str(EXE), (self.work / 'proj').as_posix(), '--headless', '1100x800', '--scale', '1',
                            '--script', script.as_posix()], env=env or self.env, capture_output=True, timeout=600)
        self.assertEqual(r.returncode, 0, r.stderr.decode(errors='replace')[-2000:])
        return [l for l in r.stdout.decode('utf-8', errors='replace').splitlines() if not l.startswith('ext=')]

    def shot(self, name):
        return ['shot ' + (Path(self.shots) / name).as_posix()] if self.shots else []

    def test_install_update_roll_back_and_update_again(self):
        out = self.run_editor(['ext-install rhun-editor/showcase@0.1.0', 'wait-install', 'print-dialog', 'dialog yes',
                               'wait-ext showcase running', 'print-ext-versions showcase'])
        self.assertEqual(out[0], 'install=asking')
        self.assertEqual(out[1], 'dialog=Add “Showcase”?')
        self.assertTrue(out[2].startswith('text=Version 0.1.0 from github.com/rhun-editor/showcase. It can '), out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=- link=no fresh=0', out)

        out = self.run_editor(['wait-ext showcase running', 'ext-check-updates', 'wait-ext-updates',
                               'print-ext-updates', 'cmd extensions', 'ext-page showcase', 'wait 300',
                               *self.shot('showcase-update.ppm')])
        line = [l for l in out if l.startswith('rhun-editor/showcase ')][0]
        self.assertRegex(line, r'^rhun-editor/showcase installed=0\.1\.0 latest=0\.1\.(\d+) state=available '
                               r'from=(github|index)$')
        reviewed = line.endswith('from=index')
        print('update source:', 'the rhun extensions index' if reviewed else "GitHub's latest-release redirect",
              file=sys.stderr)

        # 0.1.0 -> 0.1.2 adds only an icon and a color: no new access, so only an unreviewed version asks
        steps = ['wait-ext showcase running', 'ext-update showcase', 'wait-ext-updates', 'print-dialog']
        if not reviewed:
            steps += ['dialog yes', 'wait-ext-updates']
        out = self.run_editor(steps + ['wait-ext showcase running', 'print-ext-versions showcase', 'print-toast'])
        if reviewed:
            self.assertIn('dialog=none', out)
        else:
            self.assertIn('dialog=Update “Showcase” to 0.1.2?', out)
            self.assertIn('text=Not in the rhun extensions index: nobody has reviewed this version.', out)
        self.assertIn('version=0.1.2 source=github tag=v0.1.2 previous=0.1.0 link=no fresh=0', out)

        out = self.run_editor(['wait-ext showcase running', 'cmd extensions', 'ext-page showcase', 'wait 300',
                               *self.shot('showcase-rollback.ppm'), 'ext-rollback showcase',
                               'wait-ext showcase running', 'print-toast', 'print-ext-versions showcase'])
        self.assertIn('toast=Rolled back Showcase to 0.1.0', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=0.1.2 link=no fresh=0', out)
        state = (self.work / 'state/rhun/extension-updates').read_text(encoding='utf-8')
        self.assertIn('skip = v0.1.2', state)

        # automatic updates (install mode, checking every half second) leave the version rolled back from
        env = dict(self.env, RHUN_EXT_UPDATE_EVERY='500')
        out = self.run_editor(['wait-ext showcase running', 'wait 2000', 'wait-ext-updates', 'print-ext-updates',
                               'print-ext-versions showcase'], env=env)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=0.1.2 link=no fresh=0', out)
        self.assertTrue(any(l.startswith('rhun-editor/showcase installed=0.1.0 latest=0.1.2 state=skipped')
                            for l in out), out)

        steps = ['wait-ext showcase running', 'ext-update showcase', 'wait-ext-updates', 'print-dialog']
        if not reviewed:
            steps += ['dialog yes', 'wait-ext-updates']
        out = self.run_editor(steps + ['wait-ext showcase running', 'print-ext-versions showcase'])
        self.assertIn('version=0.1.2 source=github tag=v0.1.2 previous=0.1.0 link=no fresh=0', out)


if __name__ == '__main__':
    unittest.main()
