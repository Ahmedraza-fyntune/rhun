#!/usr/bin/env python3
"""Real HELLO, retained native channel after revocation, and child byte receipt."""
import argparse,importlib.util,os,re,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={'prehello-bound':102,'close-forgets':103,'corrupt-output':104}
def build(folder,windows=False,mutation=None):
 spec=importlib.util.spec_from_file_location('runtime_channel_native_builder',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 source=(ROOT/'tests/extension_lifecycle_test.s').read_text();a=source.index('    # Stop during preparation must close the gate before it can become READY.\n');z=source.index('    lea rdi, [rip + tek_ok]\n',a)
 source=source[:a]+'    call rcn_actual\n'+source[z:]
 old='lc_extension: .zero EXT_SIZE';assert source.count(old)==1;source=source.replace(old,'lc_extension: .zero RT_SLOT_COUNT * EXT_SIZE')
 old='    mov qword ptr [rip + g_exts + VEC_cap], 1';assert source.count(old)==1;source=source.replace(old,'    mov qword ptr [rip + g_exts + VEC_cap], RT_SLOT_COUNT')
 old='6:  mov edi, 1\n    lea rsi, [rip + tek_bytes]';assert source.count(old)==1;source=source.replace(old,'    call rcn_child_receipt\n'+old,1)
 source=source.replace('ok supervised extension lifecycle\\n','ok retained native runtime reply\\n')
 source=source.replace('.include "rhun.inc"','.include "rhun.inc"\n.include "app/extprepareretire.inc"\n.include "app/extruntimeservice.inc"',1)
 source+='\n'+(ROOT/'tests/runtime_channel_native_cases.inc').read_text()
 assert not re.search(r'(?m)^\s*\.section \.rodata\.',source)
 ext=(ROOT/'src/app/ext.s').read_text();assert ext.count('call ext_arm_plan')==1;ext=ext.replace('call ext_arm_plan','call rcn_defer_auto_arm',1)
 source+='\n.text\nFN rcn_defer_auto_arm\n    xor eax, eax\n    ret\n'
 replacements={'src/app/ext.s':ext}
 if mutation=='prehello-bound':
  path='src/app/extruntimesession.s';text=(ROOT/path).read_text();old='    cmp qword ptr [r14 + RTS_state], RTS_ACTIVE\n    jne .Lrs_bind_stale';assert text.count(old)==1;replacements[path]=text.replace(old,old+'\n    or qword ptr [r14 + RTS_flags], RTSF_CHANNEL_BOUND',1)
 if mutation=='close-forgets':
  path='src/app/extruntimeservice.s';text=(ROOT/path).read_text();old='    or qword ptr [r13 + RTS_flags], RTSF_STOP_REQUIRED | RTSF_PARSER_PAUSED';assert text.count(old)==1;replacements[path]=text.replace(old,old+'\n    and qword ptr [r13 + RTS_flags], ~RTSF_CHANNEL_BOUND',1)
 if mutation=='corrupt-output':
  path='src/app/extenqueue.s';text=(ROOT/path).read_text();assert text.count('call memcpy')==3;replacements[path]=text.replace('call memcpy','call rcn_corrupt_copy')
  source+='\n.text\nFN rcn_corrupt_copy\n    PROLOGUE\n    mov rbx, rdi\n    call memcpy\n    mov byte ptr [rbx], 120\n    EPILOGUE\n'
 return b.build(folder,source,replacements,windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--exe',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--mutation',choices=list(CODES));p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.wine and(not a.exe or not a.wine_drive_root):p.error('--wine requires exact --exe and --wine-drive-root')
 if a.exe and a.build_only:p.error('--exe and --build-only are exclusive')
 if a.negative_controls and(a.exe or a.mutation):p.error('negative controls build their own unambiguous variants')
 windows=os.name=='nt'or a.windows_build or bool(a.wine);drive=a.wine_drive_root.resolve()if a.wine else None
 def check(mutation):
  with tempfile.TemporaryDirectory(prefix='rhun-channel-native-',dir=drive)as temporary:
   base=Path(temporary).resolve();exe=a.exe or build(((a.build_only/mutation if mutation else a.build_only)if a.build_only else base/'bin'),windows,mutation)
   if a.build_only:print('built actual native channel',exe,flush=True);return
   root=base/'store';payload=root/'owner/name';payload.mkdir(parents=True);(root/'.change.lock').touch();lease=root/'.leases/legacy'/b'owner'.hex()/(b'name'.hex()+'.lock');lease.parent.mkdir(parents=True);lease.touch()
   state=base/'state';state.mkdir();home=base/'home';home.mkdir();(home/'approved').write_bytes(b'keeper')
   def arg(path):
    path=path.resolve()
    return('C:/'+path.relative_to(drive).as_posix()if drive else'Z:'+str(path))if a.wine else str(path)
   r=subprocess.run(([a.wine]if a.wine else[])+[arg(p)for p in [exe,root,payload,state,home]],cwd=ROOT,capture_output=True,timeout=90)
   assert r.returncode==CODES.get(mutation,0)and r.stdout+r.stderr==(b''if mutation else b'ok retained native runtime reply\n'),(mutation,r)
   if not mutation:assert(state/'channel-received').is_file()

  print('ok actual native channel '+(mutation or'baseline'),flush=True)
 for mutation in ([None,*CODES]if a.negative_controls else[a.mutation]):check(mutation)
if __name__=='__main__':main()
