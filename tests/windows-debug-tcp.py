#!/usr/bin/env python3
"""Windows: a debug adapter reached over TCP (src/win/sock.s under dapwire.s). launch.ini's
`server = HOST:PORT` and `server = PORT` connect rhun.com to tests/dap/fakedap.py, which already
listens on 127.0.0.1 (a debug server the user started), and the session runs from its entry stop to
the program's end; with nobody listening the session waits in `connecting` until it is stopped.
--wine runs rhun.com under Wine with the adapter as a Linux process: Wine's sockets are the host's,
and the adapter opens the Z: paths rhun sends through a Z: link in its working folder."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/windows'
CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
# a debugger-only extension: with `server` set nothing is started
EXTENSION = ('name = debugtcp\nowner = rhun-tests\ntitle = Debug TCP\ndescription = A fake debugger.\n'
             'version = 0.0.1\nprotocol = 1\n\n[needs]\ndebug = yes\n\n[debugger.fake]\n'
             'title = Fake Debugger\nlanguages = C\nprogram = python3\nargs = -I fakedap.py\n'
             'attr.program = path\nattr.stopOnEntry = bool\n')

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--wine', metavar='WINE64')
args = parser.parse_args()
failures = []


def winpath(path):
    value = os.path.abspath(path).replace('\\', '/')
    return 'Z:' + value if args.wine else value


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
    s.close()
    return port


def session(out, n):
    return [line for line in out if line.startswith('session=')][n]


def field(line, name):
    for part in line.split(' '):
        if part.startswith(name + '='):
            return part[len(name) + 1:]
    return None


def run_case(work, name, server, port, listen):
    case = work / name
    proj = case / 'proj'
    (proj / '.rhun').mkdir(parents=True)
    (proj / 'a.c').write_text('int main(void) {\n    return 3;\n}\n', encoding='utf-8')
    a = winpath(proj / 'a.c')
    steps = [{'file': a, 'line': 1, 'function': 'main', 'locals': {}},
             {'file': a, 'line': 2, 'function': 'main', 'locals': {}, 'output': 'sum 3\n'}]
    (proj / 'scenario.json').write_text(json.dumps({'steps': steps, 'exitCode': 3}), encoding='utf-8')
    (proj / '.rhun/launch.ini').write_text(
        '[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = true\nserver = %s\n' % server,
        encoding='utf-8')
    config = case / 'config/rhun/config'
    config.parent.mkdir(parents=True)
    config.write_text(CONFIG, encoding='utf-8')
    ext = case / 'exts/rhun-tests/debugtcp/extension.ini'
    ext.parent.mkdir(parents=True)
    ext.write_text(EXTENSION, encoding='utf-8')
    log = case / 'fakedap.log'
    env = dict(os.environ, FAKEDAP_LOG=str(log), WINEDEBUG='-all',
               XDG_CONFIG_HOME=winpath(case / 'config'), XDG_STATE_HOME=winpath(case / 'state'),
               XDG_DATA_HOME=winpath(case / 'data'))
    env.pop('FAKEDAP_MODE', None)
    adapter = None
    if listen:
        cwd = case / 'adapter'
        cwd.mkdir()
        if args.wine:
            os.symlink('/', cwd / 'Z:')
        adapter = subprocess.Popen([sys.executable, '-I', str(ROOT / 'tests/dap/fakedap.py'),
                                    '--listen', '127.0.0.1:%d' % port],
                                   cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        adapter.stdout.readline()       # listening
    if listen:
        actions = ['debug-start Run', 'print-dialog', 'wait-debug paused 10000', 'print-debug',
                   'debug-continue', 'wait-debug ended 10000', 'print-debug', 'print-console']
    else:
        actions = ['debug-start Run', 'wait 300', 'print-debug', 'debug-stop', 'wait-debug ended 2000',
                   'print-debug']
    script = case / 'actions.rsc'
    script.write_text('\n'.join(['wait 100', 'open ' + a, *actions, 'quit']) + '\n', encoding='utf-8')
    try:
        result = subprocess.run([*([args.wine] if args.wine else []), str(OUT / 'rhun.com'), winpath(proj),
                                 '--headless', '1000x600', '--scale', '1', '--extensions', winpath(case / 'exts'),
                                 '--script', winpath(script)],
                                env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    finally:
        if adapter:
            adapter.kill()
            adapter.wait()
            adapter.stdout.close()
    out = result.stdout.decode('utf-8', errors='replace').replace('\r', '').splitlines()
    assert result.returncode == 0, (result.returncode, result.stderr[-2000:])
    if not listen:
        assert field(session(out, 0), 'state') == 'connecting', out
        assert field(session(out, 1), 'state') == 'ended', out
        assert field(session(out, 1), 'reason') == 'stopped', out
        return
    assert 'dialog=none' in out, out           # nothing runs, so nothing is asked
    assert field(session(out, 0), 'state') == 'paused', out
    assert field(session(out, 0), 'reason') == 'entry', out
    assert field(session(out, 1), 'state') == 'ended', out
    assert field(session(out, 1), 'exit') == '3', out
    assert 'stdout sum 3' in out, out
    lines = log.read_text(encoding='utf-8', errors='replace').splitlines()
    assert 'accepted' in lines, lines
    assert any(line.startswith('< disconnect') for line in lines), lines


OUT.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='rhun-debug-tcp-', dir=OUT) as temporary:
    work = Path(temporary).resolve()
    for name, server, listen in (('host-port', '127.0.0.1:%d', True), ('port', '%d', True),
                                 ('nobody-listening', '%d', False)):
        port = free_port()
        try:
            run_case(work, name, server % port, port, listen)
            print('ok   debug-tcp/' + name, flush=True)
        except Exception as error:
            failures.append(name)
            print('FAIL debug-tcp/%s: %r' % (name, error), flush=True)
sys.exit(1 if failures else 0)
