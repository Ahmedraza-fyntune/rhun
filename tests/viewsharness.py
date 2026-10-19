"""The harness of the retained-view tests (tests/ext-views-*.py): a project, an isolated HOME and
config, rhun headless with the viewfake extension (tests/ext/viewfake.py, tests/ext/views), the
fake's log and the rows of print-view."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
EXTS = ROOT / 'tests/ext/views'

CONFIG = ('[ui]\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')


class ViewsBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-views-', ignore_cleanup_errors=True)  # shells may still write
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        (self.proj / 'src').mkdir(parents=True)
        (self.proj / 'src/main.rs').write_text('fn main() {\n    // TODO: parse\n}\n', encoding='utf-8')
        (self.proj / 'src/lib.rs').write_text('// TODO: lib\n', encoding='utf-8')
        (self.proj / 'README.md').write_text('# TODO\n', encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.log = self.work / 'state/rhun/extensions/rhun-tests--viewfake/vf.log'
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(),
                        VIEWFAKE_LOG=self.log.as_posix(), VIEWFAKE_ROOT=self.proj.as_posix())
        self.env.pop('VIEWFAKE_MODE', None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, actions, mode=None, exts=EXTS, start=True):
        env = dict(self.env)
        if mode:
            env['VIEWFAKE_MODE'] = mode
        pre = ['wait 100', 'wait-ext viewfake running', 'wait 200', 'wait 100'] if start else ['wait 100']
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join([*pre, *actions, 'quit']) + '\n', encoding='utf-8')
        args = [str(EXE), self.proj.as_posix(), '--headless', '1000x600', '--scale', '1']
        if exts:
            args += ['--extensions', str(exts)]
        result = subprocess.run(args + ['--script', script.as_posix()], env=env, capture_output=True,
                                timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return [l for l in result.stdout.decode('utf-8', errors='replace').splitlines()
                if not l.startswith('ext=')]

    def fake_log(self):
        return self.log.read_bytes().decode('utf-8', 'replace').splitlines() if self.log.exists() else []

    def rows(self, out, view='todo'):
        """The row lines of a print-view in out (after its at= line)."""
        rows, on = [], False
        for line in out:
            if line.startswith('at='):
                on = True
                self.view_x = int(line[3:].split(',')[0])
                continue
            if on and line.startswith('row '):
                rows.append(line)
            elif on:
                break
        return rows

    def row_xy(self, rows, ident):
        for r in rows:
            if f' id={ident} ' in r + ' ':
                y = int(r.split(' y=')[1].split(' ')[0])
                return getattr(self, 'view_x', 0) + 120, y + 10
        self.fail(f'no row {ident} in {rows}')

