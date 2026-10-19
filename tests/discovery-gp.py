#!/usr/bin/env python3
"""Native parser images, canonical typed GP validation, malformed and budget controls.

The Python side packs inspected native products. It never parses grammar source.
"""
import argparse
import copy
import importlib.util
from pathlib import Path
import struct
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
from fixture_exchange import FixtureExchange


def exchange(command, timeout=120, bound=24 * 1024 * 1024):
    with FixtureExchange([str(x) for x in command], timeout=timeout,
                         output_bound=bound, error_bound=4096) as job:
        out, error = job.finish()
        return job.process.returncode, out, error


def fnv(text):
    value = 2166136261
    for byte in text:
        value = ((value ^ byte) * 16777619) & 0xffffffff
    return value


def source_cases():
    cases = [(p.name, p.read_bytes()) for p in sorted((ROOT / 'runtime/syntax').glob('*.syn'))]
    managed_count = len(cases)
    cases += [
        ('overwritten', b'name=longpriorname\nname=\nfiles=prior\nfiles=\nfirst=old\nfirst=\nicon=old\nicon=\ncomment=///\nkeywords=Alpha Beta Alpha\ncase=insensitive\nkeywords=alpha beta Gamma\n'),
        ('long_name', b'name=' + b'a' * (2097152 - 6) + b'\n'),
        ('long_word', b'name=A\nkeywords=' + b'b' * (2097152 - 17) + b'\n'),
        ('word_max', b'name=A\nkeywords=' + b' '.join(f'w{i:05d}'.encode() for i in range(65536)) + b'\n'),
        ('rules_max', b'name=A\n' + b'comment=#\n' * 4096),
        ('folded_grow', b'name=A\nkeywords=Abc abc ' + b' '.join(f'w{i:02d}'.encode() for i in range(30)) + b'\ncase=insensitive\nkeywords=unique_new\n'),
        ('ident_tail', b'name=A\nident_extra=abcdefghijk\nident_extra=z\n'),
    ]
    words = [b'x' * 24 + f'{n:06d}'.encode() for n in range(65536)]
    text = b'name=A\nkeywords=' + b' '.join(words) + b'\n'
    words[0] += b'z' * (2097152 - len(text))
    text = b'name=A\nkeywords=' + b' '.join(words) + b'\n'
    assert len(text) == 2097152
    cases.append(('word_max_source_max', text))
    lower = 'éééé'.encode()
    variants = [''.join('É' if mask >> i & 1 else 'é' for i in range(4)).encode()
                for mask in range(1, 16)]
    prior = next(v for v in variants if fnv(v + b'ci') % 64 == fnv(lower + b'ci') % 64)
    suffix = next(bytes((a, b)) for a in range(97, 123) for b in range(97, 123)
                  if bytes((a, b)) != b'aa' and fnv(lower + bytes((a, b))) % 128 == fnv(prior + b'aa') % 128)
    candidate = lower + bytes((suffix[0] - 32, suffix[1]))
    width_prior = next(b'a' + bytes((a, b)) for a in range(97, 123) for b in range(97, 123)
                       if fnv(b'a' + bytes((a, b))) % 64 == fnv('aé'.encode()) % 64)
    cases += [
        ('unicode_collision', b'name=Unicode\ncase=insensitive\nkeywords=' + prior + b'aa ' + candidate + b'\n'),
        ('unicode_grow', b'name=Unicode\ncase=insensitive\nkeywords=' + prior + b'aa ' + candidate + b' ' + b' '.join(f'w{i:02d}'.encode() for i in range(31)) + b'\n'),
        ('unicode_equal', b'name=Unicode\ncase=insensitive\nkeywords=' + prior + b'ci\ntypes=' + lower + b'Ci\n'),
        ('unicode_width', b'name=Unicode\ncase=insensitive\nkeywords=' + width_prior + b' ' + 'Aé'.encode() + b'\n'),
        ('greek', 'name=Unicode\nkeywords=Σ σ ς\ncase=insensitive\ntypes=Σ\n'.encode()),
        ('cyrillic', 'name=Unicode\nkeywords=Б б Ж ж\ncase=insensitive\ntypes=Б\n'.encode()),
        ('empty_legacy', b''),
        ('rules_tokens', b'name=Rules\ncomment=//\nstring=" " \\\nline_comment=#\nident_extra=+$\nprefixes=@\n'),
    ]
    prefix, colliders, number = b'q' * 120, [], 0
    seed = fnv(prefix)
    while len(colliders) < 513:
        suffix = f'{number:08x}'.encode()
        value = seed
        for byte in suffix:
            value = ((value ^ byte) * 16777619) & 0xffffffff
        if value % 2048 == 0:
            colliders.append(prefix + suffix)
        number += 1
    cases.append(('probe512', b'name=Collision\nkeywords=' + b' '.join(colliders[:512]) + b'\n'))
    return cases, managed_count, prior, lower + b'Ci', colliders[-1]


