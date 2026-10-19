import argparse,importlib.util,os,pathlib,shutil,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--kind',choices=['fake','pending','real'],default='fake');p.add_argument('--exe',type=pathlib.Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--negative-controls',action='store_true');p.add_argument('--mutation',choices=['immediate','live-backoff']);p.add_argument('--temp-root',type=pathlib.Path);p.add_argument('--virtual-root');a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe')
if a.negative_controls and (a.exe or a.build_only or a.mutation):p.error('--negative-controls builds baseline and controls')
if a.mutation and a.kind!={'immediate':'fake','live-backoff':'pending'}[a.mutation]:p.error('--mutation requires its matching fixture kind')
if a.wine and bool(a.temp_root)!=bool(a.virtual_root):p.error('Wine custom temporary storage requires both --temp-root and --virtual-root')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')

def build(folder,kind,mutation=None):
 spec=importlib.util.spec_from_file_location('retirement_fixture_builder',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 if kind=='real':return real_build(folder,b)
 modules=['extsettingsmemory','extsettingsframe','extsettingsjob','extsettingsjobframes','extsettingsjobcommon','extsettingsjobio','extsettingsjobstep']
 replacements={}
 for name in modules:
  text=(ROOT/'src/app'/(name+'.s')).read_text()
  for suffix in ['start','read','write_begin','write_poll','close_input','poll','kill','free']:text=text.replace('ext_settings_native_'+suffix,('ecrf_' if kind=='fake' else 'ecnf_')+suffix)
  if kind=='fake' and name=='extsettingsjob':text=text.replace('call time_ms','call ecrf_time')
  if mutation=='immediate' and name=='extsettingsjobstep':
   old='    cmp rax, [rbx + ECJ_retry_due]\n    jb .Lecjp_return';assert text.count(old)==1;text=text.replace(old,old.replace('    jb .Lecjp_return','    nop'))
  if mutation=='live-backoff' and name=='extsettingsjobstep':
   old='    cmp r13, 1\n    je .Lecjp_cleanup_delay';assert text.count(old)==1;text=text.replace(old,'    jmp .Lecjp_cleanup_delay')
  replacements['src/app/'+name+'.s']=text
 fixture=(ROOT/'tests'/('ext_settings_retire_test.s' if kind=='fake' else 'ext_settings_job_fault_test.s')).read_text()
 return b.build(folder,fixture,replacements,windows=windows)

def real_build(folder,b):
 names=['extsettingsmemory','extsettingsframe','extsettingsjob','extsettingsjobframes','extsettingsjobcommon','extsettingsjobio','extsettingsjobstep']
 replacements={}
 for name in names:
  text=(ROOT/'src/app'/(name+'.s')).read_text()
  for suffix in ['start','read','write_begin','write_poll','close_input','poll','kill','free']:text=text.replace('call ext_settings_native_'+suffix,'call ecrr_'+suffix)
  replacements['src/app/'+name+'.s']=text
 native=(ROOT/'src/app/extsettingsnative.s').read_text();assert native.count('call prep_cleanup_free')==1
 replacements['src/app/extsettingsnative.s']=native.replace('call prep_cleanup_free','call ecrr_self_cleanup')
 fixture=(ROOT/'tests/ext_settings_job_test.s').read_text()
 old='.Lecjt_parent:\n';assert fixture.count(old)==1;fixture=fixture.replace(old,old+'    mov qword ptr [rip + ecrr_failures], 3\n')
 old='.Lecjt_loop:\n';assert fixture.count(old)==1
 fixture=fixture.replace(old,old+'''    cmp qword ptr [r12 + ECJ_cleanup_only], 0
    je 1f
    cmp qword ptr [r12 + ECJ_reservation], ESM_NATIVE_RESERVE
    jne ecjt_fail
    cmp qword ptr [r12 + ECJ_native], 0
    je ecjt_fail
1:
''')
 old='.Lecjt_terminal:\n';assert fixture.count(old)==1
 fixture=fixture.replace(old,old+'''    cmp qword ptr [rip + ecrr_failures], 0
    jne ecjt_fail
    cmp qword ptr [rip + ecrr_unmaps], 4
    jne ecjt_fail
    cmp qword ptr [rip + ecrr_claimed], 1
    jne ecjt_fail
    cmp qword ptr [r12 + ECJ_reservation], 0
    jne ecjt_fail
''')
 fixture+='''
.bss
.p2align 3
ecrr_scope: .quad 0
ecrr_failures: .quad 0
ecrr_unmaps: .quad 0
ecrr_claimed: .quad 0
.text
FN ecrr_self_cleanup
    PROLOGUE
    mov qword ptr [rip + ecrr_scope], 1
    call prep_cleanup_free
    mov qword ptr [rip + ecrr_scope], 0
    EPILOGUE
FN ecrr_free
    PROLOGUE
    call ext_settings_native_free
    test rdx, rdx
    jnz 2f
    cmp rcx, 1
    jne 1f
    mov qword ptr [rip + ecrr_claimed], 1
1:  EPILOGUE
2:  cmp rcx, 0
    jne ecjt_fail
    EPILOGUE
'''
 for suffix in ['start','read','write_begin','write_poll','close_input','poll','kill']:
  fixture+='\nFN ecrr_'+suffix+'\n    cmp qword ptr [rip + ecrr_claimed], 0\n    jne ecjt_fail\n    jmp ext_settings_native_'+suffix+'\n'
 mem=(ROOT/'src/mem.s').read_text()
 if windows:
  sys=(ROOT/'src/win/sys.s').read_text();assert sys.count('API VirtualFree')==1
  replacements['src/win/sys.s']=sys.replace('API VirtualFree','call ecrr_virtual_free')
  fixture+='''
FN ecrr_virtual_free
    cmp qword ptr [rip + ecrr_scope], 0
    je 2f
    inc qword ptr [rip + ecrr_unmaps]
    cmp qword ptr [rip + ecrr_failures], 0
    je 2f
    dec qword ptr [rip + ecrr_failures]
    mov ecx, 1
2:  jmp [rip + __imp_VirtualFree]
'''
 else:
  assert mem.count('SYS SYS_munmap')==1;replacements['src/mem.s']=mem.replace('SYS SYS_munmap','call ecrr_unmap')
  fixture+='''
FN ecrr_unmap
    cmp qword ptr [rip + ecrr_scope], 0
    je 2f
    inc qword ptr [rip + ecrr_unmaps]
    cmp qword ptr [rip + ecrr_failures], 0
    je 2f
    dec qword ptr [rip + ecrr_failures]
    mov edi, 1
2:  SYS SYS_munmap
    ret
'''
 return b.build(folder,fixture,replacements,windows=windows)

def real_check(exe):
 import hashlib,struct
 if a.wine:
  base=a.temp_root or pathlib.Path(os.environ.get('WINEPREFIX',str(pathlib.Path.home()/'.wine')))/'drive_c'/'rhun-settings-retire'
  virtual=a.virtual_root or 'C:/rhun-settings-retire'
 else:base=a.temp_root;virtual=a.virtual_root
 if base:base.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='case-',dir=base) as directory:
  root=pathlib.Path(directory).resolve();cfg=root/'cfg space 雪';cfg.mkdir();ini=cfg/'extensions.ini'
  original=b'; keep\n[owner/tool]\npinned=no\nsetting.unknown=remain\n[providers]\ncomplete.py=other/tool\n'
  path=str(virtual).rstrip('/')+'/'+root.name+'/'+cfg.relative_to(root).as_posix() if virtual else str(cfg)
  for mode in [1,2,14]:
   ini.write_bytes(original)
   command=([a.wine,'Z:'+exe.resolve().as_posix()] if a.wine else [str(exe.resolve())])+[path,str(mode),str(len(original)),hashlib.sha256(original).hexdigest()]
   r=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=35)
   assert r.returncode==0 and len(r.stdout)==64 and not r.stderr,(mode,r.returncode,r.stdout,r.stderr)
   result=struct.unpack('<8q',r.stdout)
   assert result[0]==(1 if mode==1 else 3) and result[1]==0 and result[2]<0 and result[3]==0,(mode,result)
   assert ini.read_bytes()==(original if mode==1 else original.replace(b'pinned=no',b'pinned=yes')),(mode,result)
   print('ok actual helper retained-native cleanup mode '+str(mode),flush=True)

