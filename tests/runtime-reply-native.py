#!/usr/bin/env python3
"""Real owned reply, counted complete child stream and actual quiet host take."""
import argparse,importlib.util,os,re,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={'timestamp-dead':104,'duplicate-output':106,'quiet-needs-owner':107,'ignore-session-due':108}
SCENARIOS={'timestamp-dead':0,'duplicate-output':0,'quiet-needs-owner':1,'ignore-session-due':1}
def build(folder,windows=False,mutation=None,scenario=0):
 spec=importlib.util.spec_from_file_location('runtime_channel_native_builder',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 source=(ROOT/'tests/extension_lifecycle_test.s').read_text();a=source.index('    # Stop during preparation must close the gate before it can become READY.\n');z=source.index('    lea rdi, [rip + tek_ok]\n',a)
 source=source[:a]+'    call rcn_actual\n'+source[z:]
 old='lc_extension: .zero EXT_SIZE';assert source.count(old)==1;source=source.replace(old,'lc_extension: .zero RT_SLOT_COUNT * EXT_SIZE')
 old='    mov qword ptr [rip + g_exts + VEC_cap], 1';assert source.count(old)==1;source=source.replace(old,'    mov qword ptr [rip + g_exts + VEC_cap], RT_SLOT_COUNT')
 old='6:  mov edi, 1\n    lea rsi, [rip + tek_bytes]';assert source.count(old)==1;source=source.replace(old,'    call rcn_child_receipt\n'+old,1)
 source=source.replace('ok supervised extension lifecycle\\n','ok owned native runtime reply\\n')
 source=source.replace('.include "rhun.inc"','.include "rhun.inc"\n.include "app/extprepareretire.inc"\n.include "app/extruntimeservice.inc"',1)
 helper=(ROOT/'tests/ext_activation_lifecycle_helpers.inc').read_text();old='    cmp qword ptr [rip + lc_retire_status + 24], 0';assert helper.count(old)==1;helper=helper.replace(old,'    mov rdx, [rip + rpn_native_diag]\n    cmp [rip + lc_retire_status + 24], rdx',1)
 old='.include "../tests/ext_activation_lifecycle_helpers.inc"';assert source.count(old)==1;source=source.replace(old,helper,1)
 source+='\n'+'.equ RPN_SCENARIO, '+str(scenario)+'\n'+(ROOT/'tests/runtime_reply_native_cases.inc').read_text()
 assert not re.search(r'(?m)^\s*\.section \.rodata\.',source)
 ext=(ROOT/'src/app/ext.s').read_text();assert ext.count('call ext_arm_plan')==1;ext=ext.replace('call ext_arm_plan','call rcn_defer_auto_arm',1)
 source+='\n.text\nFN rcn_defer_auto_arm\n    xor eax, eax\n    ret\n'
 activation=(ROOT/'src/app/extactivation.s').read_text();old='FN ext_activation_owner_release';assert activation.count(old)==1;activation=activation.replace(old,'FN rpn_real_ea_release',1)
 replacements={'src/app/ext.s':ext,'src/app/extactivation.s':activation}
 if mutation=='ignore-session-due':
  path='src/app/extruntimesession.s';text=(ROOT/path).read_text();old='    cmp r14, rcx\n    jb .Lrcl_wait_due';assert text.count(old)==1;replacements[path]=text.replace(old,'    cmp r14, rcx\n    nop',1)
 if mutation=='timestamp-dead':
  path='src/app/extruntimechannel.s';text=(ROOT/path).read_text();old='    cmp qword ptr [r15 + EXT_in_closed_at], 0\n    jne .Lrch_pending';assert text.count(old)==1;replacements[path]=text.replace(old,old.replace('.Lrch_pending','.Lrch_closed'),1)
 if mutation=='quiet-needs-owner':
  path='src/app/extruntimechannelquiet.s';text=(ROOT/path).read_text();old='    jz .Lrcq_ea_taken';assert text.count(old)==1;replacements[path]=text.replace(old,'    jz .Lrcq_stale',1)
 if mutation=='duplicate-output':
  path='src/app/extruntimereply.s';text=(ROOT/path).read_text();old='    jmp ext_send_enqueue_channel_bounded';assert text.count(old)==1;replacements[path]=text.replace(old,'    jmp rpn_duplicate_enqueue',1)
  source+='\n.text\nFN rpn_duplicate_enqueue\n    PROLOGUE 48\n    mov [rsp], rdi\n    mov [rsp + 8], rsi\n    mov [rsp + 16], rdx\n    mov [rsp + 24], rcx\n    mov [rsp + 32], r8\n    mov [rsp + 40], r9\n    call ext_send_enqueue_channel_bounded\n    test rax, rax\n    jnz 1f\n    mov rdi, [rsp]\n    mov rsi, [rsp + 8]\n    mov rdx, [rsp + 16]\n    mov rcx, [rsp + 24]\n    mov r8, [rsp + 32]\n    mov r9, [rsp + 40]\n    call ext_send_enqueue_channel_bounded\n1:  EPILOGUE\n'
 return b.build(folder,source,replacements,windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--exe',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--scenario',type=int,choices=range(2));p.add_argument('--mutation',choices=list(CODES));p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.wine and(not a.exe or not a.wine_drive_root):p.error('--wine requires exact --exe and --wine-drive-root')
 if a.exe and a.build_only:p.error('--exe and --build-only are exclusive')
 if a.negative_controls and(a.exe or a.mutation or a.scenario is not None):p.error('negative controls build their own unambiguous variants')
 if a.mutation and a.scenario is not None and a.scenario!=SCENARIOS[a.mutation]:p.error('mutation requires its documented scenario')
 windows=os.name=='nt'or a.windows_build or bool(a.wine);drive=a.wine_drive_root.resolve()if a.wine else None
 def check(mutation,scenario):
  with tempfile.TemporaryDirectory(prefix='rhun-channel-native-',dir=drive)as temporary:
   base=Path(temporary).resolve();exe=a.exe or build(((a.build_only/(mutation or str(scenario)))if a.build_only else base/'bin'),windows,mutation,scenario)
   if a.build_only:print('built actual native channel',exe,flush=True);return
   root=base/'store';payload=root/'owner/name';payload.mkdir(parents=True);(root/'.change.lock').touch();lease=root/'.leases/legacy'/b'owner'.hex()/(b'name'.hex()+'.lock');lease.parent.mkdir(parents=True);lease.touch()
   state=base/'state';state.mkdir();home=base/'home';home.mkdir();(home/'approved').write_bytes(b'keeper')
   def arg(path):
    path=path.resolve()
    return('C:/'+path.relative_to(drive).as_posix()if drive else'Z:'+str(path))if a.wine else str(path)
   r=subprocess.run(([a.wine]if a.wine else[])+[arg(p)for p in [exe,root,payload,state,home]],cwd=ROOT,capture_output=True,timeout=90)
   assert r.returncode==CODES.get(mutation,0)and r.stdout+r.stderr==(b''if mutation else b'ok owned native runtime reply\n'),(mutation,r)
   if not mutation and scenario==0:assert(state/'channel-complete').read_bytes()==b'1'

  print('ok owned native reply '+(mutation or str(scenario)),flush=True)
 variants=[(None,i)for i in range(2)]
 if a.mutation:variants=[(a.mutation,SCENARIOS[a.mutation])]
 elif a.scenario is not None:variants=[(None,a.scenario)]
 elif a.negative_controls:variants.extend((m,SCENARIOS[m])for m in CODES)
 if a.exe:variants=[(a.mutation,a.scenario if a.scenario is not None else SCENARIOS.get(a.mutation,0))]
 for mutation,scenario in variants:check(mutation,scenario)
if __name__=='__main__':main()
