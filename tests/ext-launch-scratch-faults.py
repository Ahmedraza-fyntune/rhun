#!/usr/bin/env python3
"""Inject owned allocation failures through actual launch callers before native handles."""
import argparse,importlib.util,os,subprocess,tempfile,shutil,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,windows=False):
 spec=importlib.util.spec_from_file_location('fault_build',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 source=(ROOT/'src/app/ext.s').read_text()
 for name,end in [('ext_legacy_start_impl','# Explicit verified plan view.'),('ext_supervised_start_impl','# Root calls after publication')]:
  a=source.index('FN '+name+'\n');z=source.index(end,a);body=source[a:z]
  body=body.replace('    SYS SYS_open\n','    call lsf_forbidden_native\n').replace('    SYS SYS_pipe2\n','    call lsf_forbidden_native\n')
  if name=='ext_supervised_start_impl':
   assert body.count('    call ext_activation_host_check\n')==1;body=body.replace('    call ext_activation_host_check\n','    xor eax, eax\n')
  source=source[:a]+body+source[z:]
 helper=(ROOT/'src/app/extlaunchscratch.s').read_text()
 for callee in ['ext_prepare_owner_create','prep_object_create','prep_owned_vec_push','prep_owned_dup']:
  assert helper.count('call '+callee)==1;helper=helper.replace('call '+callee,'call lsf_wrap_'+callee)
  helper+='\nFN lsf_wrap_'+callee+'\n'
  if callee=='prep_owned_vec_push'and not windows and sys.platform=='darwin':
   helper+='''    cmp qword ptr [rip + lsf_fail_at], 1000
    jne 1f
    cmp rsi, [rip + launch_env]
    jne 1f
    cmp qword ptr [rsi + VEC_len], 9
    jne 1f
    mov qword ptr [rdi + PO_error], -12
    mov qword ptr [rip + lsf_allocations], 1000
    xor eax, eax
    ret
1:
'''
  helper+='    PROLOGUE\n    mov qword ptr [rip + lsf_alloc_active], 1\n    call '+callee+'\n    mov qword ptr [rip + lsf_alloc_active], 0\n    EPILOGUE\n'
 mem=(ROOT/'src/mem.s').read_text();assert mem.count('FN mem_alloc_try\n')==1
 mem=mem.replace('FN mem_alloc_try\n','''FN mem_alloc_try
    cmp qword ptr [rip + lsf_alloc_active], 0
    je lsf_actual_alloc
    inc qword ptr [rip + lsf_allocations]
    mov rax, [rip + lsf_allocations]
    cmp rax, [rip + lsf_fail_at]
    jne lsf_actual_alloc
    xor eax, eax
    ret
FN lsf_actual_alloc
''')
 fixture=(ROOT/'tests/faults/ext_launch_scratch.s').read_text().replace('cmp qword ptr [rip + g_argc], 4','cmp qword ptr [rip + g_argc], 5')
 fixture=fixture.replace('    mov r14d, 3\n2:', '''    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 32]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + 32]
    call parse_u64
    mov [rip + lsf_fail_at], rax
    mov r14d, 3
2:''')
 fixture=fixture.replace('lsf_attempt:\n    PROLOGUE','lsf_attempt:\n    PROLOGUE\n    mov qword ptr [rip + lsf_allocations], 0')
 a=fixture.index('lsf_validate_counts:\n');z=fixture.index('FN lsf_setup_fcntl',a)
 fixture=fixture[:a]+'''lsf_validate_counts:
    cmp qword ptr [rip + lsf_calls], 0
    jne lsf_fail
    mov rax, [rip + lsf_fail_at]
    cmp rax, [rip + lsf_allocations]
    jne lsf_fail
    ret
'''+fixture[z:]
 for old in ['cannot create pipes','cannot start the program','failed to start: the program could not be executed']:
  fixture=fixture.replace('.asciz "'+old+'"','.asciz "cannot allocate extension launch inputs"')
 fixture+='''\n.bss
.globl lsf_fail_at,lsf_allocations,lsf_alloc_active
.p2align 3
lsf_fail_at: .quad 0
lsf_allocations: .quad 0
lsf_alloc_active: .quad 0
.text
FN lsf_forbidden_native
    mov edi, 75
    call sys_exit
    ud2
'''
 return b.build(folder,fixture,{'src/app/ext.s':source,'src/app/extlaunchscratch.s':helper,'src/mem.s':mem},windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');a=p.parse_args()
 if a.build_only and not a.exe:p.error('--build-only requires --exe')
 windows=os.name=='nt'or bool(a.wine)or bool(a.build_only and a.exe.suffix=='.exe')
 def arg(path):return 'Z:'+str(path.resolve())if a.wine else str(path.resolve())
 with tempfile.TemporaryDirectory(prefix='rhun-launch-caller-faults-')as t:
  t=Path(t);exe=a.exe if a.exe and not a.build_only else build(t/'build',windows)
  if a.build_only:
   a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(exe,a.exe);print('built actual launch allocation faults',flush=True);return
  for case in [0,1]:
   for words in [0,2]:
    maximum=(24 if windows else 19 if sys.platform=='darwin'else 18)+words
    failures=list(range(1,maximum+1))
    if sys.platform=='darwin'and not windows:failures.append(1000)
    for failure in failures:
     state=t/('state-'+str(case)+'-'+str(words)+'-'+str(failure));state.mkdir()
     r=subprocess.run(([a.wine]if a.wine else[])+[arg(exe),arg(state),str(case),str(words),str(failure)],capture_output=True,timeout=30)
     assert r.returncode==0 and not r.stdout and not r.stderr,(case,words,failure,r.returncode,r.stdout,r.stderr)
    print('ok actual launch allocation faults',case,words,len(failures),flush=True)
if __name__=='__main__':main()