def inspect_input(folder, cases, managed_count):
    lines = ['.include "rhun.inc"', '.include "app/extprepare.inc"', '.section .rodata',
             '.p2align 3', f'.equ GPC_INPUT_COUNT, {len(cases)}',
             f'.equ GPC_MANAGED_COUNT, {managed_count}', 'probe_cases:']
    for i, (_, text) in enumerate(cases):
        lines.append(f'    .quad probe_{i}, {len(text)}')
    lines.append('probe_fields: .quad GR_name, GR_files, GR_first, GR_icon, GR_comment')
    for i, (_, text) in enumerate(cases):
        path = folder / f'input{i}.syn'
        path.write_bytes(text)
        lines.append(f'probe_{i}: .incbin "{path.as_posix()}"')
    (folder / 'gpc-input.inc').write_text('\n'.join(lines) + '\n')


def decode_images(data, cases, managed_count):
    cursor = 0

    def take(count):
        nonlocal cursor
        assert 0 <= count <= len(data) - cursor, (count, cursor, len(data))
        value = data[cursor:cursor + count]
        cursor += count
        return value

    products = []
    for index, (name, text) in enumerate(cases):
        source, mode, flags, warnings, cap, wn, nr, nl = struct.unpack('<8Q', take(64))
        assert source == len(text) and mode == (1 if index < managed_count else 2)
        assert cap <= 131072 and nr + nl <= 4096
        fields = []
        for _ in range(5):
            count = struct.unpack('<Q', take(8))[0]
            fields.append(None if count == 2**64 - 1 else take(count))
        regions, lines, arrays = take(nr * 40), take(nl * 24), take(576)
        words = []
        for _ in range(cap):
            count, cls, reserved = struct.unpack('<QII', take(16))
            assert reserved == 0
            words.append(None if count == 2**64 - 1 else (take(count), cls))
        chars = sum(len(f) for f in fields if f is not None) + sum(len(w[0]) for w in words if w)
        assert chars <= source, (name, chars, source)
        products.append(dict(name=name, source=text, mode=mode, flags=flags, warnings=warnings,
                             cap=cap, wn=wn, fields=fields, regions=regions, lines=lines,
                             arrays=arrays, words=words))
    assert cursor == len(data)
    return products


def encode(product, ordinal):
    cap = product['cap']
    nr, nl = len(product['regions']) // 40, len(product['lines']) // 24
    cursor, descriptors = 256, []
    for count in (cap * 16, nr * 40, nl * 24, 576):
        descriptors.append((cursor if count else 0, count))
        cursor += count
    poolbase, pool, spans = cursor, bytearray(), []

    def string(text):
        if text is None:
            return 0, 0
        span = poolbase + len(pool), len(text)
        pool.extend(text)
        pool.append(0)
        return span

    for text in product['fields']:
        spans.append(string(text))
    words, occupied = bytearray(), 0
    for word in product['words']:
        if word is None:
            words.extend(bytes(16))
        else:
            text, cls = word
            off, count = string(text)
            words.extend(struct.pack('<QII', off, count, cls))
            occupied += 1
    header, total = bytearray(256), cursor + len(pool)
    header[:8] = b'RHGPR1\0\0'
    struct.pack_into('<IIQIIQQIIII', header, 8, 1, 256, total, ordinal, product['mode'],
                     product['flags'], product['warnings'], cap, product['wn'], nr, nl)
    for i, span in enumerate(spans):
        struct.pack_into('<QQ', header, 64 + i * 16, *span)
    for i, desc in enumerate(descriptors):
        struct.pack_into('<QQ', header, 144 + i * 16, *desc)
    struct.pack_into('<I', header, 208, occupied)
    wire = bytes(header) + words + product['regions'] + product['lines'] + product['arrays'] + pool
    assert len(wire) == total <= 4424517
    return bytes(wire), [total, product['mode'], ordinal, len(product['source']), cap,
                         product['wn'], occupied, nr, nl, product['flags'], product['warnings']]


