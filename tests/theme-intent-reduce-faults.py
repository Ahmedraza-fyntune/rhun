#!/usr/bin/env python3
"""Reducer allocation refusal preserves its borrowed input; semantic checks reject three bypasses."""
import argparse,importlib.util,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,name,win):
 spec=importlib.util.spec_from_file_location('b',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/theme_intent_reduce_test.s').read_text();replacements={}
 needle='    mov rdi, r12\n    lea rsi, [rsp + 128]\n    call theme_intent_reduce\n';assert fixture.count(needle)==1
 fixture=fixture.replace(needle,'    mov rdi, r12\n    mov esi, TI_SIZE\n    lea rdx, [rsp + 432]\n    call sha256_hash\n    test eax, eax\n    jz tirt_fail\n'+needle,1)
 needle='    mov [rsp + 360], rcx\n';assert fixture.count(needle)==1
 fixture=fixture.replace(needle,needle+'    mov rdi, r12\n    mov esi, TI_SIZE\n    lea rdx, [rsp + 464]\n    call sha256_hash\n    test eax, eax\n    jz tirt_fail\n    lea rdi, [rsp + 432]\n    lea rsi, [rsp + 464]\n    mov edx, 32\n    call memeq\n    test eax, eax\n    jz tirt_fail\n',1)

 if name in('oom','input'):
  memory=(ROOT/'src/app/themecapturemem.s').read_text().replace('FN tc_alloc_try\n','FN tirf_real_alloc\n',1)
  fixture+='\n.bss\n.p2align 3\ntirf_count: .zero 8\n.text\nFN tc_alloc_try\n    inc qword ptr [rip + tirf_count]\n    cmp qword ptr [rip + tirf_count], 2\n    jne tirf_real_alloc\n    xor eax, eax\n    ret\n';replacements['src/app/themecapturemem.s']=memory
  if name=='input':
   core=(ROOT/'src/app/themeintentreduce.s').read_text();old='.Ltr_oom:\n';assert core.count(old)==1;replacements['src/app/themeintentreduce.s']=core.replace(old,old+'    mov qword ptr [rbx + TI_state], TI_RETIRING\n',1)
 else:
  core=(ROOT/'src/app/themeintentreduce.s').read_text()
  if name in('follow','system'):
   field='TI_follow'if name=='follow'else'TI_system';off=104 if name=='follow'else 108
   old=f'    mov eax, [rsp + {off}]\n    mov [r13 + {field}], eax\n';new=f'    mov eax, [rbx + {field}]\n    mov [r13 + {field}], eax\n'
  else:
   old='    test r15, r15\n    jne .Ltr_allocate\n';new='    jmp .Ltr_allocate\n'
  assert core.count(old)==1;replacements['src/app/themeintentreduce.s']=core.replace(old,new,1)
 return m.build(folder,fixture,replacements,win)
def request(kind=0,arg=0,follow=0,resolved=b''):
 vals=(b'value',b'dark',b'light',None,None,b'shown');h=bytearray(144);struct.pack_into('<IIiII',h,0,7,follow,-1,1,1);struct.pack_into('<6i',h,24,*(-1 if v is None else len(v)for v in vals));struct.pack_into('<IIiIQQIIIIQQ',h,64,kind,0,arg,0,0,len(resolved),0,1,0,0,3,1);return h+b''.join(v+b'\0'for v in vals if v is not None)+resolved
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--build-only',type=Path);p.add_argument('--exe-root',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt'
 if a.build_only:
  for name in('oom','follow','system','unused','input'):build(a.build_only/name,name,True)
  return
 with tempfile.TemporaryDirectory(prefix='rhun-theme-reduce-fault-')as td:
  for name in('oom','follow','system','unused','input'):
   exe=a.exe_root/name/'ext_store_fault_test.exe'if a.exe_root else build(Path(td)/name,name,win)
   data=request(4,1)if name=='follow'else request(2,1)if name=='system'else request(resolved=b'a\0b')if name=='unused'else request()
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],input=data,capture_output=True,timeout=15)
   if name=='input':
    assert r.returncode==73 and not r.stdout and not r.stderr,(name,r)
    print('ok theme-intent/reducer-input-preservation-negative',flush=True);continue
   assert r.returncode==0 and not r.stderr,(name,r)
   if name=='oom':assert r.stdout==struct.pack('<qq',-12,0),(name,r.stdout)
   else:
    assert len(r.stdout)>=128 and struct.unpack_from('<qq',r.stdout)==(0,0),(name,r.stdout)
    try:
     if name=='unused':assert r.stdout==struct.pack('<qq',-22,0)
     else:
      assert struct.unpack_from('<qq',r.stdout)==(0,0)
      assert struct.unpack_from('<i',r.stdout,20 if name=='follow'else 24)[0]==1
    except AssertionError:pass
    else:raise AssertionError('semantic bypass not rejected: '+name)
   print('ok theme-intent/reducer-'+name,flush=True)
if __name__=='__main__':main()
