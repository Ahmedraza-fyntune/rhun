#!/usr/bin/env python3
"""Actual startup source replacement, unchanged refresh and overflow refusal."""
import argparse,hashlib,importlib.util,os,re,shutil,struct,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={'replacement-epoch':231,'source-token':232,'future-source':233,'source-overflow':235,'pure-publication':236}
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine')
p.add_argument('--temp-root',type=Path);p.add_argument('--virtual-root')
p.add_argument('--mutation',choices=CODES);p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe')
if a.wine and (not a.exe or not a.temp_root or not a.virtual_root):p.error('Wine requires actual C drive paths')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')
def build(folder,mutation=None):
 spec=importlib.util.spec_from_file_location('initial_build',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 fixture=(ROOT/'tests/ext_settings_service_worker_cases.inc').read_text().replace('.include "ext_settings_service_worker_faults.inc"',(ROOT/'tests/ext_settings_service_worker_faults.inc').read_text())
 old='cmp rax, 15\n    ja svw_fail';assert fixture.count(old)==1;fixture=fixture.replace(old,'cmp rax, 18\n    ja svw_fail')
 old='    cmp qword ptr [rip + svw_mode], 1\n    je .Lsvw_cleanup';assert fixture.count(old)==1
 fixture=fixture.replace(old,'    cmp qword ptr [rip + svw_mode], 16\n    jb 6f\n    call svi_initial_replace\n    jmp .Lsvw_cleanup\n6:  cmp qword ptr [rip + svw_mode], 1\n    je .Lsvw_cleanup')
 fixture+='\n'+(ROOT/'tests/ext_settings_service_initial_cases.inc').read_text()
 for label in ('FN svwf_memory_try\n','FN svwf_memory_free\n','FN ext_settings_native_start\n'):
  assert fixture.count(label)==1
  fixture=fixture.replace(label,label+'    cmp qword ptr [rip + svi_pure], 0\n    jne svi_pure_fail\n')
 replacements={}
 def change(path,old,new):
  text=replacements.get(path,(ROOT/path).read_text());assert text.count(old)==1,(path,old,text.count(old));replacements[path]=text.replace(old,new)
 change('src/app/extsettingsmemory.s','FN ext_settings_memory_try\n','FN ext_settings_memory_try\n    jmp svwf_memory_try\nFN svwf_memory_try_real\n')
 change('src/app/extsettingsmemory.s','FN ext_settings_memory_free\n','FN ext_settings_memory_free\n    jmp svwf_memory_free\nFN svwf_memory_free_real\n')
 change('src/app/extsettingsnative.s','FN ext_settings_native_start\n','FN svwf_native_start_real\n')
 change('src/app/extsettingsjob.s','FN ext_settings_job_command\n','FN svwf_job_command_real\n')
 change('src/app/extsettingsworkercommit.s','    mov qword ptr [rbx + SW_state], SW_COMMITTED\n','    call svwf_after_commit\n    mov qword ptr [rbx + SW_state], SW_COMMITTED\n')
 if windows:change('src/win/sys.s','    API VirtualFree\n','    call svwf_native_unmap\n')
 else:change('src/mem.s','    SYS SYS_munmap\n','    call svwf_native_unmap\n')
 if mutation=='replacement-epoch':change('src/app/extsettingsservicefinish.s','    inc qword ptr [rbx + SV_source_epoch]\n','')
 if mutation=='source-token':change('src/app/extsettingsservicesource.s','    cmp [rbx + SV_source], r12\n    jne .Lsvs_check_stale\n    cmp [rbx + SV_source_epoch], r13\n    jne .Lsvs_check_stale\n','')
 if mutation=='future-source':change('src/app/extsettingsserviceinitial.s','    cmp [r14 + ELM_source], r12\n    jne .Lsvic_stale\n','')
 if mutation=='source-overflow':change('src/app/extsettingsservicefinish.s','    cmp [rbx + SV_source_epoch], rax\n    jae .Lsvf_overflow\n','')
 if mutation=='pure-publication':change('src/app/extsettingsserviceinitial.s','FN ext_settings_service_initial_publish\n','FN ext_settings_service_initial_publish\n    PROLOGUE\n    mov edi, 32\n    call ext_settings_memory_try\n    EPILOGUE\n')
 # Preserve PE subsection identities by refusing suffix-bearing fixture overrides.
 for text in [fixture,*replacements.values()]:assert not re.search(r'(?m)^\s*\.section \.rodata[^\s\n]',text)
 return b.build(folder,fixture,replacements,windows=windows)
if a.negative_controls:
 for m in CODES:subprocess.run([sys.executable,__file__,'--mutation',m],check=True)
 sys.exit(0)
with tempfile.TemporaryDirectory(prefix='rhun-initial-fixture-') as td:
 exe=a.exe if a.exe and not a.build_only else build(Path(td),a.mutation)
 if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(exe,a.exe);print('built initial service fixture',a.exe);sys.exit(0)
 with tempfile.TemporaryDirectory(prefix='rhun-initial-',dir=a.temp_root) as rd:
  root=Path(rd).resolve();cfg=root/'space 雪 cfg';cfg.mkdir();ini=cfg/'extensions.ini'
  native=str(a.virtual_root).rstrip('/')+'/'+root.name+'/'+cfg.name if a.virtual_root else str(cfg)
  original=b'; retained\n[owner/tool]\npinned=no\nsetting.unknown=stay\n[providers]\ncomplete.py=other/tool\n'
  changed=b'; changed outside\n[external/tool]\nsetting.opaque=changed\n'
  for mode in ((18,) if a.mutation=='source-overflow' else (16,) if a.mutation else (16,17,18)):
   ini.write_bytes(original)
   result=subprocess.run(([a.wine] if a.wine else [])+[str(exe),native,str(mode),str(len(original)),hashlib.sha256(original).hexdigest()],capture_output=True,timeout=40)
   if a.mutation:
    assert result.returncode==CODES[a.mutation],(a.mutation,result.returncode,result.stdout,result.stderr)
    print('ok initial semantic negative',a.mutation,flush=True);continue
   assert result.returncode==0 and len(result.stdout)==64 and not result.stderr,(mode,result.returncode,result.stdout,result.stderr)
   values=struct.unpack('<8q',result.stdout);assert values==((2 if mode==16 else 1 if mode==17 else 0x7fffffffffffffff),0,0,0,0,0,0,0),(mode,values)
   assert ini.read_bytes()==(original if mode==17 else changed),(mode,values)
   print('ok actual scheduled initial source',mode,values,flush=True)