def test_rows(products, prior, candidate, collider513):
    rows = []
    for i, product in enumerate(products):
        wire, info = encode(product, i % 258)
        rows.append((product['name'], wire, info, 0))
    base = next(p for p in products if p['name'] == 'unicode_equal')
    original, info = encode(base, 0)

    def bad(name, offset=None, value=None, fmt=None, wire=None):
        data = bytearray(original if wire is None else wire)
        if offset is not None:
            if fmt:
                struct.pack_into(fmt, data, offset, value)
            else:
                data[offset:offset + len(value)] = value
        fields = list(info)
        fields[0] = len(data)
        rows.append(('bad_' + name, bytes(data), fields, -1011))

    for name, offset, value, fmt in [
        ('magic', 0, b'X', None), ('version', 8, 2, '<I'), ('headersize', 12, 255, '<I'),
        ('total', 16, 2**64 - 1, '<Q'), ('ordinal', 24, 257, '<I'), ('mode', 28, 1, '<I'),
        ('flags', 32, 256, '<Q'), ('warnings_negative', 40, 2**64 - 1, '<Q'),
        ('cap_small', 48, 32, '<I'), ('cap_large', 48, 262144, '<I'),
        ('cap_power', 48, 65, '<I'), ('parser_zero', 52, 0, '<I'),
        ('parser_over', 52, 33, '<I'), ('rules_over', 56, 4097, '<I'),
        ('words_offset', 144, 264, '<Q'), ('words_length', 152, 1023, '<Q'),
        ('empty_vector', 160, 256, '<Q'), ('array_offset', 192, 2**64 - 1, '<Q'),
        ('array_length', 200, 575, '<Q'), ('occupied_zero', 208, 0, '<I'),
        ('occupied_more', 208, 2, '<I'), ('reserved', 255, b'\x01', None),
        ('pool_alias', 80, struct.unpack_from('<Q', original, 64)[0], '<Q'),
        ('pool_overflow', 64, 2**64 - 1, '<Q'), ('field_length', 72, 2**64 - 1, '<Q'),
    ]:
        bad(name, offset, value, fmt)
    arrays = struct.unpack_from('<Q', original, 192)[0]
    for name, index, byte in [('ident_nul', 0, b'a' * 32), ('prefix_nul', 32, b'a' * 32),
                              ('rstart', 64, b'\x01'), ('wchar', 320, b'\xff')]:
        bad(name, arrays + index, byte)
    nameoff, namelen = struct.unpack_from('<QQ', original, 64)
    for label, content in [('nul', b'\0'), ('utf8', b'\xff'), ('overlong', b'\xc0'),
                           ('control', b'\x7f'), ('continuation', b'\x80')]:
        bad('pool_' + label, nameoff, content)
    bad('name_terminal', nameoff + namelen, b'a')
    occupied = next(i for i, w in enumerate(base['words']) if w)
    empty = next(i for i, w in enumerate(base['words']) if not w)
    for label, off, value, fmt in [('halfempty', 256 + empty * 16 + 8, 1, '<I'),
                                  ('word_class', 256 + occupied * 16 + 12, 20, '<I'),
                                  ('word_empty', 256 + occupied * 16 + 8, 0, '<I'),
                                  ('word_overflow', 256 + occupied * 16, 2**64 - 1, '<Q')]:
        bad(label, off, value, fmt)
    bad('trailing', wire=original + b'\0')
    for end in (256, 257, 271, 1279, 1280, 1855, len(original) - 1):
        if end < len(original):
            truncated = bytearray(original[:end])
            struct.pack_into('<Q', truncated, 16, end)
            bad('truncated_' + str(end), wire=truncated)
    # Canonical full re-encoding isolates hash/probe validation from pool ordering.
    moved = copy.deepcopy(base)
    moved['words'][(occupied + 7) % 64] = moved['words'][occupied]
    moved['words'][occupied] = None
    wire, fields = encode(moved, 0)
    rows.append(('bad_unreachable', wire, fields, -1011))
    forged = copy.deepcopy(base)
    bucket = fnv(candidate.lower()) % 64
    assert occupied == bucket and forged['words'][(bucket + 1) % 64] is None
    forged['words'][occupied] = (prior + b'ci', forged['words'][occupied][1])
    forged['words'][(bucket + 1) % 64] = (candidate, 2)
    forged['wn'] = 2
    wire, fields = encode(forged, 0)
    rows.append(('bad_later_unicode_equal', wire, fields, -1011))
    # Additional source-bound control/noncanonical encodings in a fresh canonical pool.
    for label, text in [('surrogate', b'\xed\xa0\x80'), ('too_high', b'\xf4\x90\x80\x80'),
                        ('c1', b'\xc2\x85'), ('unfinished', b'\xe2\x82')]:
        changed = copy.deepcopy(base)
        changed['fields'][0] = text
        wire, fields = encode(changed, 0)
        rows.append(('bad_' + label, wire, fields, -1011))
    # These malformed images retain matching request/header correlation and canonical pools.
    def bad_product(label, product, changes=None):
        wire, fields = encode(product, 0)
        data = bytearray(wire)
        for offset, fmt, value in changes or []:
            struct.pack_into(fmt, data, offset, value)
        rows.append(('bad_' + label, bytes(data), fields, -1011))
    strict = copy.deepcopy(next(p for p in products if p['mode'] == 1))
    for label, text in [('strict_empty', b''), ('strict_tab', b'a\tb'), ('strict_name_long', b'a' * 129)]:
        value = copy.deepcopy(strict)
        value['fields'][0] = text
        bad_product(label, value)
    bad_product('strict_warnings', strict, [(40, '<Q', 1)])
    bad_product('null_required', base, [(64, '<Q', 0)])
    rule_product = next(p for p in products if p['regions'])
    wire, fields = encode(rule_product, 0)
    reg = struct.unpack_from('<Q', wire, 160)[0]
    for label, offset, value in [('reg_len', 32, 16), ('reg_elen', 33, 16),
                                  ('reg_class', 34, 20), ('reg_multi', 36, 2),
                                  ('reg_bol', 37, 2), ('reg_reserved', 38, 1)]:
        bad_product(label, rule_product, [(reg + offset, '<B', value)])
    startlen, endlen = wire[reg + 32], wire[reg + 33]
    bad_product('reg_terminal', rule_product, [(reg + startlen, '<B', 65)])
    bad_product('reg_end_terminal', rule_product, [(reg + 16 + endlen, '<B', 65)])
    if startlen < 15:
        bad_product('reg_padding', rule_product, [(reg + 15, '<B', 65)])
    line_product = next(p for p in products if p['lines'])
    wire, fields = encode(line_product, 0)
    line = struct.unpack_from('<Q', wire, 176)[0]
    bad_product('line_length', line_product, [(line + 16, '<I', 16)])
    bad_product('line_class', line_product, [(line + 20, '<I', 20)])
    length = struct.unpack_from('<I', wire, line + 16)[0]
    bad_product('line_terminal', line_product, [(line + length, '<B', 65)])
    # Change only the claimed source size. The matching counted wire itself remains complete.
    wire, fields = encode(base, 0)
    fields[3] = 0
    rows.append(('bad_source_pool_bound', wire, fields, -1011))
    # 512 inclusive actual parser probes is valid. The 513th forged same-bucket slot is not.
    collision = copy.deepcopy(next(p for p in products if p['name'] == 'probe512'))
    assert collision['cap'] == 1024 and all(collision['words'][i] for i in range(512))
    collision['words'] += [None] * 1024
    collision['cap'] = 2048
    collision['words'][512] = (collider513, 1)
    collision['wn'] = 513
    collision['source'] += collider513 + b' '
    bad_product('probe513', collision)
    return rows


