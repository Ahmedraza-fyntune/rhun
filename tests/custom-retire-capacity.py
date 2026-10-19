#!/usr/bin/env python3
"""Actual kind8 ownership, registry bounds and native refusal gates."""
import argparse,importlib.util,os,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={
 'old-register-bound':('po',50), 'old-mark-bound':('po',52),
 'old-release-bound':('po',52), 'old-step-bound':('po',53),
 'old-alloc-bound':('simple',52), 'old-enqueue-bound':('simple',53),
 'old-free-bound':('simple',54), 'old-handoff-bound':('po',54),
 'register-nine':('simple',51), 'dispatch-nine':('simple',51),
 'accept-invalid-mode':('po',50), 'clear-native-charge':('simple',54),
}
def build(folder,windows=False,mode='po',mutation=None):
 spec=importlib.util.spec_from_file_location('retire_capacity_builder',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 paths=['src/app/extprepareretirecustom.s','src/app/extprepareretirequeue.s','src/app/extprepareretirestep.s']
 replacements={name:(ROOT/name).read_text()for name in paths}
 def change(path,name,old,new):
  source=replacements[path];head,body=source.split('FN '+name+'\n',1);body,sep,tail=body.partition('\nFN ')
  assert body.count(old)==1,(mutation,path,name,old);replacements[path]=head+'FN '+name+'\n'+body.replace(old,new,1)+sep+tail
 if mutation in ['old-register-bound','old-mark-bound','old-alloc-bound','old-enqueue-bound','old-free-bound','old-handoff-bound','register-nine','dispatch-nine']:
  name={'old-register-bound':'ext_prepare_retire_register_kind','old-mark-bound':'ext_prepare_retire_mark_custom_po','old-alloc-bound':'ext_prepare_retire_alloc_custom','old-enqueue-bound':'ext_prepare_retire_enqueue_custom','old-free-bound':'ext_prepare_retire_free_custom','old-handoff-bound':'ext_prepare_retire_handoff_ledger','register-nine':'ext_prepare_retire_register_kind','dispatch-nine':'prep_retire_dispatch_custom'}[mutation]
  register=name in ['ext_prepare_retire_register_kind','ext_prepare_retire_mark_custom_po','ext_prepare_retire_alloc_custom']
  old='cmp '+('rax'if register else'rcx')+', RD_CUSTOM_LAST - RD_CUSTOM_FIRST'
  change(paths[0],name,old,'cmp '+('rax'if register else'rcx')+', '+('5'if mutation in ['register-nine','dispatch-nine']else'3'))
 if mutation=='old-release-bound':change(paths[1],'prep_retire_po_release_sync','cmp qword ptr [r8 + RD_kind], RD_CUSTOM_LAST','cmp qword ptr [r8 + RD_kind], 7')
 if mutation=='old-step-bound':change(paths[2],'prep_retire_one','cmp qword ptr [rdi + RD_kind], RD_CUSTOM_LAST','cmp qword ptr [rdi + RD_kind], 7')
 if mutation=='accept-invalid-mode':change(paths[0],'ext_prepare_retire_register_kind','cmp rdx, 1','cmp rdx, 2')
 if mutation=='clear-native-charge':change(paths[0],'ext_prepare_retire_free_custom','    test rax, rax\n    js 1f','    test rax, rax\n    nop')
 # The adjacent sentinel is test-only and proves invalid9 never aliases modes[0].
 replacements[paths[0]]+='\n.bss\n.p2align 3\n.globl rtcap_modes_end\nrtcap_modes_end: .quad 0\n'
 mem=(ROOT/'src/mem.s').read_text();needle='    SYS SYS_munmap';assert mem.count(needle)==1;replacements['src/mem.s']=mem.replace(needle,'    call rtcap_native_unmap')
 needle='FN mem_alloc_try\n';assert replacements['src/mem.s'].count(needle)==1
 replacements['src/mem.s']=replacements['src/mem.s'].replace(needle,needle+'    cmp qword ptr [rip + rtcap_alloc_fault], 0\n    je 881f\n    xor eax, eax\n    ret\n881:\n')
 fixture=(ROOT/'tests/ext_prepare_custom_retire_test.s').read_text();assert fixture.count('FN main\n')==1
 fixture='.equ RTCAP_MODE, '+str(mode=='po'and 1 or 0)+'\n'+fixture.replace('FN main\n','FN rtcap_original_main\n')+'\n'+(ROOT/'tests/custom_retire_capacity_cases.inc').read_text()
 return b.build(folder,fixture,replacements,windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--mode',choices=['simple','po'],default='po');p.add_argument('--mutation',choices=list(CODES));p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.build_only and not a.exe:p.error('--build-only requires --exe')
 if a.negative_controls and(a.exe or a.build_only or a.mutation):p.error('negative controls build both baselines and all controls')
 if a.mutation:a.mode=CODES[a.mutation][0]
 windows=os.name=='nt'or bool(a.wine)or bool(a.build_only and a.exe.suffix=='.exe')
 with tempfile.TemporaryDirectory(prefix='rhun-retire-capacity-')as temporary:
  folder=Path(temporary)
  def check(exe,mode,mutation=None):
   result=subprocess.run(([a.wine,'Z:'+str(exe.resolve())]if a.wine else[str(exe.resolve())]),cwd=ROOT,capture_output=True,timeout=90)
   if mutation:
    assert result.returncode==CODES[mutation][1]and not result.stdout and not result.stderr,(mutation,result.returncode,result.stdout,result.stderr)
    print('ok custom retirement negative control '+mutation,flush=True)
   else:
    expected=('ok custom kind8 '+mode+' ownership and native retry\n').encode()
    assert result.returncode==0 and result.stdout==expected and not result.stderr,(result.returncode,result.stdout,result.stderr)
    print(expected.decode().strip(),flush=True)
  if a.negative_controls:
   for mode in ['po','simple']:check(build(folder/mode,windows,mode),mode)
   for mutation,(mode,_)in CODES.items():check(build(folder/mutation,windows,mode,mutation),mode,mutation)
  else:
   exe=a.exe if a.exe and not a.build_only else build(folder/'build',windows,a.mode,a.mutation)
   if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(exe,a.exe);shutil.copymode(exe,a.exe);return
   check(exe,a.mode,a.mutation)
if __name__=='__main__':main()
