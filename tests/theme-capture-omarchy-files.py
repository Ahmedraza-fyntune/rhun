#!/usr/bin/env python3
"""Actual bounded Omarchy sources and raw proof vectors."""
import argparse,hashlib,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);a=p.parse_args()
 win=bool(a.wine)or os.name=='nt';exe=ROOT/('build/windows/theme_capture_omarchy_io_test.exe'if win else'build/theme_capture_omarchy_io_test')
 def record(state,data=b''):
  return struct.pack('<QQ',state,len(data))+ (hashlib.sha256(data).digest()if state==1 else bytes(32))
 with tempfile.TemporaryDirectory(prefix='rhun-omcapture-',dir=a.wine_drive_root)as td:
  directory=Path(td).resolve();(directory/'theme').mkdir();native='C:/'+directory.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine and a.wine_drive_root else'Z:'+str(directory)if a.wine else str(directory)
  def run(scope,name=None,colors=None,marker=False,expected=0):
   for rel,data in [('theme.name',name),('theme/colors.toml',colors),('theme/light.mode',b''if marker else None)]:
    path=directory/rel
    if path.is_dir()and not path.is_symlink():path.rmdir()
    elif path.exists()or path.is_symlink():path.unlink()
    if rel=='theme/light.mode'and marker=='directory':path.mkdir()
    elif data is not None:path.write_bytes(b'nonempty marker contents'if rel=='theme/light.mode'and marker=='nonempty'else data)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native,str(scope)],capture_output=True,timeout=15)
   assert r.returncode==0 and not r.stderr,(scope,r)
   primary,cleanup=struct.unpack_from('<qq',r.stdout);assert(primary,cleanup)==(expected,0),(primary,cleanup,expected,r)
   b=r.stdout[16:256];assert len(b)==240
   if expected:
    assert b==bytes(240)and len(r.stdout)==256;return
   ptr,rawlen,length,light,presence,outscope=struct.unpack_from('<6Q',b)
   raw=name or b'';effective=raw.rstrip(bytes(range(33))).split(b'\0',1)[0]
   assert(rawlen,length,outscope)==(len(raw),len(effective),scope)
   assert bool(ptr)==(name is not None)
   assert r.stdout[256:]==raw
   assert b[224:]==bytes(16)
   light_from_colors=False
   # Expected cases keep parsing oracle explicit rather than mirroring the parser.
   if colors in (b'mode=light\n',b'[one]\nmode=daylight\nmode=dark\n'):light_from_colors=True
   used_marker=scope==2 and not light_from_colors
   expected_light=int(bool(scope==2 and(light_from_colors or marker)))
   expected_presence=int(name is not None)|(2 if scope==2 and colors is not None else 0)|(8 if used_marker else 0)|(4 if used_marker and marker else 0)
   assert(light,presence)==(expected_light,expected_presence),(light,presence,expected_light,expected_presence)
   recs=record(int(name is not None),raw)
   recs+=record(2)if scope==1 else record(int(colors is not None),colors or b'')
   recs+=record(2)if not used_marker else struct.pack('<QQ',int(bool(marker)),0)+(hashlib.sha256(b'\1').digest()if marker else bytes(32))
   assert b[80:224]==recs
   proof=hashlib.sha256(b'RHUN_OMARCHY_CAPTURE_V2\0'+struct.pack('<QQ',scope,len(os.fsencode(native)))+os.fsencode(native)+recs).digest()
   assert b[48:80]==proof
  for scope in(1,2):
   run(scope);run(scope,b'');run(scope,b'catppuccin\n');run(scope,b'name \0ignored\n',b'mode=light\n',True)
  run(2,b'gruvbox',b'mode=dark\n',True)
  run(2,b'name',b'',True)
  run(2,b'name',b'mode=dark\n','nonempty')
  run(2,b'name',b'mode=dark\n','directory')
  run(2,b'rose-pine',b'[one]\nmode=daylight\nmode=dark\n',False)
  run(2,b'name',b'mode=Light\n',False)
  run(2,b'x'*4096,b'c'*65536,True)
  run(1,b'x'*4097,expected=-27)
  run(2,b'name',b'x'*65537,expected=-27)
  # A source irrelevant to name-only capture must never be opened or classified.
  (directory/'theme/colors.toml').unlink();(directory/'theme/colors.toml').mkdir()
  r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native,'1'],capture_output=True,timeout=15)
  assert r.returncode==0 and struct.unpack_from('<qq',r.stdout)==(0,0),(r,)
 print('ok theme-capture-omarchy/actual-sources-bounds-modes-unused-isolation-and-proof',flush=True)
if __name__=='__main__':main()
