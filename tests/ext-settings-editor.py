#!/usr/bin/env python3
"""Test numeric EXT/SD bridge checks with an explicit pure metadata predicate double."""
import argparse,importlib.util,os,re,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={'ext-alignment':181,'sd-alignment':182,'schema-cap':184,'metadata-refusal':183,'sd-value-fallback':180,'zero-index':180,'zero-length':180,'zero-flags':188,'resolver-model-gate':185,'resolver-uncleared-error':182}
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--negative-controls',action='store_true');p.add_argument('--mutation',choices=[*CODES,'real-ignore-visibility','real-ignore-identity']);p.add_argument('--real-metadata',action='store_true');a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe')
if a.negative_controls and (a.exe or a.build_only or a.mutation):p.error('negative controls build their own fixtures')
REAL_CODES={'real-ignore-visibility':191,'real-ignore-identity':192}
if a.mutation in REAL_CODES and not a.real_metadata:p.error('real predicate mutation requires --real-metadata')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')
def build(folder,mutation=None):
 spec=importlib.util.spec_from_file_location('editor_fixture_build',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 fixture=(ROOT/'tests/ext_settings_view_test.s').read_text().replace('FN main','FN original_settings_view_main')+'\n'+(ROOT/'tests/ext_settings_catalog_cases.inc').read_text().replace('FN main','FN original_settings_catalog_main')
 effective=(ROOT/'tests/ext_settings_effective_cases.inc').read_text();old='    mov edx, 127\n    call av_model\n';assert effective.count(old)==1
 fixture+='\n'+effective.replace(old,old+'    call eb_cases\n')+'\n'+(ROOT/'tests/ext_settings_editor_cases.inc').read_text()
 if a.real_metadata:
  assert (ROOT/'src/app/extvisibility.s').is_file(), 'actual metadata predicate sources required'
  real=(ROOT/'src/app/extsettingseditor.s').read_text()
  for include in ['.include "rhun.inc"\n','.include "app/extprepare.inc"\n']:
   assert real.count(include)==1
   real=real.replace(include,'')
  for name in ['settings_editor_metadata','ext_setting_resolve','ext_setting_value','ext_setting_flags']:
   real=real.replace(name,name+'_real')
  assert fixture.count('    call eb_cases\n')==1
  fixture=fixture.replace('    call eb_cases\n','    call eb_cases\n    call ebr_cases\n')
  fixture+='\n'+real+'\n'+(ROOT/'tests/ext_settings_editor_real_cases.inc').read_text()
 fixture=fixture.replace('.ifdef VT_FAULTS','.if 0')
 replacements={'src/app/extsettingseditor.s':(ROOT/'src/app/extsettingseditor.s').read_text()}
 def change(path,old,new):
  text=replacements.get(path,(ROOT/path).read_text());assert text.count(old)==1,(path,old,text.count(old));replacements[path]=text.replace(old,new)
 change('src/app/extsettingseditor.s','    call ext_has_metadata\n','    call eb_metadata_predicate\n')
 for path,names in [('src/mem.s',['mem_alloc','mem_alloc_try','mem_free']),('src/sys.s',['file_read_all','file_read_all_extra','file_write_all']),('src/app/ext.s',['ext_send','ext_flush'])]:
  for name in names:change(path,'FN '+name+'\n','FN '+name+'\n    cmp qword ptr [rip + av_read_poison], 0\n    jne av_poison_fail\n')
 if mutation=='ext-alignment':change('src/app/extsettingseditor.s','    test rdx, rdx\n    jnz .Lsem_bad','    xor edx, edx\n    jnz .Lsem_bad')
 elif mutation=='sd-alignment':change('src/app/extsettingseditor.s','    test rdx, rdx\n    jnz .Lsev_bad','    xor edx, edx\n    jnz .Lsev_bad')
 elif mutation=='schema-cap':change('src/app/extsettingseditor.s','    cmp [r13 + EP_ext + EXT_sdefs + VEC_cap], rax','    cmp rax, rax')
 elif mutation=='metadata-refusal':change('src/app/extsettingseditor.s','    cmp eax, 1\n    jne .Lsem_stale','    cmp eax, eax\n    jne .Lsem_stale')
 elif mutation=='sd-value-fallback':change('src/app/extsettingseditor.s','    call ext_settings_effective_value\n','    mov rax, [rsi + EP_ext + EXT_sdefs + VEC_ptr]\n    mov rax, [rax + SD_value]\n    xor edx, edx\n    mov ecx, 4\n')
 elif mutation=='zero-index':change('src/app/extsettingseditor.s','    mov r8, rax\n    mov rax, r12','    xor r8d, r8d\n    mov rax, r12')
 elif mutation=='zero-length':change('src/app/extsettingseditor.s','    call ext_settings_effective_value\n','    call ext_settings_effective_value\n    xor ecx, ecx\n')
 elif mutation=='zero-flags':change('src/app/extsettingseditor.s','    call ext_settings_effective_flags\n','    xor eax, eax\n    xor edx, edx\n    xor ecx, ecx\n')
 if mutation=='resolver-model-gate':
  change('src/app/extsettingseditor.s','FN ext_setting_resolve\n    PROLOGUE\n','FN ext_setting_resolve\n    PROLOGUE\n    call settings_active_model\n    test rax, rax\n    jnz 9f\n    mov rax, -11\n    xor edx, edx\n    xor ecx, ecx\n    xor r8d, r8d\n    EPILOGUE\n9:\n')
 elif mutation=='resolver-uncleared-error':
  change('src/app/extsettingseditor.s','.Lsev_meta_error:\n    xor edx, edx\n    xor ecx, ecx\n    xor r8d, r8d\n','.Lsev_meta_error:\n    xor edx, edx\n    xor ecx, ecx\n')
 if mutation in ['real-ignore-visibility','real-ignore-identity']:
  visibility=(ROOT/'src/app/extvisibility.s').read_text()
  name='ext_is_visible' if mutation=='real-ignore-visibility' else 'ext_host_identity_matches'
  marker='FN '+name+'\n'
  assert visibility.count(marker)==1
  replacements['src/app/extvisibility.s']=visibility.replace(marker,marker+'    mov eax, 1\n    ret\n')
 for text in [fixture,*replacements.values()]:assert not re.search(r'(?m)^\s*\.section \.rodata[^\s\n]',text)
 return b.build(folder,fixture,replacements,windows=windows)
def check(exe,mutation=None):
 r=subprocess.run(([a.wine] if a.wine else [])+[str(exe)],cwd=ROOT,capture_output=True,timeout=90)
 if mutation:assert r.returncode=={**CODES,**REAL_CODES}[mutation],(mutation,r.returncode,r.stdout,r.stderr)
 else:assert r.returncode==0 and r.stdout==b'ok installed settings authority and canonical dirty overlays\n' and not r.stderr,(r.returncode,r.stdout,r.stderr)
with tempfile.TemporaryDirectory(prefix='rhun-settings-editor-') as t:
 f=Path(t)
 if a.negative_controls:
  check(build(f/'baseline'))
  for m in [*CODES,*(REAL_CODES if a.real_metadata else [])]:check(build(f/m,m),m);print('ok settings editor input-order negative control '+m,flush=True)
 else:
  e=a.exe if a.exe and not a.build_only else build(f,a.mutation)
  if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(e,a.exe);print('built '+('actual metadata' if a.real_metadata else 'predicate-double')+' settings editor fixture: '+str(a.exe));sys.exit(0)
  check(e,a.mutation);print('ok actual HI, metadata withdrawal and settings bridge' if a.real_metadata else 'ok predicate-double settings editor ordering and active reads',flush=True)
