#!/usr/bin/env python3
"""Complete-or-error directory scans, counted names, bounds and nested storage."""
import argparse
import importlib.util
import shutil
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


class FixtureFailure(AssertionError):
    pass


class Fixture:
    def __init__(self, executable, runner):
        self.command = [*runner, str(executable)]
        self.wine = bool(runner)

    def path(self, path):
        value = os.fsdecode(path)
        if self.wine and len(value) >= 2 and value[1] == ':':
            return value
        # Preserve trailing separators and symlink spelling for path tests.
        if not os.path.isabs(value):
            value = os.path.join(os.getcwd(), value)
        return 'Z:' + value if self.wine else value

    def run(self, path, cap, mode=0, repeat=1, nested=None):
        arguments = [*self.command, self.path(path), str(cap), str(mode), str(repeat)]
        if nested is not None:
            arguments.append(self.path(nested))
        options = {}
        if os.name == 'posix' and not self.wine:
            import resource

            def low_descriptors():
                resource.setrlimit(resource.RLIMIT_NOFILE, (32, 32))
            options['preexec_fn'] = low_descriptors
        result = subprocess.run(arguments, capture_output=True, timeout=45, **options)
        if result.returncode != 0 or result.stderr != b'':
            raise FixtureFailure(result)
        names, position = [], 0
        while True:
            assert position + 4 <= len(result.stdout), result.stdout
            length = struct.unpack_from('<I', result.stdout, position)[0]
            position += 4
            if length == 0xffffffff:
                break
            assert 0 < length <= 4095 and position + length <= len(result.stdout)
            names.append(result.stdout[position:position + length])
            position += length
        assert len(result.stdout) == position + 24, result.stdout[-100:]
        status, count, nested_count = struct.unpack_from('<qQQ', result.stdout, position)
        assert count == len(names) and len(set(names)) == len(names), (status, count, names)
        return status, set(names), nested_count


def names_in(path):
    return {os.fsencode(name) for name in os.listdir(path)}


def expect(fixture, path, cap, status=0, count=None, mode=0, repeat=1,
           complete=False, nested=None, nested_count=0):
    actual, names, observed_nested = fixture.run(path, cap, mode, repeat, nested)
    expected_statuses = status if isinstance(status, tuple) else (status,)
    assert actual in expected_statuses and observed_nested == nested_count, (
        path, cap, mode, actual, len(names), observed_nested)
    if count is not None:
        assert len(names) == count, (path, cap, mode, actual, names)
    if (mode < 4 or mode in (8, 9, 18) or mode in (13, 15, 42, 44, 45)) and os.path.isdir(path):
        source_names = names_in(path)
        assert names <= source_names, (path, names - source_names)
        if complete:
            assert names == source_names, (path, len(names), len(source_names))
    print('ok dir-scan/' + str(mode) + '/' + str(cap) + '/' + str(actual), flush=True)
    return names


