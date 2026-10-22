#!/usr/bin/env python3
"""Notice persistence and staged-update transactions in scratch directories.

PowerShell fixtures reuse the installer's application block with platform entry
checks replaced. Windows CI also exercises the unchanged full entry point.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parent.parent
PWSH=shutil.which('pwsh') or shutil.which('powershell.exe')
if not PWSH and (ROOT/'build/powershell/pwsh').is_file():PWSH=str(ROOT/'build/powershell/pwsh')

class Notices(unittest.TestCase):
    @unittest.skipIf(os.name=='nt' or getattr(os,'geteuid',lambda:0)()==0,'requires POSIX non-root permissions')
    def test_portable_linux_notice_with_readonly_parent(self):
        source=(ROOT/'install.sh').read_text()
        a=source.index('place_binary() {');b=source.index('\n}\n',a)+3
        function=source[a:b]
        for dirname in ('portable','bin'):
            with self.subTest(dirname=dirname),tempfile.TemporaryDirectory() as tmp:
                work=Path(tmp);parent=work/'readonly';target_dir=parent/dirname
                target_dir.mkdir(parents=True);target=target_dir/'rhun';target.write_bytes(b'old binary')
                archive=work/'archive';(archive/'bin').mkdir(parents=True)
                (archive/'bin/rhun').write_bytes(b'new binary')
                (archive/'LICENSE-Unicode.txt').write_bytes(b'Unicode notice')
                parent.chmod(0o555)
                try:
                    result=subprocess.run(['sh','-eu','-c',function+'\nplace_binary "$1"','fixture',str(target)],env=dict(os.environ,src=str(archive)),capture_output=True)
                    self.assertEqual(result.returncode,0,result.stderr.decode())
                    self.assertEqual(target.read_bytes(),b'new binary')
                    self.assertEqual((target_dir/'rhun-LICENSE-Unicode.txt').read_bytes(),b'Unicode notice')
                finally:parent.chmod(0o755)
    @unittest.skipUnless(PWSH,'PowerShell unavailable')
    def test_staged_update_receipts_and_notice_rollback(self):
        original=(ROOT/'install.ps1').read_text()
        # Only adapt the OS entry gate and platform-specific shell locations.
        a=original.index("if ($env:OS -ne 'Windows_NT'");b=original.index('$InstallDir = [IO.Path]',a)
        source=original[:a]+original[b:]
        source=source.replace("$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'rhun.lnk'","$shortcut = Join-Path $InstallDir 'fixture.lnk'")
        source=source.replace("$associationRoot = 'HKCU:\\Software'","$associationRoot = Join-Path $InstallDir 'fixture-registry'")
        failure='''function Move-Item {
param([string]$LiteralPath,[string]$Destination)
if ($env:RHUN_NOTICE_MOVE_FAIL -eq '1' -and $LiteralPath -eq (Join-Path $UpdateStage 'LICENSE-Unicode.txt')) { throw 'notice move failed' }
Microsoft.PowerShell.Management\\Move-Item @PSBoundParameters
}
'''
        for case in ('legacy','notice','missing','unrecorded','tampered','rollback'):
            with self.subTest(case=case),tempfile.TemporaryDirectory() as tmp:
                work=Path(tmp);target=work/'rhun';target.mkdir();stage=work/'.rhun-update-2147483647';stage.mkdir()
                installer=work/'fixture.ps1';installer.write_text(source.replace('if ($ApplyUpdate) {',failure+'if ($ApplyUpdate) {',1),encoding='utf-8-sig')
                names=['rhun.exe','rhun.com','LICENSE','install.ps1']
                if case!='legacy':names.append('LICENSE-Unicode.txt')
                old={name:('old '+name).encode() for name in names}
                hashes={}
                for name in names:
                    (target/name).write_bytes(old[name]);data=('new '+name).encode();(stage/name).write_bytes(data)
                    hashes[name]=hashlib.sha256(data).hexdigest()
                if case=='missing':(stage/'LICENSE-Unicode.txt').unlink()
                if case=='unrecorded':del hashes['LICENSE-Unicode.txt']
                if case=='tampered':(stage/'LICENSE-Unicode.txt').write_bytes(b'tampered')
                (stage/'update.json').write_text(json.dumps({'target':str(target),'version':'1.0.0','hashes':hashes}))
                env=dict(os.environ,LOCALAPPDATA=str(work),RHUN_NOTICE_MOVE_FAIL='1' if case=='rollback' else '0')
                result=subprocess.run([PWSH,'-NoLogo','-NoProfile','-File',str(installer),'-ApplyUpdate','-Version','1.0.0',
                    '-InstallDir',str(target),'-UpdateStage',str(stage),'-WaitPid','2147483647','-NoModifyPath','-NoShortcut','-NoFileAssociations','-NoUrlScheme'],env=env,capture_output=True,timeout=30)
                succeeds=case in ('legacy','notice')
                self.assertEqual(result.returncode==0,succeeds,result.stdout.decode(errors='replace')+result.stderr.decode(errors='replace'))
                for name in names:self.assertEqual((target/name).read_bytes(),('new '+name).encode() if succeeds else old[name])
                self.assertEqual(stage.exists(),not succeeds)

if __name__=='__main__':unittest.main()
