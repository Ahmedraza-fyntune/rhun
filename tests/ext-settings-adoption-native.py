#!/usr/bin/env python3
"""Real ordinary settings service and isolated helper, scheduled at public cadence."""
import argparse,hashlib,importlib.util,os,re,shutil,struct,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine')
p.add_argument('--temp-root',type=Path);p.add_argument('--virtual-root')
p.add_argument('--mutation',choices=['oldmodel-release','retired-charge','early-charge'])
p.add_argument('--negative-controls',action='store_true')
a=p.parse_args()
CODES={'oldmodel-release':248,'retired-charge':249,'early-charge':245}
if a.build_only and not a.exe:p.error('--build-only requires --exe')
if a.wine and (not a.exe or not a.temp_root or not a.virtual_root):p.error('Wine requires --exe, --temp-root, --virtual-root on actual C drive')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')
def build(folder,mutation=None):
 spec=importlib.util.spec_from_file_location('service_worker_build',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 fixture=(ROOT/'tests/ext_settings_service_worker_cases.inc').read_text().replace('.include "ext_settings_service_worker_faults.inc"', (ROOT/'tests/ext_settings_service_worker_faults.inc').read_text())
 fixture=fixture.replace('    call svw_put\n.Lsvw_save:', '    call svw_put\n    call sva_put_extra\n.Lsvw_save:',1)
 old='    mov rdi, [rbx + SV_queue]\n    cmp qword ptr [rdi + EQ_count], 1'
 assert fixture.count(old)==1
 fixture=fixture.replace(old,'    mov rdi, [rbx + SV_queue]\n    cmp qword ptr [rdi + EQ_count], 2')
 fixture+='\n'+(ROOT/'tests/ext_settings_adoption_empty_cases.inc').read_text()
 old='    mov rdi, r12\n    call ext_settings_adoption_release\n    test rax, rax\n    jnz svw_fail'
 assert fixture.count(old)==1
 fixture=fixture.replace(old,'    mov rax, [r12 + AP_oldmodel]\n    mov rax, [rax + ELM_providers]\n    test rax, rax\n    jz svw_fail\n    cmp qword ptr [rax - 32], 64\n    jb svw_fail\n    mov rdx, [rax - 16]\n    mov [rip + svaf_charge], rdx\n    sub rax, 32\n    mov [rip + svaf_target], rax\n'+old)
 fixture=fixture.replace('    call ext_settings_model_gc\n','    call svaf_model_gc\n')
 fixture+='\n'+(ROOT/'tests/ext_settings_adoption_native_cases.inc').read_text()
 old='FN svwf_native_unmap\n'
 assert fixture.count(old)==1
 fixture=fixture.replace(old,old+"    cmp qword ptr [rip + svaf_failed], 0\n    jne 7f\n.ifdef WINDOWS\n    cmp [rip + svaf_target], rcx\n.else\n    cmp [rip + svaf_target], rdi\n.endif\n    jne 7f\n    call svaf_boundary\n    mov qword ptr [rip + svaf_failed], 1\n.ifdef WINDOWS\n    mov ecx, 1\n.else\n    mov edi, 1\n.endif\n7:\n")

 old='    cmp rdx, -16\n    jne svw_fail\n    jmp .Lsvw_cleanup'
 assert fixture.count(old)==1
 fixture=fixture.replace(old,'    cmp rdx, -16\n    jne svw_fail\n    call sva_apply_empty\n    call svaf_verify_retained\n    jmp .Lsvw_cleanup')
 for label in ('FN svwf_memory_try\n','FN svwf_memory_free\n','FN ext_settings_native_start\n'):
  assert fixture.count(label)==1
  fixture=fixture.replace(label,label+'    cmp qword ptr [rip + sva_pure], 0\n    jne sva_pure_fail\n')
 replacements={}
 def change(path,old,new):
  text=replacements.get(path,(ROOT/path).read_text());assert text.count(old)==1,(path,old,text.count(old));replacements[path]=text.replace(old,new)
 change('src/app/extsettingsmemory.s','FN ext_settings_memory_try\n','FN svwf_memory_try_real\n')
 change('src/app/extsettingsnative.s','FN ext_settings_native_start\n','FN svwf_native_start_real\n')
 change('src/app/extsettingsjob.s','FN ext_settings_job_command\n','FN svwf_job_command_real\n')
 change('src/app/extsettingsworkercommit.s','    mov qword ptr [rbx + SW_state], SW_COMMITTED\n','    call svwf_after_commit\n    mov qword ptr [rbx + SW_state], SW_COMMITTED\n')
 change('src/app/extsettingsmemory.s','FN ext_settings_memory_free\n','FN ext_settings_memory_free\n    jmp svwf_memory_free\nFN svwf_memory_free_real\n')
 # All normal callers enter the fixed fixture wrapper. Native implementation stays real.
 change('src/app/extsettingsmemory.s','FN svwf_memory_try_real\n','FN ext_settings_memory_try\n    jmp svwf_memory_try\nFN svwf_memory_try_real\n')
 if windows:change('src/win/sys.s','    API VirtualFree\n','    call svwf_native_unmap\n')
 else:change('src/mem.s','    SYS SYS_munmap\n','    call svwf_native_unmap\n')
 if mutation=='oldmodel-release':change('src/app/extsettingsadoptiongc.s','    call ext_settings_model_release\n','    xor eax, eax\n')
 if mutation=='retired-charge':change('src/app/extsettingsmemory.s','    add [rip + esm_retired_bytes], rsi\n','')
 if mutation=='early-charge':change('src/app/extsettingsmemory.s','.Lesm_free_retained:\n','.Lesm_free_retained:\n    sub [rip + esm_charge], r12\n')
 # Preserve PE subsection identities by refusing suffix-bearing fixture overrides.
 for text in [fixture,*replacements.values()]:assert not re.search(r'(?m)^\s*\.section \.rodata[^\s\n]',text)
 return b.build(folder,fixture,replacements,windows=windows)
if a.negative_controls:
 for mutation in CODES:subprocess.run([sys.executable,__file__,'--mutation',mutation],check=True)
 sys.exit(0)
with tempfile.TemporaryDirectory(prefix='rhun-service-worker-fixture-') as td:
 e=a.exe if a.exe and not a.build_only else build(Path(td),a.mutation)
 if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(e,a.exe);print('built actual service worker '+str(a.exe));sys.exit(0)
 with tempfile.TemporaryDirectory(prefix='rhun-svc-real-',dir=a.temp_root) as rd:
  root=Path(rd).resolve();cfg=root/'space 雪 cfg';cfg.mkdir();ini=cfg/'extensions.ini'
  native=str(a.virtual_root).rstrip('/')+'/'+root.name+'/'+cfg.name if a.virtual_root else str(cfg)
  original=b'; retained\n[owner/tool]\npinned=no\nsetting.unknown=stay\n[providers]\ncomplete.py=other/tool\n'
  for size in ((len(original),) if a.mutation else (len(original),1048000)):
   content=b'[broken\n' if size==8 else original if size==len(original) else original+b';'+b'x'*(size-len(original)-2)+b'\n'
   for mode in (2,):
    ini.write_bytes(content)
    r=subprocess.run(([a.wine] if a.wine else [])+[str(e),native,str(mode),str(len(content)),hashlib.sha256(content).hexdigest()],capture_output=True,timeout=40)
    if a.mutation:
     assert r.returncode==CODES[a.mutation],(a.mutation,r.returncode,r.stdout,r.stderr)
     print('ok exact service negative control '+a.mutation,flush=True);continue
    assert r.returncode==0 and len(r.stdout)==64 and not r.stderr,(mode,size,r.returncode,r.stdout[:200],struct.unpack('<8q',r.stderr) if len(r.stderr)==64 else r.stderr[:2000])
    result=struct.unpack('<8q',r.stdout)
    assert result[:4]==((2,1,1,3) if mode==2 else (0,0,0,0) if mode in (6,12,13,15) else (1,1,0,0) if mode==11 else (1,0,0,1) if mode==9 else (1,0,0,0) if mode in (1,3,4,10) else (1,1,1,2)),(mode,size,result)
    assert result[5]==(1 if mode==9 else 0),(mode,size,result)
    assert ini.read_bytes()==(b'; changed outside\n[external/tool]\nsetting.opaque=changed\n' if mode==11 else content if mode in (1,3,4,6,10,12,13,15) else content.replace(b'pinned=no',b'pinned=yes').replace(b'setting.unknown=stay',b'setting.unknown=saved')),(mode,size,result)
    print('ok actual scheduled SVC worker',mode,size,result,flush=True)
