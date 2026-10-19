#!/usr/bin/env python3
"""Build and execute every metadata ownership case on native hosts or prebuilt Wine."""
import argparse
import hashlib
import importlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
METADATA = ('provider', 'icon', 'events', 'options', 'marks', 'command', 'titlebar',
            'mark-display', 'mark-bookkeeping')
CATALOG = ('allocation', 'free', 'native-close', 'skip-page')
PROMPT = ('skip-open', 'skip-close', 'skip-pure', 'skip-ext_init', 'skip-ext_load',
          'skip-ext_slot_metadata_take', 'skip-ext_host_identity_take')
SESSION = ('bind-bytes', 'hi', 'ea', 'keeper', 'disabled', 'bytewalk')
SETUP = {'fake-eof': 1, 'keeper-owner': 15, 'setup-primary': 9,
         'child-diagnostic': 12, 'unknown-disposition': 14}
MANIFEST_LIMIT = 131072
EXECUTABLE_LIMIT = 64 * 1048576
ROSETTA_ERROR = b'rosetta error: invalid gdt selector index 5\n '


def matrix(windows):
    rows = []
    def add(identifier, family, mutation=None, mode=0, long=False):
        rows.append(dict(id=identifier, family=family, mutation=mutation,
                         mode=mode, long=long))
    for family, mutations in (('metadata', METADATA), ('catalog', CATALOG), ('prompt', PROMPT)):
        add('borrow-' + family + '/baseline', family)
        for mutation in mutations:
            add('borrow-' + family + '/' + mutation, family, mutation)
    for mode in range(1, 19):
        if not windows or mode not in (5, 6):
            add('setup/' + str(mode), 'setup', mode=mode)
    for mutation, mode in SETUP.items():
        add('setup/negative-' + mutation, 'setup', mutation, mode)
    add('session/baseline', 'session')
    add('session/maximum', 'session', long=True)
    for mutation in SESSION:
        add('session/' + mutation, 'session', mutation)
    for family in ('identity', 'owned', 'identity-fault', 'owned-fault'):
        add(family, family)
    add('save-identity/baseline', 'save-identity')
    for mutation in ('skip-identity', 'skip-visibility', 'skip-survivor'):
        add('save-identity/' + mutation, 'save-identity', mutation)
    assert len(rows) == (60 if windows else 62)
    return rows


def executable_name(case, windows):
    return 'bin/' + case['id'] + ('/test.exe' if windows else '/test')


def digest(path):
    size = path.stat().st_size
    if not 0 < size <= EXECUTABLE_LIMIT:
        raise ValueError(('executable size outside bound', path, size))
    hasher = hashlib.sha256()
    with path.open('rb') as stream:
        count = 0
        while True:
            block = stream.read(1048576)
            if not block:
                break
            count += len(block)
            if count > EXECUTABLE_LIMIT:
                raise ValueError(('executable grew beyond bound', path))
            hasher.update(block)
    if count != size:
        raise ValueError(('executable size changed', path))
    return hasher.hexdigest()


