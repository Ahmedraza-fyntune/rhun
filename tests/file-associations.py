#!/usr/bin/env python3
"""Verify installer choices and registration without changing the user's associations."""
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(ROOT / 'tools/file-associations.py'), '--check'], check=True)
plist = plistlib.loads((ROOT / 'assets/mac/Info.plist').read_bytes())
assert all('public.data' not in d.get('LSItemContentTypes', []) for d in plist['CFBundleDocumentTypes'])
source = next(d for d in plist['CFBundleDocumentTypes'] if d['CFBundleTypeName'] == 'Source and configuration')
assert 'LSItemContentTypes' not in source
assert {'txt', 'md', 'py', 'rs', 'json', 'ts', 'yaml'} <= set(source['CFBundleTypeExtensions'])
assert not {'png', 'jpg', 'gif', 'qoi'} & set(source['CFBundleTypeExtensions'])
images = next(d for d in plist['CFBundleDocumentTypes'] if d['CFBundleTypeName'] == 'Image extensions')
assert 'qoi' in images['CFBundleTypeExtensions']
print('ok   associations/metadata', flush=True)

if os.name == 'nt':
    script = (ROOT / 'install.ps1').read_text()
    functions = script.split('# BEGIN FILE ASSOCIATION FUNCTIONS\n', 1)[1].split('# END FILE ASSOCIATION FUNCTIONS', 1)[0]
    # Registry tests use a temporary subtree, never the user's actual associations.
    tests = r'''
$ErrorActionPreference = 'Stop'
$associationRoot = 'HKCU:\Software\rhun-association-test-' + [Guid]::NewGuid().ToString('N')
$InstallDir = "C:\Program files café ' $ &\rhun"
$NoFileAssociations = $false
$NoMakeDefault = $false
$MakeDefault = $false
$openedSettings = @()
function Start-Process($FilePath) { $script:openedSettings += $FilePath }
function Read-Host { throw 'The installer must not prompt for defaults' }
function Notify-FileAssociations { } # No shell refresh for the test registry subtree.
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
    Set-AssociationValue "$associationRoot\Classes\.txt" '(default)' 'Other.Text'
    Set-AssociationValue "$associationRoot\Classes\.txt\OpenWithProgids" 'Other.Text' ''
    Set-AssociationValue "$associationRoot\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.txt\UserChoice" 'ProgId' 'Other.Text'
    Register-FileAssociations
    $command = Get-ItemPropertyValue -LiteralPath "$associationRoot\Classes\rhun.Text\shell\open\command" -Name '(default)'
    Assert ($command -ceq ('"' + (Join-Path $InstallDir 'rhun.exe') + '" "%1"')) 'Command quoting failed'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\Classes\.txt" -Name '(default)') -eq 'Other.Text') 'Existing default changed'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.txt\UserChoice" -Name 'ProgId') -eq 'Other.Text') 'UserChoice changed'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\rhun\Capabilities\FileAssociations" -Name '.md') -eq 'rhun.Text') 'Text registration missing'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\rhun\Capabilities\FileAssociations" -Name '.qoi') -eq 'rhun.Image') 'Image registration missing'
    $instructions = Choose-DefaultEditor | Out-String
    Assert ($openedSettings.Count -eq 0) 'Opened Settings without a manual request'
    Assert ($instructions.Contains('-ExecutionPolicy Bypass -File')) 'Manual command missing'
    Assert ($instructions.Contains('Optional: default editor')) 'Manual command heading missing'
    Assert ($instructions.Contains($InstallDir.Replace("'", "''"))) 'Manual command path quoting failed'
    $MakeDefault = $true
    Choose-DefaultEditor | Out-Null
    Assert ($openedSettings.Count -eq 1) 'Manual request did not open Settings'
    Register-FileAssociations
    $InstallDir = 'C:\Other rhun'
    Remove-FileAssociations
    Assert (Test-Path -LiteralPath "$associationRoot\Classes\rhun.Text") 'Removed another installation registration'
    $InstallDir = "C:\Program files café ' $ &\rhun"
    Remove-FileAssociations
    Assert (-not (Test-Path -LiteralPath "$associationRoot\Classes\rhun.Text")) 'ProgID left behind'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\Classes\.txt\OpenWithProgids" -Name 'Other.Text') -eq '') 'Removed another handler'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\Classes\.txt" -Name '(default)') -eq 'Other.Text') 'Uninstall changed another default'
    $NoFileAssociations = $true
    Register-FileAssociations
    Assert (-not (Test-Path -LiteralPath "$associationRoot\Classes\rhun.Text")) 'Opt-out ignored'
    'ok   associations/windows-register-preserve-defaults-and-uninstall'
} finally {
    if (Test-Path -LiteralPath $associationRoot) { Remove-Item -LiteralPath $associationRoot -Recurse -Force }
}
'''
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'associations.ps1'
        path.write_text(functions + '\n' + tests, encoding='utf-8-sig')
        subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(path)], check=True)
    raise SystemExit(0)

