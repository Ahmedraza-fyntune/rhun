#!/usr/bin/env python3
"""Immutable runtime command identity, ownership, bounds and session authority."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def build(folder, windows=False, mutation=None):
    spec = importlib.util.spec_from_file_location('runtime_build', ROOT / 'tests/faults/ext_store_build.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    source = (ROOT / 'src/app/extruntime.s').read_text()
    assert source.count('call ext_prepare_retire_alloc_custom') == 1
    source = source.replace('call ext_prepare_retire_alloc_custom', 'call rot_alloc')
    assert source.count('call ext_prepare_retire_enqueue_custom') == 1
    source = source.replace('call ext_prepare_retire_enqueue_custom', 'call rot_enqueue')
    source = source.replace('FN ext_runtime_retire_one\n', 'FN rot_retire_one_impl\n')
    source += '\nFN rot_set_incarnation_impl\n    mov [rip + ro_last_incarnation], rdi\n    ret\n'
    if mutation:
        old, new = {
            'target': ('    cmp [rbx + RO_target], rsi\n    jne .Lro_no', '    nop'),
            'session': ('    cmp [rbx + RO_session], rdx\n    jne .Lro_no', '    nop'),
            'live': ('    cmp qword ptr [rbx + RO_live], 1\n    jne .Lro_no', '    nop'),
            'identity': ('    xor esi, esi\n    mov rdx, r12\n    mov ecx, RO_LIMIT\n    call ro_equal', '    mov eax, 1'),
            'bytes': ('    call memeq\n    EPILOGUE\n8:', '    mov eax, 1\n    EPILOGUE\n8:'),
        }[mutation]
        assert source.count(old) == 1
        source = source.replace(old, new)
    fixture = '.equ ROT_INSTRUMENTED, 1\n' + (ROOT / 'tests/ext_runtime_owner_test.s').read_text()
    marker = 'FN rot_set_incarnation\n    ret\n'
    assert fixture.count(marker) == 1
    fixture = fixture.replace(marker, 'FN rot_set_incarnation\n    jmp rot_set_incarnation_impl\n')
    mem = (ROOT / 'src/mem.s').read_text()
    old = '.Lmf_large:\n'
    assert mem.count(old) == 1
    mem = mem.replace(old, old + '    inc qword ptr [rip + rot_unmap_calls]\n', 1)
    replacements = {'src/app/extruntime.s': source}
    if windows:
        native = (ROOT / 'src/win/sys.s').read_text()
        assert native.count('API VirtualFree') == 1
        native = native.replace('API VirtualFree', 'call rot_native_virtual_free', 1)
        fixture += '\nFN rot_native_virtual_free\n    cmp qword ptr [rip + rot_fail_unmap], 0\n    je 1f\n    dec qword ptr [rip + rot_fail_unmap]\n    mov ecx, 1\n1:  jmp [rip + __imp_VirtualFree]\n'
        replacements['src/win/sys.s'] = native
    else:
        assert mem.count('SYS SYS_munmap') == 1
        mem = mem.replace('SYS SYS_munmap', 'call rot_native_unmap', 1)
        fixture += '\nFN rot_native_unmap\n    cmp qword ptr [rip + rot_fail_unmap], 0\n    je 1f\n    dec qword ptr [rip + rot_fail_unmap]\n    mov edi, 1\n1:  SYS SYS_munmap\n    ret\n'
    replacements['src/mem.s'] = mem
    return builder.build(folder, fixture, replacements, windows=windows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wine')
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--negative-controls', action='store_true')
    parser.add_argument('--mutation', choices=('target', 'session', 'live', 'identity', 'bytes'))
    args = parser.parse_args()
    if args.build_only and not args.exe:
        parser.error('--build-only requires --exe')
    if args.negative_controls and (args.exe or args.build_only or args.mutation):
        parser.error('--negative-controls builds its own native fixtures')
    windows = bool(args.wine) or os.name == 'nt' or bool(args.build_only and args.exe.suffix.lower() == '.exe')
    with tempfile.TemporaryDirectory(prefix='rhun-runtime-owner-') as temporary:
        folder = Path(temporary)
        exe = args.exe.resolve() if args.exe and not args.build_only else build(folder, windows, args.mutation)
        if args.build_only:
            args.exe.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(exe, args.exe)
            return
        result = subprocess.run(([args.wine, 'Z:' + exe.as_posix()] if args.wine else [str(exe)]),
                                cwd=ROOT, capture_output=True, timeout=30)
        expected = 72 if args.mutation else 0
        assert result.returncode == expected, result
        assert not result.stderr, result
        assert result.stdout == (b'' if args.mutation else b'ok owned runtime command identity and sessions\n'), result
        if args.negative_controls:
            for mutation in ('target', 'session', 'live', 'identity', 'bytes'):
                target = folder / mutation
                target.mkdir()
                control = build(target, windows, mutation)
                result = subprocess.run(([args.wine, 'Z:' + control.as_posix()] if args.wine else [str(control)]),
                                        cwd=ROOT, capture_output=True, timeout=30)
                assert result.returncode == 72 and not result.stdout and not result.stderr, (mutation, result)
                print('ok negative control:', mutation)
    print('ok runtime command owner, immutable strings, exact identity/session, revocation, bounds and allocation failures')


if __name__ == '__main__':
    main()
