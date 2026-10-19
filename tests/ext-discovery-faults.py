#!/usr/bin/env python3
"""Exact-inventory discovery owner/candidate failure and negative-control gates."""
import argparse
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
ID=b'a'*64
def build(folder,mode,windows=False,mutation=None):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
    replacements={}
    for path,functions in {'src/mem.s':{'mem_alloc_try':'alloc'},'src/app/extvalidatepath.s':{'ext_root_open_at':'open','ext_root_identity':'identity','ext_root_close':'close','ext_root_open':'rootopen','ext_root_reopen_dir':'reopen','ext_root_stat':'stat','ext_root_read':'read'},'src/app/extstoreio.s':{'ext_store_raw_lock':'lock'}}.items():
        source=(ROOT/path).read_text()
        for public,alias in functions.items():
            old='FN '+public+'\n';assert source.count(old)==1
            source=source.replace(old,'FN edtf_real_'+alias+'\n')
        replacements[path]=source
    core=(ROOT/'src/app/extdiscovery.s').read_text()
    if mutation=='lease':core=core.replace('    call ext_store_raw_lock\n','    xor eax, eax\n',1)
    if mutation=='secondary':
        old='.Ledc_adapter_error:\n    test rdx, rdx\n    jns .Ledc_operation_error\n    mov r15, rdx'
        assert core.count(old)==1
        core=core.replace(old,'.Ledc_adapter_error:\n    test rdx, rdx\n    jns .Ledc_operation_error\n    xor r15d, r15d')
    if mutation=='shadow':
        old='    jl 1f\n    cmp qword ptr [rax + ESR_generation], 0'
        assert core.count(old)==1
        core=core.replace(old,'    jl 2f\n    cmp qword ptr [rax + ESR_generation], 0',1)
    if mutation=='proof':
        old='    cmp [r12 + ESS_proof_epoch], rax\n    jne .Led_begin_stale'
        assert core.count(old)==1
        core=core.replace(old,'    cmp [r12 + ESS_proof_epoch], rax',1)
        core=core.replace('    cmp [rdx + ESS_proof_epoch], rcx\n    jne 2f','    cmp [rdx + ESS_proof_epoch], rcx',1)
    if mutation=='epoch':
        a=core.index('FN ext_discovery_candidate_check');source=core[a:]
        old='    cmp [rax + ESG_epoch], rcx\n    jne .Ledc_check_stale';assert source.count(old)==1
        core=core[:a]+source.replace(old,'    cmp [rax + ESG_epoch], rcx',1)
    replacements['src/app/extdiscovery.s']=core
    fixture=(ROOT/'tests/ext_discovery_test.s').read_text()
    fixture=fixture.replace('    call ext_discovery_begin\n','    mov qword ptr [rip + edtf_stage], 1\n    call ext_discovery_begin\n    mov qword ptr [rip + edtf_stage], 0\n',1)
    fixture=fixture.replace('    call ext_discovery_step\n','    mov qword ptr [rip + edtf_stage], 2\n    call ext_discovery_step\n    mov qword ptr [rip + edtf_stage], 0\n',1)
    fixture=fixture.replace('    call ext_discovery_candidate_try\n','    mov qword ptr [rip + edtf_stage], 3\n    call ext_discovery_candidate_try\n    mov qword ptr [rip + edtf_stage], 0\n',1)
    if mode in (30,31,32):
        mutation={30:'    mov qword ptr [r14 + ESS_live], 129\n',31:'    mov qword ptr [r14 + ESS_proof_epoch], 0\n',32:'    mov rax, [r14 + ESS_entries + VEC_ptr]\n    mov qword ptr [rax + ESR_index + 24], 1\n'}[mode]
        old='    mov qword ptr [rip + edtf_stage], 1\n    call ext_discovery_begin'
        assert fixture.count(old)==1
        fixture=fixture.replace(old,mutation+old,1)
    if mode in (1,2,3,30,31,32):
        old='    test rax, rax\n    jz edt_fail\n    mov r13, rax\n    mov qword ptr [rsp + 336], 0'
        assert fixture.count(old)==1
        fixture=fixture.replace(old,'    test rax, rax\n    jnz edt_fail\n    cmp rdx, %d\n    jne edt_fail\n    mov [rsp + 352], rdx\n    mov [rsp + 360], rcx\n    mov qword ptr [rsp + 368], 0\n    mov qword ptr [rsp + 336], 0\n    mov rdi, r14\n    call ext_store_snapshot_free\n    jmp .Ledt_finish'%(-116 if mode==31 else -22 if mode in (30,32) else -12),1)
    if mode in (33,34):
        old='    mov qword ptr [rsp + 336], 0'
        size=3998 if mode==34 else 4095
        replacement='    mov rdi, [r13 + ED_rootpath]\n    call mem_free\n    mov edi, 4096\n    call mem_alloc_try\n    test rax, rax\n    jz edt_fail\n    mov [r13 + ED_rootpath], rax\n    mov rdi, rax\n    mov esi, 120\n    mov edx, %d\n    call memset\n    mov rax, [r13 + ED_rootpath]\n    mov byte ptr [rax], 47\n    mov byte ptr [rax + %d], 0\n'%(size,size)
        fixture=fixture.replace(old,replacement+old,1)
        if mode==34:
            fixture=fixture.replace('42: mov rdi, r13\n    call ext_discovery_detach','42: mov rdi, r13\n    xor esi, esi\n    call ext_discovery_row\n    mov rdi, [rax + EDR_path]\n    call strlen\n    cmp rax, 4095\n    jne edt_fail\n    mov rdi, r13\n    call ext_discovery_detach',1)
            old='    cmp qword ptr [rsp + 320], 100'
            fixture=fixture.replace(old,'    mov qword ptr [rsp + 320], 101\n'+old,1)
    if 22<=mode<=29:
        old='    mov qword ptr [rip + edtf_stage], 3\n    call ext_discovery_candidate_try'
        replacement='    mov [rip + edtf_guard], r12\n'
        if mode!=29:replacement+='    lea rax, [rip + edtf_cancel]\n    mov [r12 + ESG_cancel], rax\n'
        fixture=fixture.replace(old,replacement+old,1)
    if mode in (4,33,42):
        old='    test rax, rax\n    js edt_fail\n    jz 1b'
        assert fixture.count(old)==1
        fixture=fixture.replace(old,('    test rax, rax\n    jz 1b\n' if mode==42 else '')+'    cmp rax, %d\n    jne edt_fail\n    mov [rsp + 352], rax\n    mov qword ptr [rsp + 360], 0\n    mov qword ptr [rsp + 368], 0\n    mov rdi, r13\n    call ext_discovery_free\n    jmp .Ledt_finish\n    jz 1b'%(-36 if mode==33 else -12),1)
    if mode in (4,33,42):
        old='    mov [rsp + 352], rax\n    mov qword ptr [rsp + 360], 0\n    mov qword ptr [rsp + 368], 0\n    mov rdi, r13\n    call ext_discovery_free'
        expected=-36 if mode==33 else -12
        new='    mov [rsp + 352], rax\n    mov rdi, r13\n    call ext_discovery_step\n    cmp rax, %d\n    jne edt_fail\n    mov rdi, r13\n    call ext_discovery_count\n    cmp rax, %d\n    jne edt_fail\n    mov qword ptr [rsp + 360], 0\n    mov qword ptr [rsp + 368], 0\n    mov rdi, r13\n    call ext_discovery_free'%(expected,expected)
        assert fixture.count(old)==1
        fixture=fixture.replace(old,new,1)
    if mode==21:
        old='    cmp qword ptr [rsp + 320], 3\n    jne 3f'
        assert fixture.count(old)==1
        fixture=fixture.replace(old,'    jmp .Ledt_candidate_free\n'+old,1)
        old='    call ext_discovery_candidate_free\n    test rax, rax\n    jnz edt_fail\n    test rdx, rdx\n    jnz edt_fail'
        assert fixture.count(old)==1
        fixture=fixture.replace(old,'    mov qword ptr [rip + edtf_stage], 4\n    call ext_discovery_candidate_free\n    mov qword ptr [rip + edtf_stage], 0\n    cmp rax, -16\n    jne edt_fail\n    cmp rdx, -5\n    jne edt_fail\n    mov [rsp + 352], rax\n    mov [rsp + 360], rdx',1)
    import re
    pure='count|row|snapshot|find|shadow|detach|free|candidate_check|candidate_root|candidate_take'
    fixture=re.sub(r'(?m)^    call (ext_discovery_(?:'+pure+'))$',r'    mov qword ptr [rip + edtf_stage], 5\n    call \1\n    mov qword ptr [rip + edtf_stage], 0',fixture)
    fixture+='\n.equ EDTF_MODE, %d\n'%mode+(ROOT/'tests/faults/ext_discovery_native.s').read_text()
    return m.build(folder,fixture,replacements,windows=windows)
