#!/usr/bin/env python3
"""Shared harness for the debugger's host tests (tests/debug-*.py): a project with a fake program,
launch.ini, the fake debugger extension (tests/dap/exts) whose adapter is tests/dap/fakedap.py,
and headless rhun runs isolated in their own HOME and XDG folders."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
EXTS = ROOT / 'tests/dap/exts'
CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')

C_SOURCE = '''int add(int a, int b) {
    int s = a + b;
    return s;
}
int main(void) {
    int total = 0;
    for (int i = 0; i < 3; i++)
        total = add(total, i);
    return 3;
}
'''


class DebugHost(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-dbg-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        self.src = self.proj / 'a.c'
        self.src.write_text(C_SOURCE, encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.log = self.work / 'fakedap.log'
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(),
                        XDG_DATA_HOME=(self.work / 'data').as_posix(),
                        FAKEDAP_LOG=self.log.as_posix())
        self.env.pop('FAKEDAP_MODE', None)

    def tearDown(self):
        self.tmp.cleanup()

    def steps(self):
        """The default scenario: main calls add three times, then returns 3."""
        a = self.src.as_posix()
        steps = [{'file': a, 'line': 6, 'function': 'main', 'locals': {'total': 0}}]
        total = 0
        for i in range(3):
            steps.append({'file': a, 'line': 8, 'function': 'main', 'locals': {'total': total, 'i': i}})
            main = {'function': 'main', 'file': a, 'line': 8, 'locals': {'total': total, 'i': i}}
            stack = [{'function': 'add', 'file': a, 'line': 2}, main]
            steps.append({'file': a, 'line': 2, 'function': 'add', 'depth': 2, 'stack': stack,
                          'locals': {'a': total, 'b': i}})
            stack = [{'function': 'add', 'file': a, 'line': 3}, main]
            steps.append({'file': a, 'line': 3, 'function': 'add', 'depth': 2, 'stack': stack,
                          'locals': {'a': total, 'b': i, 's': total + i},
                          'output': 'i=%d total=%d\n' % (i, total)})
            total += i
        steps.append({'file': a, 'line': 9, 'function': 'main',
                      'locals': {'total': total, 'p': {'x': 1, 'y': [1, 2], 'name': 'pt'}}})
        return steps

    def scenario(self, steps=None, exit_code=3, name='scenario.json'):
        path = self.proj / name
        path.write_text(json.dumps({'steps': self.steps() if steps is None else steps,
                                    'exitCode': exit_code}), encoding='utf-8')
        return path

    def launch_ini(self, text=None):
        if text is None:
            self.scenario()
            text = '[Run]\ntype = fake\nprogram = scenario.json\n'
        ini = self.proj / '.rhun/launch.ini'
        ini.parent.mkdir(exist_ok=True)
        ini.write_text(text, encoding='utf-8')
        return ini

    def run_editor(self, actions, mode=None, files=('a.c',), exts=EXTS, timeout=60, project=True):
        env = dict(self.env)
        if mode:
            env['FAKEDAP_MODE'] = mode
        opens = ['open ' + (self.proj / name).as_posix() for name in files]
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', *opens, *actions, 'quit']) + '\n', encoding='utf-8')
        args = [str(EXE)]
        if project:
            args.append(self.proj.as_posix())
        args += ['--headless', '1000x600', '--scale', '1', '--extensions', str(exts),
                 '--script', script.as_posix()]
        result = subprocess.run(args, env=env, capture_output=True, timeout=timeout)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        self.stderr = result.stderr.decode('utf-8', errors='replace')
        return result.stdout.decode('utf-8', errors='replace').splitlines()

    def start(self, name='Run', run=False):
        """debug-start and the first-time approval"""
        return [('debug-run ' if run else 'debug-start ') + name, 'dialog yes']

    def dap_log(self):
        if not self.log.exists():
            return []
        return self.log.read_text(encoding='utf-8', errors='replace').splitlines()

    def requests(self):
        return [line[2:] for line in self.dap_log() if line.startswith('< ')]

    def args_sent(self):
        for line in self.dap_log():
            if line.startswith('ARGS '):
                return json.loads(line[5:])
        return None

    def debug_lines(self, out):
        return [line for line in out if line.startswith('session=')]

    def field(self, line, name):
        for part in line.split(' '):
            if part.startswith(name + '='):
                return part[len(name) + 1:]
        return None
