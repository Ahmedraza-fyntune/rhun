#!/usr/bin/env python3
"""Private exact-inventory store fault links and failure classification."""
import argparse
import importlib.util
from pathlib import Path
import os
import struct
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]

def index(g): return struct.pack('<8sIIQII',b'RHEXIDX\0',1,2,g,0,0)+bytes(128)

def build(folder,mode,windows=False,read=False,mutation=None):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    replacements={}
    names={'src/app/extstoreio.s':('ext_store_raw_rename','ext_store_raw_write','ext_store_raw_sync','ext_store_raw_unlink'),
           'src/app/extvalidatepath.s':('ext_root_read','ext_root_close','ext_root_open_at','ext_root_reopen_dir')}
    aliases={'ext_store_raw_rename':'rename','ext_store_raw_write':'write','ext_store_raw_sync':'sync',
             'ext_store_raw_unlink':'unlink','ext_root_read':'read','ext_root_close':'close',
             'ext_root_open_at':'open_at','ext_root_reopen_dir':'reopen'}
    for relative,symbols in names.items():
        source=(ROOT/relative).read_text()
        for symbol in symbols:
            old='FN '+symbol+'\n';assert source.count(old)==1,(relative,symbol)
            source=source.replace(old,'FN ext_store_test_real_'+aliases[symbol]+'\n')
        replacements[relative]=source
    if windows:
        relative='src/win/extvalidatepath.s';source=(ROOT/relative).read_text()
        source=source.replace('FN win_ext_root_open_prepared_at\n','FN ext_store_test_real_prepared_at\n')
        replacements[relative]=source
    if mode==161:
        relative='src/app/extvalidatepath.s'
        replacements[relative]=replacements[relative].replace('FN ext_root_identity\n','FN ext_store_test_real_identity\n')
    if mode==162:
        relative='src/app/extstorewrite.s';source=(ROOT/relative).read_text()
        old='    mov ecx, ER_DELETE\n    xor r8d, r8d\n    call ext_root_open_at\n'
        assert source.count(old)==2
        # Pause before first reopened pending source, with original writes already closed.
        source=source.replace('    mov rdi, [rbx + ESW_identity_dir]\n    lea rsi, [rbx + ESW_pending]\n    mov edx, ER_FILE\n    mov ecx, ER_DELETE', '    call est_before_reopen\n    mov rdi, [rbx + ESW_identity_dir]\n    lea rsi, [rbx + ESW_pending]\n    mov edx, ER_FILE\n    mov ecx, ER_DELETE',1)
        replacements[relative]=source
    if mode>=150:
        for relative,symbol,alias in (('src/mem.s','mem_alloc','alloc'),('src/mem.s','mem_alloc_try','alloc_try')):
            source=replacements.get(relative,(ROOT/relative).read_text())
            old='FN '+symbol+'\n';assert source.count(old)==1
            replacements[relative]=source.replace(old,'FN ext_store_test_real_'+alias+'\n')
        if windows:
            relative='src/win/extvalidatepath.s'
            replacements[relative]=replacements[relative].replace('API MultiByteToWideChar','call est_convert')
    if read:
        relative='src/app/extstoreread.s'
        source=(ROOT/relative).read_text().replace('call dir_scan_fd_try','call est_fault_scan').replace('call win_dir_scan_handle_try','call est_fault_scan')
        if mutation=='partial': source=source.replace('call est_fault_scan', 'call est_fault_scan\n    xor eax, eax')
        replacements[relative]=source
    if mutation=='enomem':
        relative='src/app/extstoreread.s';source=replacements[relative]
        old='    cmp rax, -12\n    je 9f\n';assert source.count(old)==1
        replacements[relative]=source.replace(old,'')
    fixture=(ROOT/('tests/ext_store_read_test.s' if read else 'tests/ext_store_write_test.s')).read_text()
    if mode==160:
        fixture=fixture.replace('    mov rdi, r14\n    call ext_store_prepare_free','    mov qword ptr [r14 + ESW_source_owned], 0\n    mov qword ptr [rip + est_destructor_stage], 1\n    mov rdi, r14\n    call ext_store_prepare_free')
    if mode>=150:
        fixture=fixture.replace('    inc qword ptr [rdi]','    mov qword ptr [rip + est_after_precommit], 1\n    inc qword ptr [rdi]').replace('    call ext_store_commit_try\n','    call ext_store_commit_try\n    mov qword ptr [rip + est_after_precommit], 0\n')
    fixture+='\n.equ EST_FAULT_MODE, %d\n'%mode+(ROOT/'tests/faults/ext_store_native.s').read_text()
    return module.build(folder,fixture,replacements,windows=windows)

