#!/usr/bin/env python3
"""Production GP streaming and actual owned reconstruction over native products."""
import argparse
import importlib.util
from pathlib import Path
import sys
import os
import signal
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

def fixture_input(corpus, folder, cases, products, managed_count):
    folder.mkdir(parents=True, exist_ok=True)
    corpus.inspect_input(folder, cases, managed_count)
    lines = ['.section .rodata', '.p2align 3', 'expected:']
    for i in range(len(products)):
        lines.append(f'    .quad image{i},image{i}_end-image{i}')
    for i, product in enumerate(products):
        path = folder / f'image{i}.bin'
        path.write_bytes(corpus.encode(product, i)[0])
        lines.append(f'image{i}: .incbin "{path.as_posix()}"\nimage{i}_end:')
    return (ROOT / 'tests/faults/discovery_gp_transfer.s').read_text() + '\n' + '\n'.join(lines) + '\n'

def mutations():
    p = 'src/app/'
    return [
        ('export_read_debit', (p+'extdiscoverygpexport.s', '    inc qword ptr [rdi + PGE_work]', '    nop'), None),
        ('export_output_debit', (p+'extdiscoverygpemit.s', '    inc qword ptr [rdi + PGE_work]', '    nop'), None),
        ('export_units', (p+'extdiscoverygpexport.s', '    inc qword ptr [rbx + PGE_units]', '    nop'), None),
        ('import_zero_debit', (p+'extdiscoverygpimport.s', '    add [rbx + PGI_work], rax', '    nop'), None),
        ('import_copy_debit', (p+'extdiscoverygpimport.s', '    shl rax, 1', '    nop'), None),
        ('import_units', (p+'extdiscoverygpimport.s', '    inc qword ptr [rdi + PGI_units]', '    nop'), None),
        ('token_revoked', (p+'extdiscoverygpimport.s', '    cmp qword ptr [r8 + 8], 1\n    jne .Lpi_stale_leaf', '    cmp qword ptr [r8 + 8], 1\n    nop'), 'r'),
        ('destination_pointer', (p+'extdiscoverygpimport.s', '    cmp [r10 + EP_grammars + VEC_ptr], rax\n    jne .Lpi_stale_leaf', '    cmp [r10 + EP_grammars + VEC_ptr], rax\n    nop'), 'p'),
        ('ready_store', (p+'extdiscoverygprelocate.s', '    mov qword ptr [r12 + PO_ready], 1', '    nop'), None),
        ('detach_store', (p+'extdiscoverygprelocate.s', '    mov qword ptr [r8 + DIA_gp], 0', '    nop'), None),
        ('early_clear', (p+'extdiscoverygpimport.s', '    cmp qword ptr [rax + DIA_state], DIA_EMPTY\n    jne .Lpi_busy', '    cmp qword ptr [rax + DIA_state], DIA_EMPTY\n    nop'), '0'),
        ('window_address', (p+'extdiscoverygpemit.s', '    mov [rax], dl', '    mov [rax + 1], dl'), None),
        ('retained_charge', ('src/mem.s', '    mov [rip + xfer_fail_total], rax', '    mov [rip + xfer_fail_total], rax\n    sub [rip + prep_total_charge], rcx'), 'Z'),
        ('native_field_authority', (p+'extdiscoverygprelocate.s', '    mov edx, GP_name_len', '    mov edx, GP_gr + GR_src'), None),
    ]

class LiveReleaseRetained(AssertionError):
    """A validated live probe found the SH lease retained after claimed release."""


