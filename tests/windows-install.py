#!/usr/bin/env python3
"""Exercise the Windows installer against local, checksum-verified release fixtures."""
import functools
import hashlib
import http.server
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parent.parent
if os.name != 'nt':
    raise SystemExit('Run installer tests on Windows.')
VERSION = (ROOT / 'VERSION').read_text(encoding='utf-8').strip()
ASSET = f'rhun-{VERSION}-windows-x86_64.zip'


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(prefix='rhun-installer-') as temporary:
    temp = Path(temporary)
    release = temp / 'releases' / 'download' / ('v' + VERSION)
    release.mkdir(parents=True)
    latest = temp / 'releases/latest/download'
    latest.mkdir(parents=True)
    (latest / 'VERSION').write_text(VERSION + '\n')
    shutil.copyfile(ROOT / 'build/windows' / ASSET, release / ASSET)
    digest = hashlib.sha256((release / ASSET).read_bytes()).hexdigest()
    checksums = release / 'SHA256SUMS'
    checksums.write_text(f'{digest}  {ASSET}\n')
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=temp))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    destination = temp / 'Program files café' / 'rhun'
    url = f'http://127.0.0.1:{server.server_port}/releases'
    before_path = subprocess.check_output(['powershell.exe', '-NoProfile', '-Command',
        "[Environment]::GetEnvironmentVariable('Path', 'User')"])

    def install(*options, success=True, target=destination):
        result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', str(ROOT / 'install.ps1'), '-InstallDir', str(target), '-ReleasesUrl', url,
            '-NoModifyPath', '-NoShortcut', *options], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=60)
        assert (result.returncode == 0) == success, result.stdout.decode(errors='replace')
        return result

    def version():
        assert subprocess.check_output([str(destination / 'rhun.com'), '--version']).strip() == ('rhun ' + VERSION).encode()

    try:
        install()  # latest lookup and first install, including a Unicode destination
        version()
        assert (destination / '.rhun-install').is_file()
        install('-Version', VERSION)
        version()
        print('ok   install/latest-version-and-reinstall', flush=True)
        checksums.write_text(f'{"0" * 64}  {ASSET}\n')
        install(success=False)
        version()
        checksums.write_text(f'{digest}  {ASSET}\n')
        print('ok   install/checksum-failure-preserves-installation', flush=True)
        unrelated = destination / 'personal.txt'
        unrelated.write_bytes(b'keep this')
        install(success=False)
        install('-Uninstall', success=False)
        assert unrelated.read_bytes() == b'keep this'
        version()
        unrelated.unlink()
        arbitrary = temp / 'unrelated'
        arbitrary.mkdir()
        (arbitrary / 'data').write_bytes(b'keep this too')
        install(target=arbitrary, success=False)
        assert (arbitrary / 'data').read_bytes() == b'keep this too'
        print('ok   install/unrelated-files-preserved', flush=True)
        script = temp / 'running.rsc'
        script.write_text('print-state\nwait 30000\nquit\n')
        process = subprocess.Popen([str(destination / 'rhun.com'), str(temp), '--headless', '800x600',
            '--script', str(script)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            env=dict(os.environ, XDG_CONFIG_HOME=str(temp / 'config'), XDG_STATE_HOME=str(temp / 'state')))
        try:
            ready = []
            reader = threading.Thread(target=lambda: ready.append(process.stdout.readline()), daemon=True)
            reader.start()
            reader.join(timeout=10)
            assert ready and ready[0].startswith(b'tabs='), 'editor did not become ready'
            refusal = install(success=False)
            assert b'Close rhun before updating' in refusal.stdout, refusal.stdout
            assert process.poll() is None
        finally:
            process.kill()
            process.wait()
        print('ok   install/running-editor-preserved', flush=True)
        install('-Uninstall')
        assert not destination.exists()
        leftovers = list(destination.parent.glob('.rhun-*'))
        assert not leftovers, f'staging or backup directories leaked: {leftovers}'
        after_path = subprocess.check_output(['powershell.exe', '-NoProfile', '-Command',
            "[Environment]::GetEnvironmentVariable('Path', 'User')"])
        assert before_path == after_path, 'NoModifyPath changed the user PATH'
        print('ok   install/uninstall-and-no-modify-path', flush=True)
    finally:
        server.shutdown()
        server.server_close()