def check(exe,kind,mutation=None):
 if kind=='real':return real_check(exe)
 command=[a.wine,'Z:'+exe.resolve().as_posix()] if a.wine else [str(exe.resolve())]
 r=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=40)
 if mutation:assert r.returncode==({'immediate':79,'live-backoff':75}[mutation]),(kind,mutation,r.returncode,r.stdout,r.stderr)
 else:
  expected=b'ok terminal cleanup retry ownership and cadence\n' if kind=='fake' else b'ok settings owned start failures and pending cleanup\n'
  assert r.returncode==0 and r.stdout==expected and not r.stderr,(kind,r.returncode,r.stdout,r.stderr)

with tempfile.TemporaryDirectory(prefix='rhun-settings-retire-') as temporary:
 folder=pathlib.Path(temporary)
 if a.negative_controls:
  for kind in ['fake','pending','real']:check(build(folder/kind,kind),kind)
  for kind,mutation in [('fake','immediate'),('pending','live-backoff')]:
   check(build(folder/mutation,kind,mutation),kind,mutation);print('ok retirement negative control '+mutation,flush=True)
 else:
  exe=a.exe.resolve() if a.exe and not a.build_only else build(folder,a.kind,a.mutation)
  if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(exe,a.exe);print('built settings retirement '+a.kind+' fixture',flush=True);sys.exit(0)
  check(exe,a.kind,a.mutation)
  print('ok settings retirement '+a.kind,flush=True)