def validator_input(folder, rows):
    lines = ['.include "rhun.inc"', '.include "app/extvalidate.inc"',
             '.include "app/extdiscoverygp.inc"', '.section .rodata', '.p2align 3',
             f'.equ GPC_CASE_COUNT, {len(rows)}', 'gpc_cases:']
    for i, (_, _, fields, expected) in enumerate(rows):
        lines.append(f'    .quad gpc_wire_{i}, ' + ', '.join(str(n) for n in [*fields, expected]))
    for i, (_, wire, _, _) in enumerate(rows):
        path = folder / f'case{i}.bin'
        path.write_bytes(wire)
        lines.append(f'gpc_wire_{i}: .incbin "{path.as_posix()}"')
    (folder / 'gpc-cases.inc').write_text('\n'.join(lines) + '\n')


def mutations():
    root = 'src/app/'
    return [
        ('hidden_parser', (root+'extdiscoverygpvalidate.s', '.Lpg_step_copy:\n    call pg_header_copy_step', '.Lpg_step_copy:\n    call grammar_parse_prepare\n    call pg_header_copy_step')),
        ('hidden_io', (root+'extdiscoverygpvalidate.s', '.Lpg_step_copy:\n    call pg_header_copy_step', '.Lpg_step_copy:\n    call file_read_all\n    call pg_header_copy_step')),
        ('hidden_allocator', (root+'extdiscoverygpvalidate.s', '.Lpg_step_copy:\n    call pg_header_copy_step', '.Lpg_step_copy:\n    call mem_alloc\n    call pg_header_copy_step')),
        ('address_overflow', (root+'extdiscoverygpvalidate.s', '    add rcx, rax\n    jc .Lpg_api', '    add rcx, rax\n    nop')),
        ('read_debit', (root+'extdiscoverygpvalidate.s', '    inc qword ptr [rdi + GPC_bytes]', '    nop')),
        ('write_debit', (root+'extdiscoverygpvalidate.s', '    mov [rsi], dl\n    inc qword ptr [rip + gpc_byte_actual]\n    dec qword ptr [rdi + GPC_budget]\n    inc qword ptr [rdi + GPC_bytes]', '    mov [rsi], dl\n    inc qword ptr [rip + gpc_byte_actual]\n    dec qword ptr [rdi + GPC_budget]')),
        ('unit_debit', (root+'extdiscoverygpvalidate.s', '    inc qword ptr [rbx + GPC_units]', '    nop')),
        ('budget_debit', (root+'extdiscoverygpvalidate.s', '    dec qword ptr [rdi + GPC_budget]', '    nop')),
        ('fold_debit', (root+'extdiscoverygpvalidate.s', '    add qword ptr [rbx + GPC_units], 9', '    add qword ptr [rbx + GPC_units], 8')),
        ('fold_admission', (root+'extdiscoverygpvalidate.s', '    cmp qword ptr [rdi + GPC_units], 7', '    cmp qword ptr [rdi + GPC_units], 16')),
        ('flags', (root+'extdiscoverygpvalidate.s', '    cmp rax, 255', '    cmp rax, 511')),
        ('class', (root+'extdiscoverygpword.s', '    cmp qword ptr [rbx + GPC_candidateclass], C_COUNT', '    cmp qword ptr [rbx + GPC_candidateclass], C_COUNT + 1')),
        ('arrays', (root+'extdiscoverygprecord.s', '    cmp rax, [rbx + GPC_comparebyte]\n    jne .Lpgr_bad', '    cmp rax, [rbx + GPC_comparebyte]\n    nop')),
        ('utf8_controls', (root+'extdiscoverygpstring.s', '    cmp eax, 160\n    jb .Lpgs_bad', '    cmp eax, 160\n    nop')),
        ('terminator', (root+'extdiscoverygpstring.s', '    test eax, eax\n    jne .Lpgs_step_bad', '    test eax, eax\n    nop')),
        ('canonical', (root+'extdiscoverygpstring.s', '    cmp rsi, [rdi + GPC_stringcursor]\n    jne .Lpgs_bad', '    cmp rsi, [rdi + GPC_stringcursor]\n    nop')),
        ('unicode_equality', (root+'extdiscoverygpprobe.s', '3:  mov qword ptr [rbx + GPC_comparestate], 3', '3:  jmp .Lpgc_different')),
        ('probe_bound', (root+'extdiscoverygpprobe.s', '    cmp qword ptr [rbx + GPC_probes], 512', '    cmp qword ptr [rbx + GPC_probes], 513')),
    ]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime-root', type=Path)
    parser.add_argument('--windows', action='store_true', default=sys.platform == 'win32')
    parser.add_argument('--wine', type=Path)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--prebuilt', type=Path)
    parser.add_argument('--controls', action='store_true')
    parser.add_argument('--build-inspector-only', action='store_true')
    parser.add_argument('--inspection-data', type=Path)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--controls-dir', type=Path)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('gpbuild', ROOT / 'tests/faults/discovery_gp_build.py')
    build = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(build)
    temporary = None
    if args.work is None and args.prebuilt is None:
        if args.build_only or args.build_inspector_only:
            parser.error('building retained fixtures requires --work')
        temporary = tempfile.TemporaryDirectory(prefix='rhun-discovery-gp-')
    work = Path(args.work or (temporary.name if temporary else args.prebuilt.parent)).resolve()
    try:
        work.mkdir(parents=True, exist_ok=True)
        command_prefix = [args.wine] if args.wine else []
        if args.prebuilt:
            exe = args.prebuilt
        else:
            cases, managed_count, prior, candidate, collider513 = source_cases()
            folder = work / 'inspect'
            folder.mkdir(exist_ok=True)
            inspect_input(folder, cases, managed_count)
            if args.inspection_data:
                out = args.inspection_data.read_bytes()
            else:
                inspect_exe = build.build(folder, (ROOT / 'tests/faults/discovery_gp_inspect.s').read_text(),
                                          args.windows, args.runtime_root)
                if args.build_inspector_only:
                    print(inspect_exe, flush=True)
                    return
                code, out, error = exchange([*command_prefix, inspect_exe])
                assert code == 0 and not error, ('native inspection', code, error)
            products = decode_images(out, cases, managed_count)
            rows = test_rows(products, prior, candidate, collider513)
            folder = work / 'validate'
            folder.mkdir(exist_ok=True)
            validator_input(folder, rows)
            (work / 'rows.txt').write_text('\n'.join(name for name, _, _, _ in rows) + '\n')
            exe = build.build(folder, (ROOT / 'tests/faults/discovery_gp_validate.s').read_text(),
                              args.windows, args.runtime_root, instrument=True)
            print(f'actual parser products {len(products)}, malformed {len(rows)-len(products)}', flush=True)
        if not args.build_only:
            code, out, error = exchange([*command_prefix, exe, '3'])
            assert code == 0 and not out and not error, ('API', code, error)
            print('API refusal/cancellation PASS', flush=True)
            for budget in (2, 1, 0):
                code, out, error = exchange([*command_prefix, exe, str(budget)])
                assert code == 0 and not out and not error, ('budget', budget, code, error,
                                                             struct.unpack('<2Qq3Q', error) if len(error) == 48 else None)
                print(f'budget { (1,4096,65536)[budget] } PASS', flush=True)
        control_commands = []
        if args.controls:
            assert not args.prebuilt, 'controls need the actual inspected products'
            small = [row for row in rows if len(row[1]) < 4096 or row[0] in ('probe512', 'bad_probe513')]
            for name, mutation in mutations():
                folder = work / ('control-' + name)
                folder.mkdir(exist_ok=True)
                validator_input(folder, small)
                mutant = build.build(folder, (ROOT / 'tests/faults/discovery_gp_validate.s').read_text(),
                                     args.windows, args.runtime_root, instrument=True, mutation=mutation)
                mode = '3' if name == 'address_overflow' else ('0' if name == 'budget_debit' else '2')
                control_commands.append((name, mode, str(mutant.relative_to(work))))
                if not args.build_only:
                    code, out, error = exchange([*command_prefix, mutant, mode])
                    assert code == 73 and not out and len(error) == 48, ('control survived', name, code, error)
                    print('control', name, 'rejected', flush=True)
            (work / 'controls.txt').write_text(''.join(' '.join(row) + '\n' for row in control_commands))
        if args.controls_dir:
            for line in (args.controls_dir / 'controls.txt').read_text().splitlines():
                name, mode, path = line.split()
                code, out, error = exchange([*command_prefix, args.controls_dir / path, mode])
                assert code == 73 and not out and len(error) == 48, ('control survived', name, code, error)
                print('control', name, 'rejected', flush=True)
        print('discovery GP ' + ('fixtures BUILT' if args.build_only else 'native inspection/validation PASS; budget1 skips wires above65536'), flush=True)
    finally:
        if temporary is not None:
            temporary.cleanup()


if __name__ == '__main__':
    main()