def checks(fixture, folder):
    empty, small, large = [folder / name for name in ('empty', 'small', 'large')]
    for path in (empty, small, large):
        path.mkdir()
    # Windows refuses a name that ends with a dot ('...')
    names = ('alpha', '.hidden', '.pending', '...', 'é 水 😀', "spaces & '$ `")
    for name in names if sys.platform != 'win32' else [n for n in names if not n.endswith('.')]:
        (small / name).write_bytes(b'')
    nested = small / 'nested'
    nested.mkdir()
    for index in range(3):
        (nested / str(index)).write_bytes(b'')
    if sys.platform == 'linux' and not fixture.wine:
        descriptor = os.open(os.fsencode(small) + b'/\xffraw', os.O_CREAT | os.O_WRONLY, 0o600)
        os.close(descriptor)
    if os.name == 'posix' and not fixture.wine:
        (small / 'back\\slash').write_bytes(b'')
    for index in range(4097):
        (large / ('.pending-' + str(index).zfill(4) + 'x'*100)).write_bytes(b'')
    expect(fixture, empty, 0, count=0, repeat=64, complete=True)
    expect(fixture, small, 1048576, repeat=64, complete=True)
    expect(fixture, small, 0, status=-27, count=0)
    expect(fixture, empty, 0, mode=8, count=0, repeat=64, complete=True)
    expect(fixture, small, 4096, mode=8, repeat=64, complete=True)
    expect(fixture, small, 0, mode=8, status=-27, count=0, repeat=64)
    expect(fixture, small, 4096, mode=9, status=-125, count=1, repeat=64)
    expect(fixture, small, 4096, mode=18, status=-22, count=1, repeat=64)
    expect(fixture, small, 1, status=-27, count=1)
    expect(fixture, small, len(names_in(small)), complete=True)
    expect(fixture, large, 4096, status=-27, count=4096)
    expect(fixture, large, 4097, complete=True)
    expect(fixture, small, 1048577, status=-22, count=0)
    expect(fixture, small, (1 << 64)-1, status=-22, count=0)
    for mode, status in ((1, -125), (2, -22), (4, -22), (5, -22), (6, -36)):
        expect(fixture, small, 4096, status=status, count=1 if mode in (1, 2) else 0,
               mode=mode, repeat=64)
    expect(fixture, small, 4096, mode=3, nested=nested, nested_count=3,
           repeat=8, complete=True)
    if fixture.wine or os.name == 'nt':
        expect(fixture, small, 4096, status=-22, count=0, mode=7)
    expect(fixture, folder / 'missing', 4096, status=-2, count=0, repeat=64)
    regular = folder / 'file'
    regular.write_bytes(b'')
    expect(fixture, regular, 4096, status=-20, count=0, repeat=64)
    expect(fixture, str(small) + '/', 4096, status=-22, count=0)
    expect(fixture, str(small) + '//', 4096, status=-22, count=0)
    if fixture.wine or os.name == 'nt':
        expect(fixture, str(small) + chr(92), 4096, status=-22, count=0)
        expect(fixture, str(small) + chr(92)*2, 4096, status=-22, count=0)
    if os.name == 'posix' and not fixture.wine:
        link = folder / 'link'
        link.symlink_to(small, target_is_directory=True)
        expect(fixture, link, 4096, status=(-20, -40), count=0, repeat=64)
        expect(fixture, str(link) + '/', 4096, status=-22, count=0)
        expect(fixture, str(link) + '//', 4096, status=-22, count=0)
    root = Path.cwd().anchor
    expect(fixture, root, 0, status=-27, count=0)
    deep = folder
    for index in range(6):
        deep /= str(index) + 'x'*49
        deep.mkdir()
    (deep / 'é 水 😀').write_bytes(b'')
    expect(fixture, deep, 1, count=1, complete=True)
    return small, large, empty


