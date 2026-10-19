#!/usr/bin/env python3
"""Actual configuration reload and owned snapshot/copy failure gates."""
import argparse,importlib.util,os,re,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
EXPECTED=b'ok owned keyline snapshots and reload lifetimes\n'
MUTATIONS={
 'missing-invalidation':('normal',82), 'ignore-epoch':('normal',82),
 'poison-ready':('normal',82), 'alias-source':('normal',81),
 'continue-after-allocation':('normal',81), 'unbounded-copy':('limits',91),
 'append-empty':('limits',91), 'write-refused-output':('contracts',100),
 'retain-wrap':('contracts',100), 'ignore-loading':('contracts',101),
 'epoch-wrap':('contracts',102), 'ignore-destination':('contracts',103),
 'allow-nul':('contracts',104),
}
def build(folder,windows=False,limits=False,contracts=False,mutation=None,addon_suffix=None,extra_sources=None):
 spec=importlib.util.spec_from_file_location('ksi_fixture_builder',ROOT/'tests/command-generation-build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 extra={path.relative_to(ROOT).as_posix():path.read_text()for path in sorted((ROOT/'src/app').glob('keyline*.s'))}
 extra['src/app/config.s']=(ROOT/'src/app/config.s').read_text()
 extra['src/app/commandgenerationkeycopy.s']=(ROOT/'src/app/commandgenerationkeycopy.s').read_text()
 extra['src/app/keylinesource.s']+='\n.text\nFN ksti_seed_epoch\n    mov [rip + key_source_epoch], rdi\n    ret\n'
 def change(path,old,new):
  source=extra.get(path,(ROOT/path).read_text());assert source.count(old)==1,(mutation,path,old);extra[path]=source.replace(old,new,1)
 if mutation=='missing-invalidation':change('src/app/config.s','    call config_key_source_begin\n','    nop\n')
 if mutation=='ignore-epoch':change('src/app/keylinesnapshotcapture.s','    cmp [rbx + KSI_epoch], rax\n    jne 8f','    cmp rax, rax\n    jne 8f')
 if mutation=='poison-ready':change('src/app/keylinesnapshotcapture.s','    cmp qword ptr [rbx + PO_ready], 1\n    je .Lkss_ready','    cmp qword ptr [rbx + PO_ready], 1\n    jne 91f\n    mov rdi, rbx\n    call ksi_source_check\n    test rax, rax\n    jnz .Lkss_fail\n    jmp .Lkss_ready\n91:')
 if mutation=='alias-source':change('src/app/keylinesnapshotcapture.s','    mov [r13], rax\n','    mov rax, [r15]\n    mov [r13], rax\n')
 if mutation=='continue-after-allocation':change('src/app/keylinesnapshotcapture.s','    mov qword ptr [rbx + KSI_offset], 0\n    jmp .Lkss_pending','    mov qword ptr [rbx + KSI_offset], 0\n    jmp .Lkss_next')
 if mutation=='unbounded-copy':change('src/app/keylinesnapshotcapture.s','    mov ecx, 4096\n','    mov ecx, 8192\n')
 if mutation=='append-empty':change('src/app/keylinesnapshotcopy.s','    jz .Lksc_skip\n','    nop\n')
 if mutation=='write-refused-output':change('src/app/keylinesnapshotread.s','8:  mov rax, -22\n    EPILOGUE','8:  test r13, r13\n    jz 81f\n    mov qword ptr [r13], 0\n81: mov rax, -22\n    EPILOGUE')
 if mutation=='retain-wrap':change('src/app/keylinesnapshot.s','    call prep_object_retain\n','    inc qword ptr [rdi + PO_refs]\n    xor eax, eax\n')
 if mutation=='ignore-loading':change('src/app/keylinesnapshot.s','    test rdx, rdx\n    jnz .Lksb_stale','    nop\n    nop')
 if mutation=='epoch-wrap':change('src/app/keylinesource.s','1:  mov qword ptr [rip + key_source_epoch], 0','1:  mov qword ptr [rip + key_source_epoch], 1')
 if mutation=='ignore-destination':change('src/app/keylinesnapshotcopy.s','    cmp [r13 + CG_nkeys], rax\n    jne .Lksc_bad','    cmp rax, rax\n    jne .Lksc_bad')
 if mutation=='allow-nul':change('src/app/commandgenerationinputs.s','1:  cmp byte ptr [r12 + rcx], 0\n    je .Lcgka_invalid','1:  cmp byte ptr [r12 + rcx], 0\n    nop')
 if extra_sources:
  assert extra_sources.keys()<=extra.keys(), 'override must preserve existing fixture observers'
  extra.update(extra_sources)
 path='src/app/keylinesnapshotcapture.s';assert extra[path].count('    call memcpy\n')==1;extra[path]=extra[path].replace('    call memcpy\n','    call ksti_source_copy\n')
 path='src/app/commandgenerationinputs.s';text=extra.get(path,(ROOT/path).read_text());needle='FN command_generation_key_append\n';assert text.count(needle)==1;extra[path]=text.replace(needle,needle+'    sub rsp, 8\n    call ksti_append_guard\n    add rsp, 8\n')
 addon=(ROOT/'tests/keyline_snapshot_cases.inc').read_text()
 if limits or contracts:addon=addon.replace('FN main\n','FN original_keyline_main\n')+'\n'+(ROOT/'tests/keyline_snapshot_limits.inc').read_text()
 if contracts:addon=addon.replace('FN main\n','FN limits_keyline_main\n')+'\n'+(ROOT/'tests/keyline_snapshot_contracts.inc').read_text()
 if addon_suffix:
  assert addon.count('FN main\n')==1
  addon=addon.replace('FN main\n','FN original_keyline_mode_main\n')+'\n'+addon_suffix
 if windows:
  extra={name:re.sub(r'(?m)^(\s*\.(?:pushsection|section)) \.rodata(\.\w+)?[^\n]*',lambda m:m[1]+' .rdata'+('$'+m[2][1:]if m[2]else'')+',"dr"',source)for name,source in extra.items()}
 return b.build(folder,windows=windows,addon=addon,extra_replacements=extra,mem_unmap_hook='ksti_native_unmap'if limits or contracts else None)
def main():
 p=argparse.ArgumentParser();p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--limits',action='store_true');p.add_argument('--contracts',action='store_true');p.add_argument('--mutation',choices=list(MUTATIONS));p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.limits and a.contracts:p.error('choose one fixture')
 if a.build_only and not a.exe:p.error('--build-only requires --exe')
 if a.negative_controls and(a.exe or a.build_only or a.mutation or a.limits or a.contracts):p.error('--negative-controls builds all three baselines and controls')
 if a.mutation:
  kind,_=MUTATIONS[a.mutation];a.limits=kind=='limits';a.contracts=kind=='contracts'
 windows=bool(a.wine)or os.name=='nt'or bool(a.build_only and a.exe.suffix=='.exe')
 with tempfile.TemporaryDirectory(prefix='rhun-keyline-')as t:
  folder=Path(t)
  config=folder/'config';(config/'rhun').mkdir(parents=True)
  env=os.environ.copy();env['XDG_CONFIG_HOME']=('Z:'+str(config.resolve()))if a.wine else str(config)
  def check(exe,limits=False,contracts=False,mutation=None):
   (config/'rhun/config').write_text('[keys]\nctrl+alt+9 = none\nmalformed line\nctrl+q = quit\n')
   command=([a.wine,'Z:'+str(exe.resolve())]if a.wine else[str(exe.resolve())])
   r=subprocess.run(command,cwd=ROOT,env=env,capture_output=True,timeout=180 if limits else 60)
   if mutation:
    assert r.returncode==MUTATIONS[mutation][1]and not r.stdout and not r.stderr,(mutation,r.returncode,r.stdout,r.stderr)
    print('ok keyline negative control '+mutation,flush=True)
   else:
    expected=b'ok keyline getter, source and cursor contracts\n'if contracts else b'ok keyline bounds, zero spans and native retirement\n'if limits else EXPECTED
    assert r.returncode==0 and r.stdout==expected and not r.stderr,(r.returncode,r.stdout,r.stderr)
    print(expected.decode().strip(),flush=True)
  if a.negative_controls:
   for kind in ['normal','limits','contracts']:check(build(folder/kind,windows,kind=='limits',kind=='contracts'),kind=='limits',kind=='contracts')
   for mutation,(kind,_)in MUTATIONS.items():check(build(folder/mutation,windows,kind=='limits',kind=='contracts',mutation),kind=='limits',kind=='contracts',mutation)
  else:
   exe=a.exe if a.exe and not a.build_only else build(folder/'build',windows,a.limits,a.contracts,a.mutation)
   if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(exe,a.exe);shutil.copymode(exe,a.exe);print('built keyline snapshot fixture',flush=True);return
   check(exe,a.limits,a.contracts,a.mutation)
if __name__=='__main__':main()
