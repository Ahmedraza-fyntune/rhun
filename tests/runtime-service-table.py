#!/usr/bin/env python3
"""Real runtime TABLE owners, bounded initialization and native failed-free recovery."""
import argparse,importlib.util,os,shutil,sys,tempfile
from pathlib import Path
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CODES={'ignore-role':165,'unbounded-init':164,'bypass-last-gate':167,'skip-native-quiet':169,'retire-active-guard':172,'lose-orphan':162}
def build(folder,windows=False,scenario=0,mutation=None):
    spec=importlib.util.spec_from_file_location('runtime_table_builder',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
    fixture='.equ RTF_SCENARIO, '+str(scenario)+'\n'+(ROOT/'tests/runtime_service_table_cases.inc').read_text()
    replacements={}
    for path,name,replacement in [('src/mem.s','mem_alloc_try','rtf_real_mem_alloc_try'),('src/app/extprepareretirecustom.s','ext_prepare_retire_mark_custom_po','rtf_real_mark'),('src/app/extprepareretirequeue.s','ext_prepare_owner_release_deferred','rtf_real_owner_drop')]:
        text=(ROOT/path).read_text();marker='FN '+name+'\n';assert text.count(marker)==1
        replacements[path]=text.replace(marker,'FN '+replacement+'\n',1)
    marker='    SYS SYS_munmap';assert replacements['src/mem.s'].count(marker)==1
    replacements['src/mem.s']=replacements['src/mem.s'].replace(marker,'    call rtf_unmap',1)
    if mutation:
        text=(ROOT/'src/app/extruntimeservice.s').read_text()
        def change(old,new):
            nonlocal text
            assert text.count(old)==1,(mutation,old,text.count(old));text=text.replace(old,new,1)
        if mutation=='ignore-role':change('    cmp qword ptr [rdi + RT_role], RT_TABLE_ROLE\n    jne 9f','    cmp qword ptr [rdi + RT_role], RT_TABLE_ROLE\n    nop')
        elif mutation=='unbounded-init':change('    mov r15d, 16\n','    mov r15d, 32\n')
        elif mutation=='bypass-last-gate':change('    cmp qword ptr [rbx + PO_refs], 1\n    ja .Lrtr_drop','    cmp qword ptr [rbx + PO_refs], 1\n    jmp .Lrtr_drop')
        elif mutation=='skip-native-quiet':
            head,tail=text.split('FN rt_closing_finish\n',1);body,sep,rest=tail.partition('\nFN ');marker='    call rt_table_native_quiet_check\n';assert body.count(marker)==1;body=body.replace(marker,'    xor eax, eax\n',1);text=head+'FN rt_closing_finish\n'+body+sep+rest
        elif mutation=='retire-active-guard':change('FN rt_retire_one\n    PROLOGUE\n','FN rt_retire_one\n    call rt_table_is_owned\n    test eax, eax\n    jz .Lrtd_mutant\n    PROLOGUE\n') ;text+='\n.text\n.Lrtd_mutant:\n    mov rax, -22\n    xor edx, edx\n    ret\n'
        elif mutation=='lose-orphan':change('    cmp rdx, 1\n    jne 1f\n    mov qword ptr [rbx + RTC_orphanEO], 0','    cmp rdx, 1\n    nop\n    mov qword ptr [rbx + RTC_orphanEO], 0')
        replacements['src/app/extruntimeservice.s']=text
    return b.build(folder,fixture,replacements,windows=windows)
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--scenario',type=int,choices=range(10),default=0);p.add_argument('--mutation',choices=CODES);p.add_argument('--all',action='store_true');a=p.parse_args()
    if a.build_only and not a.exe:p.error('--build-only requires --exe')
    if a.wine and not a.exe:p.error('Wine requires exact prebuilt --exe')
    if a.all and(a.exe or a.mutation or a.build_only):p.error('--all builds each exact fixture')
    if a.mutation=='lose-orphan':a.scenario=8
    windows=os.name=='nt'or bool(a.wine)or bool(a.build_only and a.exe.suffix.lower()=='.exe')
    def check(exe,scenario,mutation):
        with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve())],timeout=30,output_bound=0,error_bound=4096)as exchange:
            out,err=exchange.finish();expected=CODES[mutation]if mutation else 0
            assert exchange.process.returncode==expected and not out and not err,(scenario,mutation,exchange.process.returncode,out,err)
        print('ok runtime TABLE',scenario,mutation or '',flush=True)
    with tempfile.TemporaryDirectory(prefix='rhun-runtime-table-')as temporary:
        folder=Path(temporary)
        if a.all:
            for scenario in range(10):check(build(folder/str(scenario),windows,scenario),scenario,None)
            for mutation in CODES:
                scenario=8 if mutation=='lose-orphan'else 0
                check(build(folder/mutation,windows,scenario,mutation),scenario,mutation)
        else:
            exe=a.exe if a.exe and not a.build_only else build(folder/'build',windows,a.scenario,a.mutation)
            if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(exe,a.exe);shutil.copymode(exe,a.exe)
            else:check(exe,a.scenario,a.mutation)
if __name__=='__main__':main()
