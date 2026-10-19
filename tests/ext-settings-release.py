import argparse,importlib.util,os,pathlib,shutil,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--exe',type=pathlib.Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--negative-controls',action='store_true');p.add_argument('--mutation',choices=['early-charge','drop-owner','budget1']);a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe')
if a.negative_controls and (a.exe or a.build_only or a.mutation):p.error('--negative-controls builds its own native fixtures')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')

def build(folder,mutation=None):
 spec=importlib.util.spec_from_file_location('settings_release_build',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 names=['extsettingsmemory','extsettingsjobcommon','extsettingsjobframes','extsettingsjobstep','extsettingssnapshot','extsettingsqueue']
 replacements={'src/app/'+name+'.s':(ROOT/'src/app'/(name+'.s')).read_text() for name in names}
 memory=replacements['src/app/extsettingsmemory.s'];assert memory.count('call time_ms')==3;memory=memory.replace('call time_ms','call esmr_time')
 if mutation=='early-charge':
  old='    mov rdi, rbx\n    call prep_cleanup_free\n    test rdx, rdx\n    jz .Lesm_free_retained';assert memory.count(old)==1
  memory=memory.replace(old,'    sub [rip + esm_charge], r12\n'+old)
  old='    sub [rip + esm_charge], r12\n    xor eax, eax';assert memory.count(old)==1;memory=memory.replace(old,'    xor eax, eax')
 elif mutation=='drop-owner':
  old='    call esm_append_retired\n    test r14, r14';assert memory.count(old)==1;memory=memory.replace(old,'    nop\n    test r14, r14')
 elif mutation=='budget1':
  old='    test r12, r12\n    jz .Lesbg_return';s=replacements['src/app/extsettingssnapshot.s'];assert s.count(old)==1;replacements['src/app/extsettingssnapshot.s']=s.replace(old,'    cmp r12, 2\n    jb .Lesbg_return')
 replacements['src/app/extsettingsmemory.s']=memory
 fixture=(ROOT/'tests/ext_settings_release_test.s').read_text();mem=(ROOT/'src/mem.s').read_text();assert mem.count('.Lmf_large:\n')==1;mem=mem.replace('.Lmf_large:\n','.Lmf_large:\n    inc qword ptr [rip + esmr_unmap_calls]\n',1)
 if windows:
  native=(ROOT/'src/win/sys.s').read_text();assert native.count('API VirtualFree')==1;native=native.replace('API VirtualFree','call esmr_native_virtual_free',1);replacements['src/win/sys.s']=native
  fixture+='\nFN esmr_native_virtual_free\n    cmp qword ptr [rip + esmr_fail_unmap], 0\n    je 1f\n    dec qword ptr [rip + esmr_fail_unmap]\n    mov ecx, 1\n1:  jmp [rip + __imp_VirtualFree]\n'
 else:
  assert mem.count('SYS SYS_munmap')==1;mem=mem.replace('SYS SYS_munmap','call esmr_native_unmap',1)
  fixture+='\nFN esmr_native_unmap\n    cmp qword ptr [rip + esmr_fail_unmap], 0\n    je 1f\n    dec qword ptr [rip + esmr_fail_unmap]\n    mov edi, 1\n1:  SYS SYS_munmap\n    ret\n'
 replacements['src/mem.s']=mem
 return b.build(folder,fixture,replacements,windows=windows)

def check(exe,mutation=None):
 command=[a.wine,'Z:'+exe.resolve().as_posix()] if a.wine else [str(exe.resolve())]
 r=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=40)
 if mutation:assert r.returncode==({'early-charge':81,'drop-owner':81,'budget1':82}[mutation]),(mutation,r.returncode,r.stdout,r.stderr)
 else:assert r.returncode==0 and r.stdout==b'ok checked settings release ownership and retry\n' and not r.stderr,(r.returncode,r.stdout,r.stderr)

with tempfile.TemporaryDirectory(prefix='rhun-settings-release-') as temporary:
 folder=pathlib.Path(temporary)
 if a.negative_controls:
  check(build(folder/'baseline'))
  for mutation in ['early-charge','drop-owner','budget1']:
   check(build(folder/mutation,mutation),mutation);print('ok settings release negative control '+mutation,flush=True)
 else:
  exe=a.exe.resolve() if a.exe and not a.build_only else build(folder,a.mutation)
  if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(exe,a.exe);print('built checked settings release fixture',flush=True);sys.exit(0)
  check(exe,a.mutation)
  print('ok checked settings release ownership and retry',flush=True)
