#!/usr/bin/env python3
"""Run actual command dispatch across output refusal and command-vector replacement."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[1]

def build(folder,windows=False):
    spec=importlib.util.spec_from_file_location('pending_builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    ext=(ROOT/'src/app/ext.s').read_text()
    ext+='\nFN ext_pending_fixture_setup_impl\n    mov [rip + ext_manifest_cmds], rdi\n    ret\nFN ext_pending_ext_cleanup_impl\n    PROLOGUE\n    lea rdi, [rip + tmp]\n    call sb_free\n    EPILOGUE\n'
    def replace_region(text, begin, end, replacements):
        before, region = text.split(begin, 1)
        region, after = region.split(end, 1)
        for old, new in replacements:
            assert old in region, (begin, old)
            region = region.replace(old, new)
        return before + begin + region + end + after
    ext=replace_region(ext,'ext_spawn:\n','# build_argv(ext)',[
        ('call mkdir_p','call pct_native_noop'),('SYS SYS_open','call pct_native_open'),
        ('SYS SYS_close','call pct_native_close'),('SYS SYS_pipe2','call pct_native_pipe'),
        ('call build_argv','call pct_native_noop'),('call build_env','call pct_native_noop'),
        ('call proc_spawn','call pct_native_spawn')])
    ext=replace_region(ext,'FN ext_exited\n','# ext_is_visible(ext',[
        ('SYS SYS_kill','call pct_native_noop'),('SYS SYS_close','call pct_native_noop'),
        ('call proc_wait','call pct_native_noop'),('call confine_failed','call pct_confine_failed'),
        ('call confine_exit_reason','call pct_confine_reason'),('call ext_start','call pct_retry_start')])
    ext=replace_region(ext,'FN ext_shutdown\n','FN ext_status_draw\n',[
        ('call proc_wait','call pct_shutdown_wait'),('call loop_poll','call pct_shutdown_poll')])
    proto=(ROOT/'src/app/extproto.s').read_text()
    marker='    jmp ext_send_checked\n'
    assert proto.count(marker)==1
    proto=proto.replace(marker,'    jmp ext_pending_fixture_send\n')
    proto+='\nFN ext_pending_fixture_cleanup_impl\n    PROLOGUE\n    lea rdi, [rip + out]\n    call sb_free\n    lea rdi, [rip + line]\n    call sb_free\n    call ext_pending_ext_cleanup_impl\n    EPILOGUE\n'
    fixture=(ROOT/'tests/ext_pending_command_test.s').read_text()
    for name in ('setup','cleanup'):
        marker='FN ext_pending_fixture_'+name+'\n    ret\n'
        assert fixture.count(marker)==1
        fixture=fixture.replace(marker,'FN ext_pending_fixture_'+name+'\n    jmp ext_pending_fixture_'+name+'_impl\n')
    return builder.build(folder,fixture,{'src/app/ext.s':ext,'src/app/extproto.s':proto},windows=windows)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--wine');p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');a=p.parse_args()
    if a.build_only and not a.exe:p.error('--build-only requires --exe')
    windows=bool(a.wine) or os.name=='nt' or bool(a.build_only and a.exe.suffix.lower()=='.exe')
    with tempfile.TemporaryDirectory(prefix='rhun-pending-command-') as temporary:
        exe=a.exe.resolve() if a.exe and not a.build_only else build(Path(temporary),windows)
        if a.build_only:
            a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(exe,a.exe);return
        result=subprocess.run(([a.wine,'Z:'+exe.as_posix()] if a.wine else [str(exe)]),cwd=ROOT,capture_output=True,timeout=30)
        assert result.returncode==0 and result.stdout==b'ok pending commands\n' and not result.stderr,result
        print('ok owned pending command retries, hello refusal, stop, native startup faults, confinement and shutdown callbacks')
if __name__=='__main__':main()
