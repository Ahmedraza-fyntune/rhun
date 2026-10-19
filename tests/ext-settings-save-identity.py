#!/usr/bin/env python3
"""Actual settings serializer after real historical HI withdrawal, with a file sink."""
import argparse, importlib.util, os, shutil, sys, tempfile
from pathlib import Path
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CODES={'skip-identity':211,'skip-visibility':212,'skip-survivor':212}
def build(folder, windows=False, mutation=None):
    spec=importlib.util.spec_from_file_location('save_identity_builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    fixture=(ROOT/'tests/ext_host_identity_test.s').read_text()
    marker='    cmp qword ptr [r12 + EXT_state], 0\n    jne .Lhit_bad\n'
    assert fixture.count(marker)==1
    fixture=fixture.replace(marker,marker+'    call svh_save\n')+'\n'+(ROOT/'tests/ext_settings_save_identity_cases.inc').read_text()
    replacements={}
    for path,names in [('src/app/ext.s',['ext_full_name']),('src/sys.s',['file_write_all','mkdir_p']),('src/app/config.s',['config_dir'])]:
        source=(ROOT/path).read_text()
        for name in names:
            marker='FN '+name+'\n';assert source.count(marker)==1
            source=source.replace(marker,'FN svh_real_'+name+'\n')
        if windows:
            source=source.replace('.pushsection .rodata.str, "aMS", @progbits, 1', '.pushsection .rdata, "dr"')
        replacements[path]=source
    replacements['src/app/ext.s']+='\n.text\nFN svh_free_buffers\n    PROLOGUE\n    lea rdi, [rip + tmp]\n    call sb_free\n    lea rdi, [rip + tmp2]\n    call sb_free\n    lea rdi, [rip + ext_ini_path]\n    call sb_free\n    EPILOGUE\n'
    if mutation:
        source=replacements['src/app/ext.s'];head,body=source.split('FN ext_settings_save\n',1);body,sep,tail=body.partition('\nFN ')
        marker='    call ext_has_identity\n';assert body.count(marker)==1
        body=body.replace(marker,{'skip-identity':'    mov eax, 1\n','skip-visibility':'    call ext_host_identity_matches\n','skip-survivor':'    xor eax, eax\n'}[mutation],1)
        replacements['src/app/ext.s']=head+'FN ext_settings_save\n'+body+sep+tail
    return builder.build(folder,fixture,replacements,windows=windows)
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path);p.add_argument('--wine');p.add_argument('--build-only',action='store_true');p.add_argument('--mutation',choices=CODES);p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
    if a.build_only and not a.exe:p.error('--build-only requires --exe')
    if a.negative_controls and(a.exe or a.build_only or a.mutation):p.error('controls build their own exact fixtures')
    if a.wine and not a.exe:p.error('Wine requires a prebuilt --exe')
    windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')
    def check(exe,mutation):
        with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve())],timeout=30,output_bound=0,error_bound=4096)as exchange:
            out,err=exchange.finish();assert exchange.process.returncode==(CODES[mutation]if mutation else 0)and not out and not err,(mutation,exchange.process.returncode,out,err)
        print('ok settings save identity '+(mutation or 'withdrawal'),flush=True)
    with tempfile.TemporaryDirectory(prefix='rhun-settings-save-identity-')as temporary:
        folder=Path(temporary)
        if a.negative_controls:
            check(build(folder/'normal',windows),None)
            for mutation in CODES:check(build(folder/mutation,windows,mutation),mutation)
        else:
            exe=a.exe if a.exe and not a.build_only else build(folder/'build',windows,a.mutation)
            if a.build_only:
                a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(exe,a.exe);shutil.copymode(exe,a.exe)
            else:check(exe,a.mutation)
if __name__=='__main__':main()
