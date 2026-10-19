#!/usr/bin/env python3
"""Actual failed allocator unmaps must retain native owners until consumed."""
import argparse, importlib.util, os
from pathlib import Path
import subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
def build(folder, mode, windows=False, negative=False):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    memory=(ROOT/'src/mem.s').read_text().replace('    SYS SYS_munmap\n','    call '+('ncu_munmap'if mode in(12,13)else'ncf_munmap')+'\n')
    if mode in(12,13):
        memory=memory.replace('FN mem_alloc_try\n','FN ncu_real_alloc\n')
    assert memory.count('call '+('ncu_munmap'if mode in(12,13)else'ncf_munmap'))==1
    relative='src/win/extstorejob.s'if windows else'src/app/extstorejobposix.s'
    native=(ROOT/relative).read_text().replace('FN ext_store_job_native_close\n','FN ncf_real_close\n')
    replacements={'src/mem.s':memory}
    if mode==16:
        a=native.index('FN ext_store_job_native_free');z=native.index('FN ncf_real_close',a)
        native=native[:a]+native[a:z].replace('API CloseHandle'if windows else'SYS SYS_close','call ncf_temp_close')+native[z:]
    if negative=='precedence':
        old='    mov rdi, [rbx + ESJ_work]\n    call prep_cleanup_free'
        assert native.count(old)==1
        native=native.replace(old,'    xor r13d, r13d\n'+old,1)
    if mode not in(12,13):replacements[relative]=native
    if negative=='reason':
        core=(ROOT/'src/app/extsettingsnative.s').read_text()
        old='    mov ecx, 1\n'
        assert core.count(old)==1
        replacements['src/app/extsettingsnative.s']=core.replace(old,'    xor ecx, ecx\n',1)
    if negative is True:
        cleanup=(ROOT/'src/app/extprepareretirealloc.s').read_text()
        old='    inc qword ptr [rip + g_mem_live]\n    xor edx, edx'
        assert cleanup.count(old)==1
        replacements['src/app/extprepareretirealloc.s']=cleanup.replace(old,'    mov edx, 1',1)
    fixture='.equ NCF_MODE, %d\n'%mode+(ROOT/('tests/faults/native_cleanup_unpack.s'if mode in(12,13)else'tests/faults/native_cleanup.s')).read_text()
    return builder.build(folder,fixture,replacements,windows)
def main():
    p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args()
    windows=bool(a.wine)or a.windows_build or os.name=='nt'
    modes=list(range(17)) if windows else [0,1,5,6,7,8,9,10,11,12,13,14,15,16]
    with tempfile.TemporaryDirectory(prefix='rhun-native-cleanup-')as folder:
        for mode in modes:
            exe=build((a.build_only or Path(folder))/str(mode),mode,windows)
            if a.build_only:continue
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert r.returncode==0 and not r.stdout and not r.stderr,(mode,r)
            print('ok native-cleanup/retained-unmap-retry/'+str(mode),flush=True)
        exe=build((a.build_only or Path(folder))/'negative',0,windows,True)
        if not a.build_only:
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert r.returncode==73,(r,)
            print('ok native-cleanup/negative-control/consumed-without-unmap',flush=True)
        exe=build((a.build_only or Path(folder))/'negative-precedence',16,windows,'precedence')
        if not a.build_only:
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert r.returncode==73,(r,)
            print('ok native-cleanup/negative-control/overwritten-first-close-error',flush=True)
        exe=build((a.build_only or Path(folder))/'negative-reason',0,windows,'reason')
        if not a.build_only:
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert r.returncode==73,(r,)
            print('ok native-cleanup/negative-control/misclassified-retirement-reason',flush=True)
if __name__=='__main__':main()