import errno
import fcntl
import pty
import select
import termios
import time

with tempfile.TemporaryDirectory(prefix='rhun-associations-') as directory:
    temp = Path(directory)
    home = temp / 'home café'
    prefix = home / '.local'
    shim = temp / 'shim'
    shim.mkdir()
    (prefix / 'bin').mkdir(parents=True)
    executable = prefix / 'bin/rhun'
    executable.write_text('#!/bin/sh\nexit 0\n')
    executable.chmod(0o755)
    desktop = prefix / 'share/applications/rhun.desktop'
    desktop.parent.mkdir(parents=True)
    desktop.write_bytes((ROOT / 'assets/rhun.desktop').read_bytes())
    installer = temp / 'install.sh'
    installer.write_text(re.sub(r'^LSREGISTER=.*$', 'LSREGISTER=/nonexistent', (ROOT / 'install.sh').read_text(), flags=re.M))
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
               XDG_DATA_HOME=str(prefix / 'share'), XDG_DATA_DIRS='/usr/share',
               PATH=str(shim) + ':' + os.environ['PATH'], RHUN_ASSOC_TEST=str(temp),
               RHUN_RELEASES_URL='file:///nonexistent')
    for name, content in {
        'uname': '#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo x86_64;; esac\n',
        'xdg-mime': '''#!/bin/sh
printf '%s\n' "$*" >> "$RHUN_ASSOC_TEST/calls"
case "$1" in
 default) printf '%s' "$2" > "$RHUN_ASSOC_TEST/default";;
 query) cat "$RHUN_ASSOC_TEST/default";;
esac
''',
        'update-desktop-database': '#!/bin/sh\nexit 0\n',
        'gtk-update-icon-cache': '#!/bin/sh\nexit 0\n',
        'xdg-desktop-menu': '#!/bin/sh\nexit 0\n',
        'osascript': '#!/bin/sh\nprintf "%s\\n" "$@" > "$RHUN_ASSOC_TEST/mac-args"\ncat > "$RHUN_ASSOC_TEST/mac-script"\n',
        'curl': '#!/bin/sh\ncat "$RHUN_ASSOC_TEST/install.sh"\n',
    }.items():
        path = shim / name
        path.write_text(content)
        path.chmod(0o755)

    def run(*options, success=True):
        result = subprocess.run(['sh', str(installer), '--configure-files', *options], env=env,
                                stdin=subprocess.DEVNULL, capture_output=True, timeout=15)
        assert (result.returncode == 0) == success, result.stderr.decode()
        assert b'Downloading' not in result.stderr
        return result.stderr

    run('--no-make-default')
    assert not (temp / 'calls').exists()
    output = run()
    assert not (temp / 'calls').exists()

    def run_printed_command(output):
        commands = [line.strip().decode() for line in output.splitlines() if line.startswith(b'  curl -fsSL ')]
        assert len(commands) == 1, output
        result = subprocess.run(['sh', '-c', commands[0]], env=env, stdin=subprocess.DEVNULL,
                                capture_output=True, timeout=15)
        assert result.returncode == 0, result.stderr.decode()
        return result.stderr

    output = run_printed_command(output)
    calls = (temp / 'calls').read_text().splitlines()
    defaults = [line.split() for line in calls if line.startswith('default ')]
    assert len(defaults) == 1 and defaults[0][1] == 'rhun.desktop', calls
    assert {'text/plain', 'application/json'} <= set(defaults[0][2:])
    assert not any('image/' in line or 'inode/' in line for line in calls)
    assert not {'text/html', 'application/xhtml+xml'} & set(defaults[0][2:]), defaults
    assert b'rhun is the default editor' in output
    print('ok   associations/linux-opt-in-and-configure-without-download', flush=True)
    (temp / 'calls').unlink()
    output = run('--make-default', '--prefix', str(home / 'elsewhere'), success=False)
    assert not (temp / 'calls').exists()
    # Failure is reported without pretending the desktop accepted the change.
    (shim / 'xdg-mime').write_text('#!/bin/sh\nexit 1\n')
    output = run('--make-default')
    assert b'Some default associations were not changed' in output
    print('ok   associations/missing-install-and-desktop-failure', flush=True)

    result = subprocess.run(['sh', str(installer), '--make-default'], env=env,
                            stdin=subprocess.DEVNULL, capture_output=True, timeout=15)
    assert result.returncode != 0 and b'requires --configure-files' in result.stderr, result.stderr
    assert b'Downloading' not in result.stderr
    print('ok   associations/install-cannot-change-defaults', flush=True)

    # A piped installer with a terminal still prints instructions without asking for input.
    master, slave = pty.openpty()
    def terminal_session():
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    process = subprocess.Popen(['sh', '-s', '--', '--configure-files'], env=env,
                               stdin=subprocess.PIPE, stdout=slave, stderr=slave,
                               preexec_fn=terminal_session)
    os.close(slave)
    process.stdin.write(installer.read_bytes())
    process.stdin.close()
    output = bytearray()
    deadline = time.monotonic() + 15
    try:
        while time.monotonic() < deadline:
            if not select.select([master], [], [], .1)[0]:
                continue
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            output.extend(chunk)
        assert process.wait(timeout=5) == 0, output
        assert b'[y/N]' not in output and b'--configure-files --make-default' in output, output
        assert not (temp / 'calls').exists()
    finally:
        os.close(master)
        if process.poll() is None:
            process.kill()
            process.wait()
    print('ok   associations/piped-installer-no-terminal-prompt', flush=True)

    # Mac requests use argument data and the bundle ID, never interpolated script code.
    (shim / 'uname').write_text('#!/bin/sh\ncase "$1" in -s) echo Darwin;; -m) echo arm64;; esac\n')
    appdir = home / "Apps ' $ &"
    (appdir / 'rhun.app').mkdir(parents=True)
    run('--app-dir', str(appdir), '--no-make-default')
    assert not (temp / 'mac-args').exists()
    output = run('--app-dir', str(appdir))
    assert not (temp / 'mac-args').exists()
    run_printed_command(output)
    args = (temp / 'mac-args').read_text().splitlines()
    assert args[:3] == ['-l', 'JavaScript', '-']
    assert args[3] == str(appdir / 'rhun.app')
    assert {'txt', 'md', 'py'} <= set(args[4].split())
    assert 'LSSetDefaultRoleHandlerForContentType' in (temp / 'mac-script').read_text()
    (shim / 'osascript').write_text('#!/bin/sh\nexit 1\n')
    output = run('--app-dir', str(appdir), '--make-default')
    assert b'Some defaults could not be changed' in output
    print('ok   associations/mac-opt-in-arguments-and-failure', flush=True)

subprocess.run([sys.executable, str(ROOT / 'tests/mac-defaults.py')], check=True)
