#!/usr/bin/env python3
"""Actual metadata prompt eligibility. Delayed UI association tests are separate."""
import argparse,importlib.util,os,re,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={'ext-alignment':200,'sd-alignment':200,'schema-count':200,'schema-cap':200,'metadata-owner':201,'identity-owner':201,'activation-owner':201,'required':201,'removed':202,'latch':203,'zero-index':200,'uncleared-error':200}
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--negative-controls',action='store_true');p.add_argument('--mutation',choices=CODES);a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe')
if a.negative_controls and (a.exe or a.build_only or a.mutation):p.error('negative controls build their own fixtures')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')
def build(folder,mutation=None):
 spec=importlib.util.spec_from_file_location('prompt_fixture_build',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 fixture=(ROOT/'tests/ext_settings_view_test.s').read_text().replace('FN main','FN original_settings_view_main')+'\n'+(ROOT/'tests/ext_settings_catalog_cases.inc').read_text().replace('FN main','FN original_settings_catalog_main')
 effective=(ROOT/'tests/ext_settings_effective_cases.inc').read_text();marker='    mov edx, 127\n    call av_model\n';assert effective.count(marker)==1
 fixture+='\n'+effective.replace(marker,marker+'    call epr_legacy_cases\n    call ebr_cases\n')
 real=(ROOT/'tests/ext_settings_editor_real_cases.inc').read_text()
 for name in ['ext_setting_resolve','ext_setting_value','ext_setting_flags']:real=real.replace(name+'_real',name)
 marker='    call ebr_resolve_valid\n';assert real.count(marker)==1
 real=real.replace(marker,marker+'    mov rdi, rbx\n    mov rsi, [rbx + EXT_sdefs + VEC_ptr]\n    add rsi, 2 * SD_SIZE\n    mov edx, 2\n    call epr_prepared_valid\n')
 marker='    call ebr_resolve_error\n';assert real.count(marker)==1
 real=real.replace(marker,marker+'    mov rdi, r12\n    mov esi, 1\n    mov rdx, -116\n    call epr_error\n')
 fixture+='\n'+(ROOT/'tests/ext_settings_prompt_cases.inc').read_text()+'\n'+real
 fixture=fixture.replace('.ifdef VT_FAULTS','.if 0');replacements={'src/app/extsettingsprompt.s':(ROOT/'src/app/extsettingsprompt.s').read_text()}
 def change(path,old,new):
  text=replacements.get(path,(ROOT/path).read_text());assert text.count(old)==1,(path,old,text.count(old));replacements[path]=text.replace(old,new)
 for path,names in [('src/mem.s',['mem_alloc','mem_alloc_try','mem_free']),('src/sys.s',['file_read_all','file_read_all_extra','file_write_all']),('src/app/ext.s',['ext_send','ext_flush'])]:
  for name in names:change(path,'FN '+name+'\n','FN '+name+'\n    cmp qword ptr [rip + av_read_poison], 0\n    jne av_poison_fail\n')
 path='src/app/extsettingsprompt.s'
 if mutation=='ext-alignment':change(path,'    test rdx, rdx\n    jnz .Lspr_bad\n    mov r13, rax','    xor edx, edx\n    jnz .Lspr_bad\n    mov r13, rax')
 elif mutation=='sd-alignment':change(path,'    test rdx, rdx\n    jnz .Lspr_bad\n    mov r8, rax','    xor edx, edx\n    jnz .Lspr_bad\n    mov r8, rax')
 elif mutation=='schema-count':change(path,'    cmp rcx, 256\n    ja .Lspr_bad','    cmp rcx, rcx\n    ja .Lspr_bad')
 elif mutation=='schema-cap':change(path,'    cmp [rbx + EXT_sdefs + VEC_cap], rcx','    cmp rcx, rcx')
 elif mutation in ['metadata-owner','identity-owner','activation-owner']:
  field={'metadata-owner':'EXT_metadata_owner','identity-owner':'EXT_identity_owner','activation-owner':'EXT_activation_owner'}[mutation]
  change(path,'    cmp qword ptr [rbx + '+field+'], 0\n    jne .Lspr_stale','    cmp rbx, rbx\n    jne .Lspr_stale')
 elif mutation=='required':change(path,'    cmp dword ptr [rbx + EXT_activation_required], 0\n    jne .Lspr_stale','    cmp rbx, rbx\n    jne .Lspr_stale')
 elif mutation=='removed':change(path,'    call ext_is_visible\n','    mov eax, 1\n')
 elif mutation=='latch':
  change(path,'    call ext_is_visible\n','    call ext_is_visible\n    cmp qword ptr [rip + g_ext_prepared_catalog_active], 1\n    jne .Lspr_mutant_visible\n    mov eax, 1\n.Lspr_mutant_visible:\n')
  change(path,'    cmp qword ptr [rip + g_ext_prepared_catalog_active], 0\n    jne .Lspr_stale','    cmp rbx, rbx\n    jne .Lspr_stale')
 elif mutation=='zero-index':change(path,'    mov r8, rax\n    mov rax, r13','    xor r8d, r8d\n    mov rax, r13')
 elif mutation=='uncleared-error':change(path,'.Lspr_error:\n    xor edx, edx\n    xor ecx, ecx\n    xor r8d, r8d\n','.Lspr_error:\n    xor edx, edx\n    xor ecx, ecx\n')
 for text in [fixture,*replacements.values()]:assert not re.search(r'(?m)^\s*\.section \.rodata[^\s\n]',text)
 return b.build(folder,fixture,replacements,windows=windows)
def check(exe,mutation=None):
 r=subprocess.run(([a.wine] if a.wine else [])+[str(exe)],cwd=ROOT,capture_output=True,timeout=90)
 if mutation:assert r.returncode==CODES[mutation],(mutation,r.returncode,r.stdout,r.stderr)
 else:assert r.returncode==0 and r.stdout==b'ok installed settings authority and canonical dirty overlays\n' and not r.stderr,(r.returncode,r.stdout,r.stderr)
with tempfile.TemporaryDirectory(prefix='rhun-settings-prompt-') as t:
 f=Path(t)
 if a.negative_controls:
  check(build(f/'baseline'))
  for m in CODES:check(build(f/m,m),m);print('ok actual prompt eligibility negative control '+m,flush=True)
 else:
  e=a.exe if a.exe and not a.build_only else build(f,a.mutation)
  if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(e,a.exe);print('built actual prompt eligibility fixture: '+str(a.exe));sys.exit(0)
  check(e,a.mutation);print('ok actual staging and prepared prompt eligibility')