def successful_lifetime(corpus, prefix, exe, native, expected_intercepts=0):
    assert expected_intercepts in (0, 1)
    with corpus.FixtureExchange([*map(str, prefix), str(exe), 'L', native],
                               timeout=60, output_bound=1024, error_bound=4096) as child:
        def probe():
            code, data, error = corpus.exchange(
                [*prefix, exe, 'P', native], timeout=min(10, child._remaining()), bound=1024)
            child._remaining()
            assert not data and not error, ('probe output', code, data, error)
            return code

        def alive():
            child._remaining()
            assert child.process.poll() is None, ('child exited before acknowledgement', child.process.returncode)

        assert child.read(1) == b'R'
        for command in (b'G', b'D'):
            alive()
            assert probe() == 75, 'SH lease escaped before final grammar release'
            alive()
            child.send(command)
            if command == b'G':
                assert child.read(1) == b'V'
        assert child.read(2) == bytes((ord('F'), expected_intercepts))
        alive()
        code = probe()
        alive()
        if code == 75:
            # Only this exact live-retention event may become expected control evidence.
            child.process.kill()
            data, error = child.finish()
            expected_kill = 1 if os.name == 'nt' else -signal.SIGKILL
            assert child.process.returncode == expected_kill, ('unexpected termination', child.process.returncode)
            assert not data and not error, ('retained fixture output', data, error)
            child._remaining()
            assert probe() == 0, 'lease survived forced process collection'
            child._remaining()
            raise LiveReleaseRetained('live EX probe refused after claimed grammar lease release')
        assert code == 0, ('unexpected live EX probe status', code)
        alive()
        child.send(b'E')
        data, error = child.finish()
        assert child.process.returncode == 0 and not data and not error, ('L lifetime', child.process.returncode, data, error)
        assert probe() == 0, 'lease survived successful process collection'
        child._remaining()


