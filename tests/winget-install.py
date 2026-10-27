#!/usr/bin/env python3
"""Install the packaged ZIP with winget from tools/winget-manifests.py's manifests, as winget-pkgs
would: the rhun-VERSION folder on PATH runs rhun.com, rhun.exe is beside it, and uninstalling takes
both away. Needs winget with local manifests allowed (the windows workflow sets that up)."""
import functools
import http.server
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import winreg

ROOT = Path(__file__).resolve().parent.parent
if os.name != 'nt':
    raise SystemExit('Run the winget test on Windows.')
VERSION = (ROOT / 'VERSION').read_text(encoding='utf-8').strip()
OUT = ROOT / 'build/windows'
ZIP = OUT / f'rhun-{VERSION}-windows-x86_64.zip'
FOLDER = f'rhun-{VERSION}'


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class Server(http.server.ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        pass                    # winget closes its probing connections early


def winget(*arguments, check=True):
    result = subprocess.run(['winget', *arguments, '--disable-interactivity'], capture_output=True,
                            text=True, encoding='utf-8', errors='replace', timeout=600)
    print(result.stdout.strip(), flush=True)
    if check and result.returncode:
        raise SystemExit(f'winget {arguments[0]} exited {result.returncode:#x}: {result.stderr}')
    return result


def user_path():
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, 'Environment') as key:
        return winreg.QueryValueEx(key, 'Path')[0].split(';')


server = Server(('127.0.0.1', 0), functools.partial(Handler, directory=OUT))
threading.Thread(target=server.serve_forever, daemon=True).start()
with tempfile.TemporaryDirectory(prefix='rhun-winget-') as temporary:
    temp = Path(temporary)
    made = subprocess.run([sys.executable, str(ROOT / 'tools/winget-manifests.py'), str(ZIP), str(temp),
                           '--url', f'http://127.0.0.1:{server.server_port}/{ZIP.name}'],
                          capture_output=True, text=True, check=True)
    manifests = Path(made.stdout.strip())
    winget('validate', '--manifest', str(manifests))
    print('ok   winget/manifests-validate', flush=True)
    winget('install', '--manifest', str(manifests), '--accept-package-agreements', '--accept-source-agreements')
    try:
        folders = [Path(entry) for entry in user_path() if entry.rstrip('\\').endswith('\\' + FOLDER)]
        assert len(folders) == 1, user_path()
        folder = folders[0]
        assert 'WinGet\\Packages\\rhun.rhun_' in str(folder), folder
        assert (folder / 'rhun.exe').is_file() and (folder / 'rhun.com').is_file(), list(folder.iterdir())
        env = dict(os.environ, XDG_CONFIG_HOME=str(temp / 'config'), XDG_STATE_HOME=str(temp / 'state'),
                   HOME=str(temp / 'home'), PATH=str(folder) + ';' + os.environ['PATH'])
        # `rhun` as a terminal finds it: PATHEXT puts .COM first
        version = subprocess.run(['cmd', '/d', '/c', 'rhun --version'], env=env, capture_output=True,
                                 text=True, check=True, timeout=30, cwd=temp).stdout.strip()
        assert version == f'rhun {VERSION}', version
        print('ok   winget/installs-on-path', flush=True)
        # installed from a local manifest, it is known by name, not by a source's id
        listed = winget('list', '--name', 'rhun', '--exact', '--accept-source-agreements')
        assert VERSION in listed.stdout, listed.stdout
        print('ok   winget/lists-the-version', flush=True)
    finally:
        winget('uninstall', '--manifest', str(manifests), check=False)
    assert not any(entry.rstrip('\\').endswith('\\' + FOLDER) for entry in user_path()), user_path()
    assert not folder.exists(), folder
    print('ok   winget/uninstalls', flush=True)
server.shutdown()
