#!/usr/bin/env python3
"""Refuse specific output frames in the actual extension event state machine."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def build(folder, windows=False, mutation=None):
    spec = importlib.util.spec_from_file_location('event_fixture_build', ROOT / 'tests/faults/ext_store_build.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    protocol = (ROOT / 'src/app/extproto.s').read_text()
    marker = '    jmp ext_send_checked\n'
    if protocol.count(marker) != 1:
        raise AssertionError('checked output interception changed')
    protocol = protocol.replace(marker, '    jmp ext_events_send\n')
    protocol += '\nFN ext_events_output_free_impl\n    PROLOGUE\n    lea rdi, [rip + out]\n    call sb_free\n    lea rdi, [rip + line]\n    call sb_free\n    EPILOGUE\n'
    fixture = (ROOT / 'tests/ext_events_test.s').read_text()
    marker = 'FN ext_events_output_free\n    ret\n'
    if fixture.count(marker) != 1:
        raise AssertionError('output cleanup interception changed')
    fixture = fixture.replace(marker, 'FN ext_events_output_free\n    jmp ext_events_output_free_impl\n')
    events = (ROOT / 'src/app/extprotoevents.inc').read_text()
    if mutation:
        old, new = {
            'full': ('    call out_end\n    test rax, rax\n    js 9f\n    mov rdi, rbx\n    call snapshot_taken',
                     '    call out_end\n    mov rdi, rbx\n    call snapshot_taken'),
            'range': ('h_range:', 'h_range:'),
            'positions': ('    cmp qword ptr [rsp], 0\n    jne .Lxe_closed_begin\n    xor r12d, r12d',
                          '    xor r12d, r12d'),
            'active': ('    cmp qword ptr [rsp], 0\n    jne .Lxe_result\n    call active_doc_id',
                       '    call active_doc_id'),
            'closed': ('    mov qword ptr [r13 + XK_phase], XP_NEED_OPEN\n', '    nop\n'),
            'debt': ('mov qword ptr [rax + XK_resync], 1\n', 'nop\n'),
            'request': ("    call out_end\n    test rax, rax\n    js 8f\n    mov rdi, [rsp]              # resources group: the request's kind and time",
                        "    call out_end\n    mov rdi, [rsp]              # resources group: the request's kind and time"),
        }[mutation]
        target = protocol if mutation in ('request', 'full', 'range') else events
        if mutation == 'range':
            start = protocol.index('h_range:')
            end = protocol.index('h_replace:', start)
            old = protocol[start:end]
            marker = '    call out_end\n'
            if old.count(marker) != 1:
                raise AssertionError('range snapshot mutation changed')
            new = old.replace(marker, marker + '    mov rdi, rbx\n    call snapshot_taken\n')
        if target.count(old) != 1:
            raise AssertionError('negative control no longer matches: ' + mutation)
        target = target.replace(old, new)
        if mutation in ('request', 'full', 'range'):
            protocol = target
        else:
            events = target
    marker = '.include "app/extprotoevents.inc"'
    if protocol.count(marker) != 1:
        raise AssertionError('event include changed')
    protocol = protocol.replace(marker, events)
    return builder.build(folder, fixture, {'src/app/extproto.s': protocol}, windows=windows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wine')
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--negative-controls', action='store_true')
    args = parser.parse_args()
    if args.build_only and not args.exe:
        parser.error('--build-only requires --exe output')
    if args.negative_controls and args.exe and not args.build_only:
        parser.error('negative controls require local builds')
    windows = bool(args.wine) or os.name == 'nt' or bool(args.build_only and args.exe.suffix.lower() == '.exe')
    with tempfile.TemporaryDirectory(prefix='rhun-ext-events-') as temporary:
        folder = Path(temporary)
        exe = args.exe.resolve() if args.exe and not args.build_only else build(folder / 'regular', windows)
        if args.build_only:
            args.exe.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(exe, args.exe)
            print('built extension event fixture: ' + str(args.exe))
            return
        command = [args.wine, 'Z:' + exe.as_posix()] if args.wine else [str(exe)]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
        expected = (ROOT / 'tests/data/ext-events.expected').read_bytes()
        if result.returncode or result.stdout + result.stderr != expected:
            raise AssertionError(f'event fixture: exit {result.returncode}, {(result.stdout + result.stderr)[:4000]!r}')
        if args.negative_controls:
            for mutation in ('positions', 'active', 'closed', 'debt', 'request', 'full', 'range'):
                exe = build(folder / mutation, windows, mutation)
                command = [args.wine, 'Z:' + exe.as_posix()] if args.wine else [str(exe)]
                result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
                expected_exit = {'full': 83, 'range': 84, 'positions': 82, 'active': 79, 'closed': 73, 'debt': 76, 'request': 78}[mutation]
                if result.returncode != expected_exit or result.stdout or result.stderr:
                    raise AssertionError(f'negative control {mutation}: expected exit {expected_exit}, got '
                                         f'{result.returncode}, {(result.stdout + result.stderr)[:4000]!r}')
                print('ok   negative control: ' + mutation, flush=True)
    print('ok   extension event prefixes and refused output', flush=True)


if __name__ == '__main__':
    main()
