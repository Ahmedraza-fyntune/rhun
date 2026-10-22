#!/usr/bin/env python3
"""Package an already built Windows editor as a portable ZIP."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text(encoding='utf-8').strip()
out = root / 'build/windows'
archive = out / f'rhun-{version}-windows-x86_64.zip'
files = [(out / 'rhun.exe', 'rhun.exe'), (out / 'rhun.com', 'rhun.com'),
         (root / 'LICENSE', 'LICENSE'),
         (root / 'assets/licenses/LICENSE-Unicode.txt', 'LICENSE-Unicode.txt'), (root / 'install.ps1', 'install.ps1')]
for path, _ in files:
    if not path.is_file():
        raise SystemExit(f'Missing {path}. Build the Windows editor first.')
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as package:
    for path, name in files:
        if name == 'LICENSE':
            # Older embedded updaters copy LICENSE but do not know the separate notice file.
            notice = (root / 'assets/licenses/LICENSE-Unicode.txt').read_bytes()
            package.writestr(f'rhun-{version}/{name}', path.read_bytes() + b'\n\nUnicode data notice\n\n' + notice)
        else:
            package.write(path, f'rhun-{version}/{name}')
print(archive)
