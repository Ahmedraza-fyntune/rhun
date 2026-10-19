#!/usr/bin/env python3
"""Compare incremental combinations with the actual parser, with exact scan/application budgets."""
import argparse
from collections import Counter
import importlib.util
import os
from pathlib import Path
import random
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CAP = 196610
UNSPECIFIED = (1 << 64) - 1


def work_counts(data):
    cursor = scans = tokens = 0
    while cursor < len(data):
        start = cursor
        first = data[cursor]
        scans += 1
        cursor += 1
        if first != ord('+'):
            while cursor < len(data):
                scans += 1
                if data[cursor] == ord('+'):
                    break
                cursor += 1
        token = data[start:cursor]
        skip = 2 if len(token) > 2 and token.startswith(b'0x') else 1 if len(token) >= 5 and token.startswith(b'U') else None
        if skip is not None:
            for value in token[skip:]:
                scans += 1
                if value not in b'0123456789abcdefABCDEF':
                    break
        tokens += 1
        if cursor < len(data):
            scans += 1
            if data[cursor] == ord('+'):
                cursor += 1
    return tokens, scans


def source_audit():
    keys = (ROOT / 'src/app/keys.s').read_text()
    generated = (ROOT / 'src/plat/keysyms.s').read_text()
    modifiers = re.findall(r'^\.Lm_\w+: \.asciz "([^"\\]*)"$', keys, re.M)
    aliases = re.findall(r'^\.Lk_\w+: \.asciz "([^"\\]*)"$', keys, re.M)
    names = re.findall(r'^\.Lk\d+: \.asciz "([^"\\]*)"$', generated, re.M)
    assert (len(modifiers), len(aliases), len(names)) == (7, 32, 2114)
    alias_bound = sum(len(name.encode()) for name in modifiers + aliases)
    name_bound = len(names).bit_length() * (max(len(name.encode()) for name in names) + 1)
    assert alias_bound == 155 and name_bound == 336
    assert 6 + alias_bound + name_bound == 497
    assert not any(len(name) > 2 and name.startswith('0x') or len(name) >= 5 and name.startswith('U') for name in modifiers + aliases)
    token = keys[keys.index('combo_token:'):keys.index('# str_ieq_cstr')]
    assert 'call keysym_value' in token and 'call to_lower' in token
    xkb = (ROOT / 'src/plat/xkb.s').read_text()
    assert xkb.count('FN keysym_name_value') == 1
    assert 'cmp word ptr [rbx], 0x7830' in xkb and "cmp byte ptr [rbx], 'U'" in xkb
    return modifiers, aliases, names