def lifetime(corpus, prefix, exe, wine_drive_root=None):
    if prefix:
        assert wine_drive_root is not None, 'Wine lifetime requires --wine-drive-root inside private prefix drive_c'
    for kind in ('L', 'Q'):
        with tempfile.TemporaryDirectory(prefix='gp-transfer-lease-', dir=wine_drive_root) as directory:
            root = Path(directory).resolve()
            (root / 'lease').touch()
            native = 'C:/' + root.name if prefix else root.as_posix()
            if kind == 'L':
                successful_lifetime(corpus, prefix, exe, native)
                print('actual independent GP/EO live-before-exit release L PASS', flush=True)
                continue
            with corpus.FixtureExchange([*map(str, prefix), str(exe), kind, native], timeout=60, output_bound=1024, error_bound=4096) as child:
                assert child.read(1) == b'R'
                for expected in (b'G', b'D'):
                    code, data, error = corpus.exchange([*prefix, exe, 'P', native])
                    assert code == 75 and not data and not error, ('lease escaped', code, error)
                    child.send(expected)
                    if expected == b'G':
                        assert child.read(1) == b'V'
                if kind == 'Q':
                    assert child.read(1) == b'Q'
                    code, data, error = corpus.exchange([*prefix, exe, 'P', native])
                    assert code == 75 and not data and not error, ('quarantine lease escaped', code, error)
                    child.send(b'U')
                data, error = child.finish()
                assert child.process.returncode == 0 and not data and not error, ('lifetime', kind, child.process.returncode, error)
            code, data, error = corpus.exchange([*prefix, exe, 'P', native])
            assert code == 0 and not data and not error, ('lease survived process collection', kind, code, error)
        print('actual independent GP/EO lease/tokenizer after EP/input/anchor disposal', kind, 'PASS', flush=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime-root', type=Path)
    parser.add_argument('--windows', action='store_true', default=sys.platform == 'win32')
    parser.add_argument('--wine', type=Path)
    parser.add_argument('--wine-drive-root', type=Path)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--prebuilt', type=Path)
    parser.add_argument('--inspection-data', type=Path)
    parser.add_argument('--build-inspector-only', action='store_true')
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--controls', action='store_true')
    parser.add_argument('--controls-dir', type=Path)
    args = parser.parse_args()
    if (args.build_only or args.build_inspector_only) and args.work is None:
        parser.error('retained build requires --work')
    corpus = module('transfer_reference', ROOT / 'tests/discovery-gp.py')
    builder = module('transfer_builder', ROOT / 'tests/faults/discovery_gp_transfer_build.py')
    temporary = tempfile.TemporaryDirectory(prefix='rhun-gp-transfer-') if args.work is None and args.prebuilt is None else None
    work = Path(args.work or (temporary.name if temporary else args.prebuilt.parent)).resolve()
    prefix = [args.wine] if args.wine else []
    try:
        work.mkdir(parents=True, exist_ok=True)
        if args.prebuilt:
            exe = args.prebuilt
        else:
            cases, managed_count, _, _, _ = corpus.source_cases()
            folder = work / 'inspect'
            folder.mkdir(exist_ok=True)
            corpus.inspect_input(folder, cases, managed_count)
            if args.inspection_data:
                data = args.inspection_data.read_bytes()
            else:
                inspector = builder.build(folder, (ROOT / 'tests/faults/discovery_gp_inspect.s').read_text(), args.windows, args.runtime_root)
                if args.build_inspector_only:
                    print(inspector, flush=True)
                    return
                code, data, error = corpus.exchange([*prefix, inspector])
                assert code == 0 and not error, ('native inspection', code, error)
            products = corpus.decode_images(data, cases, managed_count)
            folder = work / 'transfer'
            fixture = fixture_input(corpus, folder, cases, products, managed_count)
            exe = builder.build(folder, fixture, args.windows, args.runtime_root, instrument=True)
            print(f'native products {len(products)}', flush=True)
        control_commands = []
        if args.controls:
            assert not args.prebuilt, 'building controls requires actual native products'
            for name, mutation, fault in mutations():
                folder = work / ('control-' + name)
                full = fault == 'Z'
                fixture = fixture_input(corpus, folder, cases if full else cases[:1], products if full else products[:1], managed_count)
                mutant = builder.build(folder, fixture, args.windows, args.runtime_root, instrument=True, mutation=mutation)
                command = ['0', '0'] + ([fault] if fault else [])
                control_commands.append((name, mutant.relative_to(work).as_posix(), command))
                if not args.build_only:
                    code, data, error = corpus.exchange([*prefix, mutant, *command])
                    assert code == 73 and not data and len(error) in (0,48), ('control survived', name, code, error.hex())
                    print('control', name, 'rejected', flush=True)
            import json
            (work / 'controls.json').write_text(json.dumps(control_commands))
            live = module('transfer_live_controls', ROOT / 'tests/discovery-gp-transfer-live.py')
            folder = work / 'control-live-release'
            fixture = fixture_input(corpus, folder, cases[:1], products[:1], managed_count)
            retained = builder.build(folder, fixture, args.windows, args.runtime_root,
                                     instrument=True, mutation=live.retained_close_mutation())
            (work / 'live-controls.json').write_text(json.dumps(retained.relative_to(work).as_posix()))
        if args.build_only:
            print(exe, flush=True)
            return
        for budget in (3, 2, 1, 0):
            for cap in (3, 2, 1, 0):
                code, data, error = corpus.exchange([*prefix, exe, str(budget), str(cap)], timeout=180)
                assert code == 0 and not data and not error, ('roundtrip', budget, cap, code, error.hex())
                print(f'counted roundtrip budget{(2,3,4096,65536)[budget]} window{(1,3,4096,65536)[cap]} PASS', flush=True)
        code, data, error = corpus.exchange([*prefix, exe, '4', '3'], timeout=180)
        assert code == 0 and not data and not error, ('measure budget1', code, error.hex())
        print('counted measurement budget1 PASS', flush=True)
        for fault in '0123456789ABCtuarg svpcfXZdehijkm'.replace(' ', ''):
            code, data, error = corpus.exchange([*prefix, exe, '0', '0', fault])
            assert code == 0 and not data and not error, ('cancel/stale', fault, code, error.hex())
            print('cancel/stale', fault, 'PASS', flush=True)
        lifetime(corpus, prefix, exe, args.wine_drive_root)
        if args.controls_dir:
            import json
            for name, path, command in json.loads((args.controls_dir / 'controls.json').read_text()):
                code, data, error = corpus.exchange([*prefix, args.controls_dir / path, *command])
                assert code == 73 and not data and len(error) in (0,48), ('control survived', name, code, error.hex())
                print('control', name, 'rejected', flush=True)
        if args.controls or args.controls_dir:
            import json
            controls = args.controls_dir or work
            retained = controls / json.loads((controls / 'live-controls.json').read_text())
            live = module('transfer_live_control_checks', ROOT / 'tests/discovery-gp-transfer-live.py')
            driver = argparse.Namespace(successful_lifetime=successful_lifetime,
                                        LiveReleaseRetained=LiveReleaseRetained)
            live.controller_checks(driver)
            live.run_native(driver, corpus, prefix, exe, retained, args.wine_drive_root)
            print('default live-release distinguishing controls PASS', flush=True)
        print('production GP counted byte parity/owned reconstruction/abort PASS', flush=True)
    finally:
        if temporary is not None:
            temporary.cleanup()

if __name__ == '__main__':
    main()