def build_all(root, folder, windows):
    if (folder / 'manifest.json').exists():
        raise ValueError('build output already has a manifest; use a fresh directory')
    folder.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(root / 'tests/faults'))
    modules = {name: importlib.import_module('ext_' + name + '_borrowers_build')
               for name in ('metadata', 'catalog', 'prompt')}
    modules['session'] = importlib.import_module('ext_running_session_build')
    modules['setup'] = importlib.import_module('ext_host_setup_native_build')
    modules['identity-fault'] = importlib.import_module('ext_host_identity_build')
    modules['owned-fault'] = importlib.import_module('ext_host_owned_build')
    for module in modules.values():
        if module.ROOT.resolve() != root:
            raise ValueError(('fixture builder belongs to another source tree', module.__file__))
    spec = importlib.util.spec_from_file_location('metadata_save_identity', root / 'tests/ext-settings-save-identity.py')
    modules['save-identity'] = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modules['save-identity'])
    if modules['save-identity'].ROOT.resolve() != root:
        raise ValueError('save identity fixture belongs to another source tree')
    assert tuple(modules['metadata'].MUTATIONS) == METADATA
    assert tuple(modules['session'].MUTATIONS) == SESSION
    assert modules['setup'].MUTATIONS == SETUP
    assert tuple(modules['setup'].MODES) == tuple(range(1, 19))
    manifest = dict(version=1, platform='windows' if windows else 'posix', cases=[])
    for case in matrix(windows):
        family = case['family']
        work = folder / '_build' / case['id']
        if family in ('metadata', 'catalog', 'prompt'):
            built = modules[family].build(work, windows=windows, mutation=case['mutation'])
        elif family == 'save-identity':
            built = modules[family].build(work, windows=windows, mutation=case['mutation'])
        elif family == 'session':
            built = modules[family].build(work, windows=windows,
                                          mutation=case['mutation'], long=case['long'])
        elif family == 'setup':
            built = modules[family].build(work, case['mode'], windows=windows,
                                          mutation=case['mutation'])
        elif family in ('identity-fault', 'owned-fault'):
            built = modules[family].build(work, windows=windows)
        else:
            name = 'ext_host_identity_test.s' if family == 'identity' else 'ext_host_owned_test.s'
            built = modules['metadata'].link(work, {'fixture.s': (root / 'tests' / name).read_text()},
                                             windows=windows)
        relative = executable_name(case, windows)
        target = folder / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(built, target)
        manifest['cases'].append(dict(id=case['id'], executable=relative,
                                      negative=case['mutation'] is not None, sha256=digest(target)))
        print('built', case['id'], flush=True)
    encoded = json.dumps(manifest, indent=2).encode('utf-8') + b'\n'
    if len(encoded) > MANIFEST_LIMIT:
        raise ValueError('generated manifest exceeds bound')
    temporary = folder / 'manifest.pending'
    temporary.write_bytes(encoded)
    temporary.replace(folder / 'manifest.json')


def load_all(folder, windows):
    with (folder / 'manifest.json').open('rb') as stream:
        encoded = stream.read(MANIFEST_LIMIT + 1)
    if len(encoded) > MANIFEST_LIMIT:
        raise ValueError('manifest exceeds bound')
    manifest = json.loads(encoded)
    if (type(manifest) is not dict or set(manifest) != {'version', 'platform', 'cases'}
            or type(manifest['version']) is not int or manifest['version'] != 1
            or manifest['platform'] != ('windows' if windows else 'posix')
            or type(manifest['cases']) is not list):
        raise ValueError('invalid manifest header')
    expected = matrix(windows)
    if len(manifest['cases']) != len(expected):
        raise ValueError('manifest omits or adds matrix cases')
    result = []
    for case, row in zip(expected, manifest['cases']):
        if (type(row) is not dict or set(row) != {'id', 'executable', 'negative', 'sha256'}
                or row['id'] != case['id'] or row['executable'] != executable_name(case, windows)
                or type(row['negative']) is not bool
                or row['negative'] != (case['mutation'] is not None)
                or type(row['sha256']) is not str or not re.fullmatch('[0-9a-f]{64}', row['sha256'])):
            raise ValueError(('invalid matrix row', case['id']))
        executable = (folder / row['executable']).resolve()
        if not executable.is_relative_to(folder) or not executable.is_file():
            raise ValueError(('missing or escaped matrix executable', case['id']))
        if digest(executable) != row['sha256']:
            raise ValueError(('matrix executable digest mismatch', case['id']))
        result.append((case, executable, row['sha256']))
    return result


def check_result(case, code, output, errors, wine):
    negative = case['mutation'] is not None
    expected_exit = code != 0 if negative else code == 0
    known_error = (bool(wine) and case['id'] in ('borrow-metadata/provider', 'borrow-metadata/icon')
                   and negative and code == -5 and errors == ROSETTA_ERROR)
    if not expected_exit or output or (errors and not known_error):
        raise AssertionError((case['id'], code, output, errors))
    return known_error


