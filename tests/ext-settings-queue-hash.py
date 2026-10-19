#!/usr/bin/env python3
"""Verify immutable queue hash caches, exact collisions and bounded byte comparisons."""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CODES = {'omit-cache': 40, 'prefix-only': 40, 'skip-key-equality': 40,
         'stale-new-identity': 42, 'zero-sentinel': 44,
         'skip-cache-audit': 40, 'unfiltered-comparisons': 46}
EXPECTED = (b'ok owned settings queue\n'
            b'ok queue identity cache, collisions and bounded comparison work\n')


def reference(section, key):
    value = 5381
    for item in [*section, len(section), 255, *key, len(key)]:
        value = ((value * 33) ^ item) & ((1 << 64) - 1)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--wine')
    parser.add_argument('--negative-controls', action='store_true')
    parser.add_argument('--mutation', choices=CODES)
    args = parser.parse_args()
    if args.build_only and not args.exe:
        parser.error('--build-only requires --exe')
    if args.negative_controls and (args.exe or args.build_only or args.mutation):
        parser.error('--negative-controls builds its own native fixtures')
    assert reference(b'owner/a', b'a3') == reference(b'owner/a', b'bP') == 0xa4656e1be0bd3dc2
    assert reference(b'owner/a', b'setting.a') == 0x0b3c02cb1a444842
    windows = os.name == 'nt' or bool(args.wine) or bool(
        args.build_only and args.exe.suffix.lower() == '.exe')
    spec = importlib.util.spec_from_file_location('queue_hash_build',
                                                 ROOT / 'tests/faults/ext_store_build.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)

    def build(folder, mutation=None):
        baseline = (ROOT / 'tests/ext_settingsqueue_test.s').read_text()
        assert baseline.count('FN main') == 1
        fixture = ('.equ TEST_SETTINGS_QUEUE_FAULT, 1\n'
                   + baseline.replace('FN main', 'FN original_settings_queue_main') + '\n'
                   + (ROOT / 'tests/ext_settings_queue_hash_cases.inc').read_text())
        queue = (ROOT / 'src/app/extsettingsqueue.s').read_text()
        helper = (ROOT / 'src/app/extsettingsqueuehash.s').read_text()
        library = (ROOT / 'src/lib.s').read_text()

        def replace(text, old, new):
            assert text.count(old) == 1, (old, text.count(old))
            return text.replace(old, new)

        queue = queue.replace('call ext_settings_memory_try', 'call sq_alloc')
        helper = replace(helper, 'FN ext_settings_queue_identity_hash\n',
                         'FN ext_settings_queue_identity_hash\n'
                         '    cmp qword ptr [rip + qh_force_zero], 0\n'
                         '    je 9f\n    xor eax, eax\n    xor edx, edx\n    ret\n9:\n')
        library = replace(library, 'FN memeq\n', 'FN memeq\n'
                          '    cmp qword ptr [rip + qh_counting], 0\n'
                          '    je 9f\n    add [rip + qh_bytes], rdx\n9:\n')
        if mutation == 'omit-cache':
            queue = replace(queue, '    mov [rax + EQC_hash], rdx\n', '')
        elif mutation == 'prefix-only':
            helper = replace(helper, '    xor rax, r9\n    xor edx, edx\n',
                              '    xor rax, r9\n    mov eax, 5381\n    xor edx, edx\n')
        elif mutation == 'skip-key-equality':
            queue = replace(queue, '    call memeq\n    test eax, eax\n    jnz 5f',
                            '    mov eax, 1\n    test eax, eax\n    jnz 5f')
        elif mutation == 'stale-new-identity':
            queue = replace(queue, '    mov [rax + EQC_hash], rdx\n',
                            '    cmp qword ptr [r12 + EC_keylen], 9\n'
                            '    jne 8f\n    mov rdx, 0xa4656e1be0bd3dc2\n'
                            '8:  mov [rax + EQC_hash], rdx\n')
        elif mutation == 'zero-sentinel':
            queue = replace(queue, '    mov [rsp + 32], rax\n',
                            '    test rax, rax\n    jz .Leqf_invalid\n'
                            '    mov [rsp + 32], rax\n')
        elif mutation == 'skip-cache-audit':
            fixture = fixture.replace('    cmp [r13 + EQC_hash], rax\n'
                                      '    jne .Lqha_bad\n', '')
        elif mutation == 'unfiltered-comparisons':
            queue = replace(queue, '    cmp [r13 + EQC_hash], rax\n    jne 3f\n', '')
        replacements = {'src/app/extsettingsqueue.s': queue,
                        'src/app/extsettingsqueuehash.s': helper, 'src/lib.s': library}
        for text in [fixture, *replacements.values()]:
            assert not re.search(r'(?m)^\s*\.section \.rodata[^\s\n]', text)
        return builder.build(folder, fixture, replacements, windows=windows)

    def check(executable, mutation=None):
        result = subprocess.run(([args.wine] if args.wine else []) + [str(executable)],
                                cwd=ROOT, capture_output=True, timeout=90)
        if mutation:
            assert result.returncode == CODES[mutation], (
                mutation, result.returncode, result.stdout, result.stderr)
        else:
            assert result.returncode == 0 and result.stdout + result.stderr == EXPECTED, (
                result.returncode, result.stdout, result.stderr)

    with tempfile.TemporaryDirectory(prefix='rhun-settings-queue-hash-') as temporary:
        folder = Path(temporary)
        if args.negative_controls:
            check(build(folder / 'baseline'))
            for mutation in CODES:
                check(build(folder / mutation, mutation), mutation)
                print('ok queue hash negative control ' + mutation, flush=True)
        else:
            executable = args.exe if args.exe and not args.build_only else build(folder, args.mutation)
            if args.build_only:
                args.exe.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(executable, args.exe)
                print('built queue identity cache fixture: ' + str(args.exe), flush=True)
                return
            check(executable, args.mutation)
            print('ok queue hash negative control ' + args.mutation if args.mutation
                  else 'ok queue identity cache, exact collisions, lifecycle and byte-work bound',
                  flush=True)


if __name__ == '__main__':
    main()