def setup(root):
    owner=root/'.installed'/'466f6f';owner.mkdir(parents=True)
    for name,active in [('Bar',True),('Removed',False),('Broken',None)]:
        path=owner/name.encode().hex();path.mkdir()
        data=struct.pack('<8sIIQII',b'RHEXIDX\0',1,1 if active else 2,1,0,0)+(ID if active else bytes(64))+bytes(64) if active is not None else b'broken'
        (path/'0000000000000001.idx').write_bytes(data)
    path=owner/'50656e64696e67';path.mkdir();(path/'.pending').touch()
    path=root/'.packages'/'466f6f'/'426172'/ID.decode();(path/'payload').mkdir(parents=True);(path/'lease').touch()
def main():
    p=argparse.ArgumentParser();p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);args=p.parse_args()
    windows=args.windows_build or bool(args.wine) or os.name=='nt'
    with tempfile.TemporaryDirectory(prefix='rhun-discovery-fault-',dir=args.wine_drive_root) as temp:
        folder=Path(temp).resolve()
        def run(exe,root,mode=0):
            native='C:/'+root.relative_to(args.wine_drive_root.resolve()).as_posix() if args.wine else str(root)
            options={}
            if os.name=='posix' and not windows:
                import resource
                options['preexec_fn']=lambda:resource.setrlimit(resource.RLIMIT_NOFILE,(32,32))
            return subprocess.run(([args.wine] if args.wine else [])+[str(exe),native,str(mode)],capture_output=True,timeout=30,**options)
        modes={0:(0,0,1),1:(-12,0,0),2:(-12,0,0),3:(-12,0,0),4:(-12,0,0),5:(-12,0,1),**{i:(-5,0,1) for i in range(10,16)},16:(-2,-5,1),17:(-5,0,1),18:(-5,0,1),19:(-5,-13,1),20:(-11,0,1),21:(-16,-5,1),**{i:(-125,0,1) for i in range(22,29)},29:(-116,0,1),30:(-22,0,0),31:(-116,0,0),32:(-22,0,0),33:(-36,0,0),34:(0,0,1),35:(0,0,1),**{i:(-5,0,1) for i in range(36,40)},40:(-11,-5,1),41:(-5,-16,1),42:(-12,0,0)}
        for mode,expected in modes.items():
            exe=build((args.build_only or folder)/str(mode),mode,windows)
            if args.build_only:continue
            root=folder/('root'+str(mode));root.mkdir();setup(root)
            if mode==42:
                path=root/'.installed'/'466f6f'/'5a6564';path.mkdir()
                (path/'0000000000000001.idx').write_bytes(struct.pack('<8sIIQII',b'RHEXIDX\0',1,1,1,0,0)+ID+bytes(64))
            if mode==35:
                native='C:/'+root.relative_to(args.wine_drive_root.resolve()).as_posix() if args.wine else str(root)
                process=subprocess.Popen(([args.wine] if args.wine else [])+[str(exe),native,'7'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                import selectors
                if os.name=='posix':
                    selector=selectors.DefaultSelector();selector.register(process.stdout,selectors.EVENT_READ)
                    assert selector.select(30),'substitution rendezvous timed out';selector.close()
                assert process.stdout.read(1)==b'R','missing substitution rendezvous'
                package=root/'.packages'/'466f6f'/'426172'/ID.decode();package.rename(package.with_name('b'*64))
                (package/'payload').mkdir(parents=True);(package/'lease').touch()
                stdout,stderr=process.communicate(b'G',timeout=30)
                r=subprocess.CompletedProcess(process.args,process.returncode,stdout,stderr)
            else:r=run(exe,root)
            assert r.returncode==0 and not r.stderr and len(r.stdout)==32,(mode,r)
            assert struct.unpack('<qqQQ',r.stdout)[:3]==expected,(mode,struct.unpack('<qqQQ',r.stdout),expected)
            print('ok ext-discovery/fault/'+str(mode),flush=True)
        for mode,mutation,argmode in [(0,'lease',0),(16,'secondary',0),(0,'epoch',3),(0,'shadow',0),(31,'proof',0)]:
            exe=build((args.build_only or folder)/('negative-'+mutation),mode,windows,mutation)
            if args.build_only:continue
            root=folder/('negative-root-'+mutation);root.mkdir();setup(root);r=run(exe,root,argmode)
            if mutation=='lease':assert r.returncode==0 and struct.unpack('<qqQQ',r.stdout)[0]==-33,r
            elif mutation=='secondary':assert r.returncode==0 and struct.unpack('<qqQQ',r.stdout)[1]!=-5,r
            else:assert r.returncode==73,r
            print('ok ext-discovery/negative-control/'+mutation,flush=True)
if __name__=='__main__':main()