def run_all(folder, windows, wine, drive, exchange):
    # Validate every binary and manifest row before launching any fixture.
    rows = load_all(folder, windows)
    with tempfile.TemporaryDirectory(prefix='rhun-metadata-matrix-', dir=drive) as temporary:
        base = Path(temporary).resolve()
        def native(path):
            resolved = path.resolve()
            return 'C:/' + resolved.relative_to(drive).as_posix() if wine else str(resolved)
        for case, source, checksum in rows:
            executable = source
            if wine:
                executable = base / 'executables' / executable_name(case, True)
                executable.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, executable)
                if digest(executable) != checksum:
                    raise ValueError(('copied executable digest mismatch', case['id']))
            work = base / 'work' / case['id']
            work.mkdir(parents=True)
            arguments = []
            if case['family'] == 'setup':
                store = work / 'store'
                payload = store / 'owner/name'
                payload.mkdir(parents=True)
                (store / '.change.lock').touch()
                lease = store / '.leases/legacy' / b'owner'.hex() / (b'name'.hex() + '.lock')
                lease.parent.mkdir(parents=True)
                lease.touch()
                state = work / 'state'
                state.mkdir()
                home = work / 'home'
                home.mkdir()
                (home / 'approved').write_bytes(b'keeper')
                arguments = [native(path) for path in (store, payload, state, home)]
            elif case['family'] == 'session':
                arguments = [native(work)]
            command = ([wine] if wine else []) + [native(executable) if wine else str(executable), *arguments]
            with exchange(command, timeout=30, output_bound=0, error_bound=4096) as fixture:
                output, errors = fixture.finish()
                known = check_result(case, fixture.process.returncode, output, errors, wine)
            print('ok', case['id'], '(expected invalid-pointer signal)' if known else '', flush=True)
    print('ok complete metadata matrix:', len(rows), 'cases', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--windows-build', action='store_true')
    parser.add_argument('--build-only', type=Path, help='build the complete Windows PE artifact, without execution')
    parser.add_argument('--prebuilt', type=Path, help='execute a complete previously built manifest')
    parser.add_argument('--wine')
    parser.add_argument('--wine-drive-root', type=Path)
    args = parser.parse_args()
    if args.build_only and (args.prebuilt or args.wine or args.wine_drive_root):
        parser.error('--build-only cannot be combined with execution inputs')
    if args.wine and (not args.prebuilt or not args.wine_drive_root):
        parser.error('--wine requires --prebuilt and --wine-drive-root')
    if args.wine_drive_root and not args.wine:
        parser.error('--wine-drive-root requires --wine')
    windows = bool(args.windows_build or args.wine or args.build_only or os.name == 'nt')
    if windows and not args.build_only and not args.wine and os.name != 'nt':
        parser.error('Windows execution requires native Windows or --prebuilt with --wine')
    root = args.source_root.resolve()
    sys.path.insert(0, str(root / 'tests'))
    from fixture_exchange import FixtureExchange
    drive = None
    if args.wine:
        drive = args.wine_drive_root.resolve()
        prefix = Path(os.environ.get('WINEPREFIX', str(Path.home() / '.wine')))
        mapping = prefix / 'dosdevices/c:'
        if not drive.is_dir() or not mapping.is_dir() or mapping.resolve() != drive:
            parser.error('--wine-drive-root must match the initialized Wine C: mapping')
    if args.build_only:
        build_all(root, args.build_only.resolve(), True)
        return
    if args.prebuilt:
        run_all(args.prebuilt.resolve(), windows, args.wine, drive, FixtureExchange)
        return
    with tempfile.TemporaryDirectory(prefix='rhun-metadata-build-') as temporary:
        folder = Path(temporary).resolve()
        build_all(root, folder, windows)
        run_all(folder, windows, None, None, FixtureExchange)


if __name__ == '__main__':
    main()