def build_pending(folder):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    source=(ROOT/'src/app/extstoreio.s').read_text().replace('API NtSetInformationFile','call esp_set_information').replace('API WaitForSingleObject','call esp_wait')
    adapter=(ROOT/'src/app/extvalidatepath.s').read_text().replace('FN ext_root_close\n','FN ext_store_test_real_close\n')
    return module.build(folder,(ROOT/'tests/faults/ext_store_pending.s').read_text(),{'src/app/extstoreio.s':source,'src/app/extvalidatepath.s':adapter},windows=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--windows-build',action='store_true');parser.add_argument('--wine');parser.add_argument('--wine-drive-root',type=Path);parser.add_argument('--build-only',type=Path)
    args=parser.parse_args();windows=args.windows_build or bool(args.wine) or os.name=='nt'
    base=args.wine_drive_root.resolve() if args.wine_drive_root else None
    with tempfile.TemporaryDirectory(prefix='rhun-ext-store-faults-',dir=base) as name:
        folder=Path(name).resolve();prefix=[args.wine] if args.wine else []
        def native(p):return 'C:/'+p.resolve().relative_to(base).as_posix() if args.wine else str(p.resolve())
        if windows:
            executable=build_pending((args.build_only or folder)/'pending')
            if not args.build_only:
                root=folder/'pending-root';root.mkdir()
                result=subprocess.run([*prefix,str(executable),native(root)],capture_output=True,timeout=30)
                assert result.returncode==0 and not result.stdout and not result.stderr,result
                print('ok ext-store/fault/persistent-native-pending',flush=True)
            for mode in (160,161,162):
                executable=build((args.build_only or folder)/str(mode),mode,windows)
                if args.build_only:continue
                root=folder/('identity'+str(mode));directory=root/'.installed'/'466f6f'/'434f4e2e';directory.mkdir(parents=True)
                (directory/'0000000000000001.idx').write_bytes(index(1))
                nextfile=folder/'next';nextfile.write_bytes(index(2))
                arguments=[*prefix,str(executable),native(root),'Foo','CON.',native(nextfile),'1' if mode==160 else '0']
                if mode==162:
                    process=subprocess.Popen(arguments,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                    assert process.stdout.read(6)==b'READY\n'
                    pending=next(directory.glob('.pending-*'));saved=directory/'.saved-own-pending';pending.rename(saved)
                    replacement=b'preserve-replacement';pending.write_bytes(replacement)
                    output,error=process.communicate(b'x',timeout=30);returncode=process.returncode
                    assert pending.read_bytes()==replacement and saved.read_bytes()==index(2)
                else:
                    result=subprocess.run(arguments,capture_output=True,timeout=30);output,error,returncode=result.stdout,result.stderr,result.returncode
                assert returncode==0 and len(output)==64 and not error,(mode,returncode,output,error)
                words=struct.unpack('<8q',output)
                if mode==160:assert words[2]==-125 and words[6]==-13,words
                elif mode==161:assert words[0]==-5 and words[6]==-5 and list(directory.glob('.pending-*')),words
                else:assert words[0]==-116 and words[6]==-116,words
                print('ok ext-store/fault/'+str(mode),flush=True)
        targets=[(100,-5,6,False),(101,0,3,True),(102,-5,5,True),(103,-5,4,False),(104,-5,5,False),(105,-5,5,True),(106,-5,6,False),(107,-5,6,False),(109,-5,6,False),(114,-5,5,True),(150,0,3,True),(151,0,3,True)]
        for mode,status,state,renamed in targets:
            executable=build((args.build_only or folder)/str(mode),mode,windows)
            if args.build_only:continue
            root=folder/('root'+str(mode));directory=root/'.installed'/'466f6f'/'434f4e2e';directory.mkdir(parents=True)
            for g in range(1,5):(directory/('%016x.idx'%g)).write_bytes(index(g))
            nextfile=folder/'next';nextfile.write_bytes(index(5))
            result=subprocess.run([*prefix,str(executable),native(root),'Foo','CON.',native(nextfile),'0'],capture_output=True,timeout=30)
            assert result.returncode==0 and len(result.stdout)==64 and not result.stderr,(mode,result)
            words=struct.unpack('<8q',result.stdout)
            actual=words[0] if words[0] else words[2]
            assert actual==status and words[3]==state,(mode,words)
            if renamed:assert (directory/'0000000000000005.idx').read_bytes()==index(5)
            else:assert (directory/'0000000000000004.idx').read_bytes()==index(4)
            assert mode==103 or renamed or not (directory/'0000000000000005.idx').exists()
            print('ok ext-store/fault/'+str(mode),flush=True)
        for mode in (120,121,122,130,131,132,133,134,135):
            executable=build((args.build_only or folder)/str(mode),mode,windows,read=True)
            if args.build_only:continue
            root=folder/('read'+str(mode));directory=root/'.installed'/'466f6f'/'434f4e2e';directory.mkdir(parents=True)
            (directory/'0000000000000001.idx').write_bytes(index(1))
            result=subprocess.run([*prefix,str(executable),native(root),'0','1'],capture_output=True,timeout=30)
            assert result.returncode==0 and len(result.stdout)>=24 and not result.stderr,(mode,result)
            primary,secondary,length=struct.unpack_from('<qqQ',result.stdout)
            if mode in (120,121): assert (primary,secondary,length)==(-5,0,0),(mode,primary,secondary,length)
            elif mode==134: assert (primary,secondary,length)==(-13,-5,0),(mode,primary,secondary,length)
            elif mode==135: assert (primary,secondary,length)==(-2,-5,0),(mode,primary,secondary,length)
            else:
                assert primary==secondary==0 and length>0,(mode,primary,secondary,length)
                generation,status=struct.unpack_from('<Qq',result.stdout,24+128+208)
                assert generation==1 and status==({122:-5,132:-11,133:-5}.get(mode,0)),(mode,generation,status)
            print('ok ext-store/fault/'+str(mode),flush=True)
        for mode,mutation in ((120,'partial'),):
            executable=build((args.build_only or folder)/('negative-'+mutation),mode,windows,read=True,mutation=mutation)
            if args.build_only:continue
            root=folder/('negative-'+mutation);directory=root/'.installed'/'466f6f'/'434f4e2e';directory.mkdir(parents=True)
            (directory/'0000000000000001.idx').write_bytes(index(1))
            result=subprocess.run([*prefix,str(executable),native(root),'0','1'],capture_output=True,timeout=30)
            assert result.returncode==0 and struct.unpack_from('<qqQ',result.stdout)[0]==0,result
            print('ok ext-store/fault/negative-'+mutation,flush=True)
        for mutation in (None,'enomem'):
            executable=build((args.build_only or folder)/('oom-'+str(mutation)),111,windows,read=True,mutation=mutation)
            if args.build_only:continue
            root=folder/('oom-'+str(mutation));owner=root/'.installed'/'466f6f'
            for name in ('a','b'):
                path=owner/name.encode().hex();path.mkdir(parents=True);(path/'0000000000000001.idx').write_bytes(index(1))
            result=subprocess.run([*prefix,str(executable),native(root),'0','1'],capture_output=True,timeout=30)
            assert result.returncode==0 and len(result.stdout)>=24 and not result.stderr,result
            primary,secondary,length=struct.unpack_from('<qqQ',result.stdout)
            if mutation:assert primary==0 and length>0, (primary,secondary,length)
            else:assert (primary,secondary,length)==(-12,0,0),(primary,secondary,length)
            print('ok ext-store/fault/oom-'+str(mutation),flush=True)
if __name__=='__main__':main()
