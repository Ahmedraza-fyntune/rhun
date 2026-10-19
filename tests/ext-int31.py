#!/usr/bin/env python3
"""Saturating integer prefix parsing and actual legacy prepared defaults."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OLD_BODY = '''    push rbx
    call parse_u64
    pop rbx
    mov ecx, 0x7fffffff
    cmp rax, rcx
    jbe 1f
    mov eax, ecx
1:  ret
'''


def build(folder, windows, mutation=None):
    spec = importlib.util.spec_from_file_location('int31_builder', ROOT / 'tests/faults/ext_store_build.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    source = (ROOT / 'src/app/ext.s').read_text()
    fixture = (ROOT / 'tests/faults/int31_normalization.s').read_text()
    if mutation:
        marker = 'FN ext_prepare_parse_int31\nparse_int31:\n'
        assert source.count(marker) == 1
        start = source.index(marker) + len(marker)
        end = source.index('\n# sdefs_init_values', start)
        source = source[:start] + OLD_BODY + source[end:]
        if mutation == 'wrapping-default':
            fixture = '.equ INTT_DEFAULT_ONLY, 1\n' + fixture
    return builder.build(folder, fixture, {'src/app/ext.s': source}, windows=windows)


def check(executable, wine=None, mutation=None):
    command = [wine, 'Z:' + executable.resolve().as_posix()] if wine else [str(executable.resolve())]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=40)
    expected_exit = {'wrapping': 81, 'wrapping-default': 82}.get(mutation, 0)
    expected_output = b'' if mutation else b'ok saturating int31 prefix and legacy defaults\n'
    assert (result.returncode, result.stdout, result.stderr) == (expected_exit, expected_output, b''), result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--wine')
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--negative-controls', action='store_true')
    parser.add_argument('--mutation', choices=['wrapping', 'wrapping-default'])
    args = parser.parse_args()
    if args.build_only and not args.exe:
        parser.error('--build-only requires --exe')
    if args.wine and not args.exe and not args.negative_controls:
        parser.error('--wine requires --exe or --negative-controls')
    if args.negative_controls and (args.exe or args.build_only or args.mutation):
        parser.error('--negative-controls builds its own fixtures')
    windows = os.name == 'nt' or bool(args.wine) or bool(args.build_only and args.exe.suffix.lower() == '.exe')
    with tempfile.TemporaryDirectory(prefix='rhun-int31-') as temporary:
        folder = Path(temporary)
        if args.negative_controls:
            check(build(folder / 'baseline', windows), args.wine)
            for mutation in ['wrapping', 'wrapping-default']:
                check(build(folder / mutation, windows, mutation), args.wine, mutation)
                print('ok int31 negative control ' + mutation, flush=True)
        else:
            executable = args.exe if args.exe and not args.build_only else build(folder, windows, args.mutation)
            if args.build_only:
                args.exe.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(executable, args.exe)
                print('built integer normalization fixture', flush=True)
                return
            check(executable, args.wine, args.mutation)
            print('ok saturating int31 prefix and legacy defaults', flush=True)


if __name__ == '__main__':
    main()