def fault_builder():
    spec = importlib.util.spec_from_file_location('dir_scan_build', ROOT / 'tests/faults/dir_scan_build.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.build


def check_faults(fixture, small, large, windows=False):
    cases = [(10, -13, 0), (11, -5, 0), (12, -5, 1), (14, -13, 0), (16, -125, 1), (17, -22, 1)]
    if windows:
        cases += [(20, -5, 0), (21, -5, 0), (22, -5, 0), (23, -5, 0),
                  (24, -5, 0), (25, -5, 0), (26, -22, 0), (27, -5, 0),
                  (28, -5, 0), (29, -36, 0), (30, -5, 0), (31, -5, 0),
                  (32, -20, 0), (33, -20, 0), (34, -40, 0), (35, 0, 0),
                  (36, -5, 0), (37, -2, 1), (38, -2, 0), (39, -12, 0)]
    else:
        cases += [(mode, -36 if mode == 27 else -5, 1 if mode == 28 else 0)
                  for mode in range(20, 29)]
    for mode, status, count in cases:
        expect(fixture, small, 4096, mode=mode, status=status, count=count, repeat=64)
    expect(fixture, small, 4096, mode=13, status=-5, count=len(names_in(small)), repeat=64)
    if not windows:
        expect(fixture, small, 4096, mode=15, complete=True, repeat=64)
    # Native continuation after real batches also checks that a close error
    # cannot turn a complete multi-batch scan into success.
    expect(fixture, large, 4097, mode=13, status=-5, count=4097, repeat=8)


def check_native_mac(fixture, small, large):
    for mode in (40, 41):
        expect(fixture, small, 4096, mode=mode, status=-5, count=0, repeat=64)
    for mode in (42, 44, 45):
        expect(fixture, small, 4096, mode=mode, count=len(names_in(small)), complete=True, repeat=64)
    status, names, nested = fixture.run(large, 4097, mode=43, repeat=8)
    assert status == -5 and 0 < len(names) < 4097 and nested == 0, (status, len(names))
    assert names <= names_in(large)
    print('ok dir-scan/mac-native-error-after-batches', flush=True)


def reject_mutant(fixture, small, mode, status, count=None):
    try:
        actual, names, _ = fixture.run(small, 4096, mode=mode)
    except FixtureFailure as error:
        # The shared fixture also asserts the healthy same-process retry.
        # Stale-errno suppression can corrupt that retry as well.
        if mode != 42:
            raise
        result = error.args[0]
        assert result.returncode == 101 and result.stdout == b'' and result.stderr == b'', result
    else:
        assert actual != status or (count is not None and len(names) != count), (mode, actual, names)
    print('ok dir-scan/negative-control/' + str(mode), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--helpers-exe', type=Path)
    parser.add_argument('--wine')
    parser.add_argument('--fault-exe', type=Path)
    parser.add_argument('--negative-read-exe', type=Path)
    parser.add_argument('--negative-close-exe', type=Path)
    parser.add_argument('--build-windows-only', action='store_true')
    args = parser.parse_args()
    windows = bool(args.wine) or os.name == 'nt'
    if args.build_windows_only:
        with tempfile.TemporaryDirectory(prefix='rhun-dir-scan-build-') as directory:
            for mutation in (None, 'read', 'close'):
                name = 'dir_scan_' + (mutation + '_negative' if mutation else 'fault') + '_test.exe'
                shutil.copy2(fault_builder()(Path(directory) / name, windows=True, mutation=mutation),
                             ROOT / 'build/windows' / name)
        return
    runner = [args.wine] if args.wine else []
    executable = args.exe or ROOT / ('build/windows/dir_scan_test.exe' if windows else 'build/dir_scan_test')
    helpers = args.helpers_exe or ROOT / ('build/windows/dir_scan_helpers_test.exe'
                                        if windows else 'build/dir_scan_helpers_test')
    result = subprocess.run([*runner, str(helpers.resolve())], capture_output=True, timeout=15)
    assert result.returncode == 0 and result.stdout + result.stderr == (
        ROOT / 'tests/data/dir-scan-helpers.expected').read_bytes(), result
    print('ok dir-scan/helpers', flush=True)
    with tempfile.TemporaryDirectory(prefix='rhun-dir-scan-') as directory:
        folder = Path(directory)
        small, large, _ = checks(Fixture(executable.resolve(), runner), folder)
        build = fault_builder()
        fault = args.fault_exe or build(folder / 'fault', windows=windows)
        check_faults(Fixture(fault.resolve(), runner), small, large, windows)
        for mutation, supplied, mode, count in (
                ('read', args.negative_read_exe, 12, 1),
                ('close', args.negative_close_exe, 13, len(names_in(small)))):
            mutant = supplied or build(folder / ('negative-' + mutation), windows=windows, mutation=mutation)
            reject_mutant(Fixture(mutant.resolve(), runner), small, mode, -5, count)
        if sys.platform == 'darwin' and not windows:
            native = build(folder / 'native', native_mac=True)
            check_native_mac(Fixture(native, []), small, large)
            for mutation, mode, status in (('read', 40, -5), ('stale', 42, 0), ('interrupt', 44, 0)):
                mutant = build(folder / ('native-negative-' + mutation), native_mac=True, mutation=mutation)
                reject_mutant(Fixture(mutant, []), small, mode, status, len(names_in(small)) if mode == 44 else None)



if __name__ == '__main__':
    main()
