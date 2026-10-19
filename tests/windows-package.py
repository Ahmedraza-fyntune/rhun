#!/usr/bin/env python3
"""Portable ZIP contents include the Unicode data notice."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp)
    (root/'tools').mkdir();(root/'build/windows').mkdir(parents=True)
    (root/'assets/licenses').mkdir(parents=True)
    shutil.copyfile(ROOT/'tools/package-windows.py',root/'tools/package-windows.py')
    (root/'VERSION').write_text('0.18.0\n')
    expected={'rhun.exe':b'editor','rhun.com':b'launcher','LICENSE':b'project license',
              'LICENSE-Unicode.txt':b'Unicode license','install.ps1':b'installer'}
    for name,data in expected.items():
        target=root/('build/windows/'+name if name in ('rhun.exe','rhun.com') else 'assets/licenses/'+name if name=='LICENSE-Unicode.txt' else name)
        target.write_bytes(data)
    expected['LICENSE'] += b'\n\nUnicode data notice\n\n'+expected['LICENSE-Unicode.txt']
    subprocess.run([sys.executable,str(root/'tools/package-windows.py')],check=True,stdout=subprocess.DEVNULL)
    with zipfile.ZipFile(root/'build/windows/rhun-0.18.0-windows-x86_64.zip') as z:
        assert set(z.namelist())=={'rhun-0.18.0/'+name for name in expected}
        for name,data in expected.items():assert z.read('rhun-0.18.0/'+name)==data
        # The outgoing updater's four-file extraction still retains the data notice.
        old_files={name:z.read('rhun-0.18.0/'+name) for name in ('rhun.exe','rhun.com','LICENSE','install.ps1')}
        assert old_files['LICENSE'].endswith(expected['LICENSE-Unicode.txt'])
print('ok   windows-package/unicode-license')
