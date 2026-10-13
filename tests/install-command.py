#!/usr/bin/env python3
"""The Windows install command is the same wherever it is shown (tests/windows-install.py runs the README's)."""
import html
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
COMMAND = r'powershell -NoProfile -ExecutionPolicy Bypass -Command "[^"\n]*install\.ps1[^"\n]*"'
EXPECTED = {'README.md': 1, 'docs/guide.md': 1, 'site/index.html': 2, 'site/docs/getting-started.html': 1}

shown = {}
for name, count in EXPECTED.items():
    text = (ROOT / name).read_text(encoding='utf-8')
    if name.endswith('.html'):
        text = html.unescape(text)
    found = re.findall(COMMAND, text)
    assert len(found) == count, f'{name}: {len(found)} Windows install commands, expected {count}'
    shown.update((command, name) for command in found)
assert len(shown) == 1, 'the Windows install commands differ:\n' + '\n'.join(f'{n}: {c}' for c, n in shown.items())
print('ok   install-command/same-everywhere', flush=True)
# Windows PowerShell reads a script without a BOM in the ANSI code page, whether pasted or run with -File.
assert (ROOT / 'install.ps1').read_bytes().isascii(), 'install.ps1 is not ASCII'
print('ok   install-command/ascii-installer', flush=True)
