import argparse,hashlib,os,pathlib,queue,struct,subprocess,tempfile,threading,time,sys,re,shutil,importlib.util
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--exe',type=pathlib.Path);p.add_argument('--build-only',action='store_true');p.add_argument('--deadlines',action='store_true');p.add_argument('--faults',action='store_true');a=p.parse_args()
JOB=17;TAG=struct.pack('<QQ',JOB,29)+bytes(range(16));CAP=1048576+16384

def build_fixture(platform,folder,faults):
 builder=None;objects=[]
 if platform=='windows':
  spec=importlib.util.spec_from_file_location('worker_windows_builder',ROOT/'tools/build-windows.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
 paths=[('fixture',ROOT/'tests/ext_settings_worker_test.s')]
 if faults:paths.append(('memory',ROOT/'src/mem.s'))
 for name,path in paths:
  text=path.read_text()
  if name=='memory':
   assert text.count('FN mem_alloc_try')==1;text=text.replace('FN mem_alloc_try','FN sw_real_mem_alloc_try')
  if builder:text=re.sub(r'(?m)^\.section \.rodata$', '.section .rdata,"dr"',text)
  source=folder/(name+'.s');source.write_text(text);obj=source.with_suffix('.obj' if builder else '.o')
  definitions=['TEST_SETTINGS_WORKER_ALLOC_FAULT'] if faults and name=='fixture' else []
  if platform=='macos':
   translated=folder/(name+'-a64.s');cmd=[sys.executable,ROOT/'tools/arm64.py','-I',ROOT/'src','-D','MACOS']
   for definition in definitions:cmd+=['-D',definition]
   subprocess.run([*cmd,source,translated],check=True,timeout=120);cmd=['as','-arch','arm64','-mmacosx-version-min=12.0','-o',obj,translated]
  elif builder:
   cmd=[builder.tool('llvm-mc'),'-triple=x86_64-pc-windows-msvc','-filetype=obj','-defsym=WINDOWS=1','-I',ROOT/'src','-I',ROOT/'src/win']
   for definition in definitions:cmd+=['-defsym='+definition+'=1']
   cmd += [source,'-o',obj]
  else:
   cmd=['as','--64','-I',ROOT/'src']
   for definition in definitions:cmd += ['--defsym',definition+'=1']
   cmd += ['-o',obj,source]
  subprocess.run(cmd,check=True,timeout=120);objects.append(obj)
 excluded={'src/main.s'}
 if faults:excluded.add('src/mem.s')
 if platform!='linux':excluded.update(['src/start.s','src/plat/wayland.s','src/plat/x11.s','src/plat/appearance.s'])
 build=ROOT/('build/windows' if builder else 'build/obj')
 for path in sorted((ROOT/'src').rglob('*.s')):
  relative=path.relative_to(ROOT).as_posix()
  if relative in excluded or relative.startswith('src/mac/') and platform!='macos' or relative.startswith('src/win/') and not builder:continue
  name=relative.replace('/','_');obj=build/(name+'.obj' if builder else name[:-2]+'.o')
  if not obj.is_file():raise AssertionError('build current runtime first: '+str(obj))
  objects.append(obj)
 assets=build/('build_windows_assets.s.obj' if builder else 'build_assets.o');assert assets.is_file();objects.append(assets)
 exe=folder/('ext-settings-worker.exe' if builder else 'ext-settings-worker')
 if platform=='macos':
  cmd=['clang','-arch','arm64','-mmacosx-version-min=12.0','-o',exe,*objects]
  for framework in ['AppKit','QuartzCore','IOSurface','CoreServices','Carbon']:cmd+=['-framework',framework]
 elif builder:
  libs=[build/(p.stem+'.lib') for p in sorted((ROOT/'src/win').glob('*.def'))]
  cmd=[builder.tool('lld-link'),'/nodefaultlib','/entry:win_start','/subsystem:console,6.02','/stack:33554432,33554432','/dynamicbase','/nxcompat','/largeaddressaware','/out:'+str(exe),*objects,*libs,build/'rhun.res']
 else:cmd=['ld','-static','-nostdlib','--no-dynamic-linker','-z','noexecstack','-o',exe,*objects]
 subprocess.run(cmd,check=True,timeout=120);return exe

if a.build_only and not a.exe:p.error('--build-only requires --exe output')
platform='windows' if os.name=='nt' or a.build_only and a.exe.suffix.lower()=='.exe' else 'macos' if sys.platform=='darwin' else 'linux'
fixture_temporary=None
if a.build_only or a.faults and not a.exe:
 fixture_temporary=tempfile.TemporaryDirectory(prefix='rhun-settings-worker-fixture-')
 built=build_fixture(platform,pathlib.Path(fixture_temporary.name),a.faults)
 if a.build_only:
  a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(built,a.exe);print('built settings worker fixture: '+str(a.exe),flush=True);sys.exit(0)
 a.exe=built
elif not a.exe:a.exe=ROOT/('build/windows/ext_settings_worker_test.exe' if platform=='windows' else 'build/ext_settings_worker_test')
a.exe=a.exe.resolve()


def frame(k,b=b'',r=0):return b'RHECJOB1'+struct.pack('<II',1,k)+TAG+struct.pack('<QQ',len(b),r)+b

def delta(sec=b'owner/tool',key=b'pinned',val=b'yes',remove=0):return struct.pack('<IIII',len(sec),len(key),len(val),remove)+sec+key+val

def request(path,mode=1,deltas=(),flags=0,exists=0,digest=bytes(32)):
 x=str(path).encode();return frame(1,struct.pack('<IIIIQ',mode,len(deltas),len(x),flags,exists)+digest+x+b''.join(deltas))

class Worker:
 def __init__(self):
  self.p=subprocess.Popen([a.exe,'--extension-settings-worker','v1',str(JOB),'29',bytes(range(16)).hex()],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
  self.q=queue.Queue();self.buf=bytearray();self.received=0
  def pump():
   try:
    while True:
     x=os.read(self.p.stdout.fileno(),65536);self.received+=len(x);self.q.put(x)
     if not x:return
   except OSError:self.q.put(b'')
  self.reader=threading.Thread(target=pump,daemon=True);self.reader.start()
 def send(self,x):
  view=memoryview(x)
  while view:
   n=self.p.stdin.write(view)
   if not n:raise AssertionError('input closed')
   view=view[n:]
 def take(self,n):
  while len(self.buf)<n:
   x=self.q.get(timeout=20)
   if not x:raise AssertionError(('truncated output',n,len(self.buf),self.p.poll()))
   self.buf.extend(x)
  x=bytes(self.buf[:n]);del self.buf[:n];return x
 def read(self):
  h=self.take(64);assert h[:8]==b'RHECJOB1' and struct.unpack_from('<I',h,8)[0]==1 and h[16:48]==TAG,h
  k=struct.unpack_from('<I',h,12)[0];n,r=struct.unpack_from('<QQ',h,48);assert n<=CAP
  return k,r,self.take(n)
 def tail(self):
  self.reader.join(timeout=2);assert not self.reader.is_alive()
  tail=bytes(self.buf);self.buf.clear()
  while not self.q.empty():tail+=self.q.get_nowait()
  return tail
 def done(self,status=0):
  self.p.stdin.close();assert self.p.wait(timeout=20)==status
  tail=self.tail();err=self.p.stderr.read();assert not tail and not err,(tail[:100],err)
 def cleanup(self):
  if self.p.poll() is None:
   try:self.p.stdin.close()
   except OSError:pass
   try:self.p.wait(timeout=12)
   except subprocess.TimeoutExpired:self.p.kill();self.p.wait(timeout=10)
  self.reader.join(timeout=2)
  for stream in [self.p.stdin,self.p.stdout,self.p.stderr]:stream.close()
 def __enter__(self):return self
 def __exit__(self,*unused):self.cleanup()

def snapshot(b):
 ex,res,n=struct.unpack_from('<IIQ',b);assert ex<=1 and res==0 and n==len(b)-48 and b[16:48]==hashlib.sha256(b[48:]).digest();assert ex or n==0
 return ex,b[48:]

def read(path,error=None):
 with Worker() as w:
  w.send(request(path));k,r,b=w.read()
  if error is None:
   assert (k,r)==(2,0);s=snapshot(b);k,r,b=w.read();assert (k,r)==(8,0) and struct.unpack('<4q',b)==(1,0,0,0)
  else:
   assert (k,r)==(8,0);result=struct.unpack('<4q',b);assert result[0]==2 and result[1]<0,(result,error)
   if error!=True:assert result[1]==error,result
   s=None
  w.done();return s

def committed(w,round):
 k,r,b=w.read();assert (k,r)==(6,round);result=struct.unpack_from('<4q',b);assert result[:2]==(3,0),result
 return snapshot(b[32:])[1]

def release(w,round,state=3,primary=0,cleanup=0):
 w.send(frame(7,r=round));k,r,b=w.read();assert (k,r)==(8,round) and struct.unpack('<4q',b)==(state,primary,cleanup,0),(k,r,struct.unpack('<4q',b));w.done()

if a.faults:
 with tempfile.TemporaryDirectory(prefix='rhun-settings-worker-allocation-') as td:
  cfg=pathlib.Path(td).resolve()/'cfg';cfg.mkdir();ini=cfg/'extensions.ini';original=b'; retained\n[owner/tool]\npinned=no\nsetting.unknown=stay\n';ini.write_bytes(original)
  for JOB in range(1,129):
   TAG=struct.pack('<QQ',JOB,29)+bytes(range(16))
   with Worker() as w:
    try:w.send(request(cfg,2,[delta()]))
    except BrokenPipeError:pass
    kinds=[];terminal=False
    while True:
     try:k,r,b=w.read()
     except AssertionError:
      break
     kinds.append(k)
     if k==4:w.send(frame(9,r=r))
     elif k==10:w.send(frame(7,r=r))
     elif k==8:
      terminal=True;assert struct.unpack('<4q',b)[0] in (2,5) and struct.unpack('<4q',b)[1]<0;break
    try:w.p.stdin.close()
    except BrokenPipeError:pass
    status=w.p.wait(timeout=20)
    assert status in (0,1,2,91),(JOB,status,kinds)
    assert ini.read_bytes()==original and not list(cfg.glob('.extensions-*.pending')),(JOB,kinds)
    assert not w.tail() and not w.p.stderr.read()
    assert terminal if status in (0,91) else w.received==0
   if status==91:
    print(f'ok worker every allocation failure through {JOB-1} owned sites retains original bytes and frees all allocations',flush=True);break
  else:raise AssertionError('allocation enumeration did not finish')
else:
 with tempfile.TemporaryDirectory(prefix='rhun-settings-worker-') as temporary:
  root=pathlib.Path(temporary).resolve();cfg=root/'nested space'/'雪 folder'/'cfg';ini=cfg/'extensions.ini'
  assert read(cfg)==(0,b'') and not cfg.exists()
  print('ok worker absent READ creates no config directory',flush=True)
  with Worker() as w:
   w.send(request(cfg,2,[delta()]));k,r,b=w.read();assert (k,r)==(2,1) and snapshot(b)==(0,b'')
   k,r,b=w.read();assert (k,r)==(4,1) and len(b)==48 and not ini.exists()
   w.send(frame(5,r=1));body=committed(w,1);assert ini.read_bytes()==body==b'[owner/tool]\npinned=yes\n'
   read(cfg,error=True);release(w,1)
  original=b'; retained\n[removed/tool]\ndisabled=yes\n[owner/tool]\npinned=no\nsetting.unknown=stay\n[providers]\ncomplete.py=other/tool\n'
  ini.write_bytes(original)
  with Worker() as w:
   w.send(request(cfg,2,[delta()]));k,r,b=w.read();assert (k,r)==(2,1) and snapshot(b)==(1,original)
   k,r,b=w.read();assert (k,r)==(4,1);w.send(frame(5,r=1));body=committed(w,1)
   assert body==original.replace(b'pinned=no',b'pinned=yes') and ini.read_bytes()==body
   release(w,1)
  print('ok worker gated SAVE, native publication, preservation and retained EX contention',flush=True)
  before=ini.read_bytes()
  with Worker() as w:
   w.send(request(cfg,3));k,r,b=w.read();assert (k,r)==(2,0) and snapshot(b)==(1,before)
   read(cfg,error=True);release(w,0,state=1)
  assert ini.read_bytes()==before
  print('ok worker no-delta TX retains guard and leaves bytes unchanged',flush=True)
  with Worker() as w:
   w.send(request(cfg,3));k,r,b=w.read();assert (k,r)==(2,0)
   w.send(frame(3,struct.pack('<II',1,0)+delta(val=b'first'),1));assert w.read()[:2]==(4,1)
   w.send(frame(9,r=1));k,r,b=w.read();assert (k,r)==(10,1) and struct.unpack('<4q',b)==(6,0,0,0) and ini.read_bytes()==before
   w.send(frame(3,struct.pack('<II',1,0)+delta(val=b'second'),2));assert w.read()[:2]==(4,2)
   w.send(frame(5,r=2));body=committed(w,2);assert ini.read_bytes()==body and b'pinned=second\n' in body
   w.send(frame(3,struct.pack('<II',1,0)+delta(key=b'disabled'),3));assert w.read()[:2]==(4,3)
   w.send(frame(5,r=3));body=committed(w,3);assert ini.read_bytes()==body and b'disabled=yes\n' in body
   w.send(frame(3,struct.pack('<II',1,0)+delta(),4));k,r,b=w.read();assert (k,r)==(8,3) and struct.unpack('<4q',b)==(3,0,-71,0);w.done()
  assert ini.read_bytes()==body
  print('ok worker ABORT cleanup, same-guard rounds2/3 and fourth-round refusal',flush=True)
  before=ini.read_bytes()
  with Worker() as w:
   w.send(request(cfg,2,[delta(val=b'never')]));assert w.read()[:2]==(2,1);assert w.read()[:2]==(4,1)
   w.p.stdin.close();k,r,b=w.read();assert (k,r)==(8,1) and struct.unpack('<4q',b)[:2]==(2,-125)
   assert w.p.wait(timeout=20)==0 and not w.tail() and not w.p.stderr.read()
  assert ini.read_bytes()==before and not list(cfg.glob('.extensions-*.pending'))
  print('ok worker control EOF withdraws prepared candidate without publication',flush=True)
  ini.write_bytes(b'malformed line')
  with Worker() as w:
   w.send(request(cfg,2,[delta()]));k,r,b=w.read();assert (k,r)==(8,1) and struct.unpack('<4q',b)[:2]==(2,-22);w.done()
  assert ini.read_bytes()==b'malformed line';ini.write_bytes(before)
  with Worker() as w:
   wrong=hashlib.sha256(b'wrong').digest();w.send(request(cfg,2,[delta()],1,1,wrong));k,r,b=w.read();assert (k,r)==(8,1) and struct.unpack('<4q',b)[:2]==(2,-116);w.done()
  assert ini.read_bytes()==before
  print('ok worker malformed file and stale accepted baseline refuse overwrite',flush=True)
  bad=root/'must not exist'/'..'/'cfg'
  with Worker() as w:
   w.send(request(bad,2,[delta()]));w.p.stdin.close();assert w.p.wait(timeout=20)==2 and not w.tail() and w.received==0 and not w.p.stderr.read()
  assert not (root/'must not exist').exists()
  print('ok worker validates entire path before directory creation',flush=True)
  bad_file=root/'blocking-file';bad_file.write_bytes(b'unchanged')
  with Worker() as w:
   w.send(request(bad_file/'cfg',2,[delta()]));k,r,b=w.read();assert (k,r)==(8,1) and struct.unpack('<4q',b)[:2]==(2,-20);w.done()
  assert bad_file.read_bytes()==b'unchanged'
  print('ok worker early SAVE opening failure retains round1 and precise errno',flush=True)
  if a.deadlines:
   with Worker() as w:
    w.send(request(cfg,3));assert w.read()[:2]==(2,0);time.sleep(10.3);read(cfg,error=True);release(w,0,state=1)
   with Worker() as w:
    w.send(request(cfg,2,[delta(val=b'expired')]));assert w.read()[:2]==(2,1);assert w.read()[:2]==(4,1);k,r,b=w.read();assert (k,r)==(8,1) and struct.unpack('<4q',b)[:2]==(2,-110);w.done()
   assert ini.read_bytes()==before and not list(cfg.glob('.extensions-*.pending'))
   print('ok worker retained hold exceeds10s, PREPARED expires without publication',flush=True)
 
 with tempfile.TemporaryDirectory(prefix='rhun-settings-worker-adversarial-') as td:
  root=pathlib.Path(td).resolve();cfg=root/'cfg';cfg.mkdir();ini=cfg/'extensions.ini';before=b'[owner/tool]\npinned=no\n'
  ini.write_bytes(before)
  for trailing in [b'!',request(cfg),frame(5,r=0)]:
   with Worker() as w:
    w.send(request(cfg)+trailing);k,r,b=w.read();assert (k,r)==(8,0) and struct.unpack('<4q',b)[:2]==(2,-71);w.done()
   assert ini.read_bytes()==before
  with Worker() as w:
   w.send(request(cfg));w.p.stdin.close();assert w.read()[:2]==(2,0);k,r,b=w.read();assert (k,r)==(8,0) and struct.unpack('<4q',b)==(1,0,0,0);assert w.p.wait(timeout=20)==0 and not w.tail() and not w.p.stderr.read()
  print('ok worker READ rejects trailing input and accepts complete request plus EOF',flush=True)
  for trailing in [b'!',frame(7,r=0),frame(3,struct.pack('<II',1,0)+delta(),1)]:
   with Worker() as w:
    w.send(request(cfg,3));assert w.read()[:2]==(2,0);w.send(frame(7,r=0)+trailing);k,r,b=w.read();assert (k,r)==(8,0) and struct.unpack('<4q',b)[:2]==(2,-71);w.done()
  for prepared in [True,False]:
   with Worker() as w:
    w.send(request(cfg,2,[delta()]));assert w.read()[:2]==(2,1);assert w.read()[:2]==(4,1)
    if not prepared:
     w.send(frame(5,r=1));committed(w,1)
    w.send(frame(7,r=1)+b'!');k,r,b=w.read();result=struct.unpack('<4q',b);assert (k,r)==(8,1)
    assert result==((2,-71,0,0) if prepared else (3,0,-71,0)),result;w.done()
   if not prepared:ini.write_bytes(before)
  print('ok worker RELEASE rejects trailing input, preserves earlier committed proof',flush=True)
  for command in [frame(5,r=1)[:17],frame(5,r=2),frame(3,struct.pack('<II',1,0)+delta(),1),frame(5,r=1)+b'!']:
   with Worker() as w:
    w.send(request(cfg,2,[delta()]));assert w.read()[:2]==(2,1);assert w.read()[:2]==(4,1)
    w.send(command);w.p.stdin.close();k,r,b=w.read();assert (k,r)==(8,1) and struct.unpack('<4q',b)[0]==2,(k,r,b)
    assert w.p.wait(timeout=20)==0 and not w.tail() and not w.p.stderr.read()
   assert ini.read_bytes()==before and not list(cfg.glob('.extensions-*.pending'))
  print('ok worker partial/invalid/extra COMMIT refuses publication',flush=True)
  for cut in [1,63,64,100]:
   with Worker() as w:
    w.send(request(cfg,2,[delta()])[:cut]);w.p.stdin.close();assert w.p.wait(timeout=20)==2 and not w.tail() and w.received==0 and not w.p.stderr.read()
   assert ini.read_bytes()==before
  print('ok worker incomplete initial frames refuse all file changes',flush=True)
  raw=b';'+b'x'*(1048576-128)+b'\n'+before;ini.write_bytes(raw)
  with Worker() as w:
   w.send(request(cfg,2,[delta()]));k,r,b=w.read();assert (k,r)==(2,1) and snapshot(b)==(1,raw)
   assert w.read()[:2]==(4,1);w.send(frame(5,r=1));merged=committed(w,1);assert merged==raw.replace(b'pinned=no',b'pinned=yes') and ini.read_bytes()==merged;release(w,1)
  print('ok worker near1MiB framing and exact unrelated-byte preservation',flush=True)
  ini.write_bytes(b';'+b'x'*1048576)
  with Worker() as w:
   w.send(request(cfg,2,[delta()]));k,r,b=w.read();assert (k,r)==(8,1) and struct.unpack('<4q',b)[0]==2;w.done()
  assert ini.stat().st_size==1048577
  print('ok worker oversized file preserved and refused',flush=True)
  # A strict rooted traversal must refuse a symlink ancestor, including READ.
  target=root/'target';target.mkdir();(target/'extensions.ini').write_bytes(before);link=root/'link'
  if os.name=='nt':subprocess.run(['cmd','/d','/c','mklink','/J',str(link),str(target)],check=True,capture_output=True,timeout=20)
  else:link.symlink_to(target,target_is_directory=True)
  for mode in [1,2,3]:
   with Worker() as w:
    w.send(request(link/'child',mode,[delta()] if mode==2 else []));k,r,b=w.read();assert k==8 and struct.unpack('<4q',b)[0]==2;w.done()
  assert not (target/'child').exists() and (target/'extensions.ini').read_bytes()==before
  print('ok worker READ/SAVE/TX reject linked ancestors without creation',flush=True)