def cases():
    modifiers, aliases, names = source_audit()
    expected = [
        (b'', 0, 0), (b'a', 97, 0), (b'A', 97, 0), (b'+', 43, 0),
        (b'++', 43, 0), (b'+++', 43, 0), (b'+a', 97, 0),
        (b'ctrl++', 43, 4), (b'ctrl+++a', 97, 4), (b'a+ctrl', 97, 4),
        (b'ctrl+shift+A', 97, 5), (b'a+bad_nonexistent', 0, 0),
        (b'ctrl', 0, 4), (b'ctrl+ctrl', 0, 4), (b' ctrl', 0, 0),
        (b'ctrl+ ', 32, 4), (b'0x41junk', 65, 0), (b'0xq', 0, 0),
        (b'0X41', 0, 0), (b'U0041', 0x1000041, 0), (b'U041', 0, 0),
        (b'Return\0junk', 0xff0d, 0), (b'Left', 0xff51, 0),
        (b'0xffffffffffffffffffff', 0xffffffff, 0),
        (b'Uffffffffffffffffffff', 0xffffff, 0),
    ]
    result = []
    budgets = [(1, 1), (2, 2), (3, 16), (7, 1), (4096, 16), (0, 0)]
    for data, key, mods in expected:
        for byte_budget, token_budget in budgets:
            result.append((data, byte_budget, token_budget, key, mods))
    for name in modifiers + aliases:
        for data in (name.encode(), name.upper().encode(), b'ctrl+' + name.encode()):
            for byte_budget, token_budget in budgets:
                result.append((data, byte_budget, token_budget, UNSPECIFIED, UNSPECIFIED))
    # Every generated native keysym is compared with the actual oracle, including U-name fallback.
    for name in names:
        for byte_budget, token_budget in budgets:
            result.append((name.encode(), byte_budget, token_budget, UNSPECIFIED, UNSPECIFIED))
    rng = random.Random(1800)
    for _ in range(256):
        data = bytes(rng.randrange(256) for _ in range(rng.randrange(81)))
        result.append((data, 0, 0, UNSPECIFIED, UNSPECIFIED))
    huge = [b'0x' + b'0' * (CAP - 3) + b'F', b'U' + b'0' * (CAP - 2) + b'F',
            b'x' * CAP, (b'ctrl+' * (CAP // 5)) + b'a' * (CAP % 5)]
    for data in huge:
        assert len(data) == CAP
        for byte_budget, token_budget in ((1, 1), (7, 16), (4096, 16), (0, 0)):
            result.append((data, byte_budget, token_budget, UNSPECIFIED, UNSPECIFIED))
    return result


def scanner_inventory(source):
    # Exhaustive memory-operand inventory: changing a destination register cannot hide a read.
    step = source.split('FN keys_combo_step\n', 1)[1].split('FN keys_combo_result\n', 1)[0]
    indirect = []
    for raw in step.splitlines():
        instruction = ' '.join(raw.split('#', 1)[0].split())
        if instruction.startswith('lea '):
            continue
        for operand in re.findall(r'\[[^]]+\]', instruction):
            if not re.fullmatch(r'\[rbx \+ KC_\w+\]', operand):
                indirect.append(instruction)
    assert Counter(indirect) == Counter({
        'movzx eax, byte ptr [r8 + rcx]': 4,
        'cmp word ptr [r8], 0x7830': 1,
        "cmp byte ptr [r8], 'U'": 1,
    }), indirect
    rbx_operations = re.findall(r'^\s*(\w+\s+rbx(?:,.*)?)$', step, re.M)
    assert [line.strip() for line in rbx_operations] == ['mov rbx, rdi'], rbx_operations
    calls = re.findall(r'^\s*call (\w+)\s*$', step, re.M)
    assert Counter(calls) == Counter({'kc_validate': 1, 'keys_combo_token': 1, 'keysym_name_value': 1}), calls


def build(folder, windows=False, mutation=None):
    spec = importlib.util.spec_from_file_location('combo_build', ROOT / 'tests/faults/ext_store_build.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    source = (ROOT / 'src/app/keycombo.s').read_text()
    marker = '    movzx eax, byte ptr [r8 + rcx]\n'
    scanner_inventory(source)
    assert source.count(marker) == 4
    assert source.count('    call keys_combo_token\n') == source.count('    call keysym_name_value\n') == 1
    assert source.count('    cmp word ptr [r8], 0x7830\n') == 1
    assert source.count("    cmp byte ptr [r8], 'U'\n") == 1
    assert 'call parse_hex' not in source
    source = source.replace(marker, '    call kct_observed_read\n')
    if mutation == 'delimiter':
        start = source.index('.Lkcs_separator:')
        end = source.index('.Lkcs_numeric:', start)
        region = source[start:end]
        old = '    test r12, r12\n    jz .Lkcs_pending\n'
        assert region.count(old) == 1
        source = source[:start] + region.replace(old, '') + source[end:]
    elif mutation == 'plus':
        old = "    cmp al, '+'\n    jne .Lkcs_loop\n    mov qword ptr [rbx + KC_phase], KC_APPLY"
        assert source.count(old) == 1
        source = source.replace(old, '    jmp .Lkcs_loop\n    mov qword ptr [rbx + KC_phase], KC_APPLY')
    elif mutation == 'reset':
        old = '1:  mov [rbx + KC_key], eax\n'
        assert source.count(old) == 1
        source = source.replace(old, '1:  test eax, eax\n    jz .Lkcs_applied\n    mov [rbx + KC_key], eax\n')
    elif mutation == 'numeric':
        assert source.count('    je .Lkcs_start_hex\n') == source.count('    je .Lkcs_start_unicode\n') == 1
        source = source.replace('    je .Lkcs_start_hex\n', '    je .Lkcs_lookup\n')
        source = source.replace('    je .Lkcs_start_unicode\n', '    je .Lkcs_lookup\n')
    return builder.build(folder, (ROOT / 'tests/keycombo_test.s').read_text(),
                         {'src/app/keycombo.s': source}, windows=windows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wine')
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--negative-controls', action='store_true')
    parser.add_argument('--mutation', choices=('delimiter', 'plus', 'reset', 'numeric'))
    args = parser.parse_args()
    if args.build_only and not args.exe:
        parser.error('--build-only requires --exe')
    if args.negative_controls and (args.exe or args.build_only or args.mutation):
        parser.error('--negative-controls builds its own fixtures')
    windows = bool(args.wine) or os.name == 'nt' or bool(args.build_only and args.exe.suffix.lower() == '.exe')
    with tempfile.TemporaryDirectory(prefix='rhun-key-combo-') as temporary:
        folder = Path(temporary)
        exe = args.exe.resolve() if args.exe and not args.build_only else build(folder, windows, args.mutation)
        if args.build_only:
            args.exe.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(exe, args.exe)
            return
        records = cases()
        data = bytearray(struct.pack('<Q', len(records)))
        for value, byte_budget, token_budget, key, mods in records:
            tokens, scans = work_counts(value)
            data.extend(struct.pack('<7Q', len(value), byte_budget, token_budget, tokens, key, mods, scans))
            data.extend(value)
        input_file = folder / 'cases.bin'
        input_file.write_bytes(data)

        def run(target, mutation=None):
            command = [args.wine, 'Z:' + target.as_posix(), 'Z:' + input_file.as_posix()] if args.wine else [str(target), str(input_file)]
            result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=120)
            assert result.returncode == (72 if mutation else 0), result
            assert result.stdout == (b'' if mutation else b'ok resumable key combinations\n') and not result.stderr, result
        run(exe, args.mutation)
        if args.negative_controls:
            original = (ROOT / 'src/app/keycombo.s').read_text()
            marker = '    movzx eax, byte ptr [r8 + rcx]\n'
            unobserved = original.replace(marker, '    movzx edx, byte ptr [r8 + rcx]\n' + marker, 1)
            try:
                scanner_inventory(unobserved)
            except AssertionError:
                print('ok negative control: added read with a different destination is rejected')
            else:
                raise AssertionError('scanner inventory accepted an extra input read')
            for mutation in ('delimiter', 'plus', 'reset', 'numeric'):
                directory = folder / mutation
                directory.mkdir()
                run(build(directory, windows, mutation), mutation)
                print('ok negative control:', mutation)
    print('ok all 2114 keysym names, aliases, numeric/NUL quirks, exact scan/token budgets, ABI, invalid states and terminal input independence')


if __name__ == '__main__':
    main()
