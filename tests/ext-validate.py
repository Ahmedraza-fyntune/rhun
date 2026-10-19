#!/usr/bin/env python3
"""Independent package hash vectors, static validation and early-helper no-execution checks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--exe', type=Path, required=True)
parser.add_argument('--helper', type=Path)
parser.add_argument('--wine')
parser.add_argument('--wine-drive-root', type=Path)
parser.add_argument('--resource', action='store_true')
parser.add_argument('--probe', type=Path)
args = parser.parse_args()
exe = str(args.exe.resolve())
helper = str(args.helper.resolve()) if args.helper else None
windows = bool(args.wine) or os.name == 'nt'
mac = sys.platform == 'darwin' and not windows
platform = 'windows-x64' if windows else 'macos-arm64' if mac else 'linux-x86_64'
run_key = 'run.' + platform
runner = [args.wine] if args.wine else []


def native(path):
    if not args.wine:
        return str(path)
    if args.wine_drive_root:
        return 'C:/' + str(Path(path).relative_to(args.wine_drive_root)).replace(os.sep, '/')
    return 'Z:' + str(path)


def invoke(path, owner='owner', name='sample', binary=exe, tree=False, env=None):
    command = [*runner, binary, '--tree', native(path)] if tree else [
        *runner, binary, '--validate-extension', native(path), owner, name]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, timeout=45)
    assert len(result.stdout) <= 80, (command, result.stdout)
    if result.returncode == 0:
        assert re.fullmatch(rb'ok [0-9a-f]{64}\n', result.stdout), (command, result.stdout)
        return result.stdout[3:-1].decode()
    assert re.fullmatch(rb'error [0-9]{1,5}\n', result.stdout), (
        command, result.returncode, result.stdout, result.stderr)
    return None


def digest(folder):
    records = []
    for current, dirs, files in os.walk(folder):
        for name in dirs:
            path = Path(current) / name
            records.append((os.fsencode(str(path.relative_to(folder)).replace(os.sep, '/')), 'd', path))
        for name in files:
            path = Path(current) / name
            records.append((os.fsencode(str(path.relative_to(folder)).replace(os.sep, '/')), 'f', path))
    value = hashlib.sha256(b'rhun-package-v1\0')
    for relative, kind, path in sorted(records):
        value.update(kind.encode() + struct.pack('<I', len(relative)) + relative)
        if kind == 'f':
            st = path.stat()
            value.update(struct.pack('<QI', st.st_size, 0 if windows else st.st_mode & 0o111))
            content = hashlib.sha256()
            with path.open('rb') as source:
                for block in iter(lambda: source.read(65536), b''):
                    content.update(block)
            value.update(content.digest())
    return value.hexdigest()


def manifest(**changes):
    values = dict(owner='owner', name='sample', title='Sample', version='1.0', protocol='1')
    values[run_key] = 'run.exe' if windows else 'run'
    values.update(changes)
    return ''.join(key + ' = ' + value + '\n' for key, value in values.items() if value is not None)


def prepare(folder):
    folder.mkdir(exist_ok=True)
    if windows:
        shutil.copyfile(args.probe.resolve() if args.probe else exe, folder / 'run.exe')
    else:
        (folder / 'run').write_bytes(b'#!/bin/sh\necho executed > marker\n')
        (folder / 'run').chmod(0o755)
    (folder / 'extension.ini').write_text(manifest(), encoding='utf-8')
    return folder


def rejected(folder, body, label, **kwargs):
    (folder / 'extension.ini').write_bytes(body if isinstance(body, bytes) else body.encode())
    assert invoke(folder, **kwargs) is None, label


with tempfile.TemporaryDirectory(prefix='rhun-ext-validate-', dir=args.wine_drive_root) as temporary:
    base = Path(temporary).resolve()
    vector = json.loads((ROOT / 'tests/data/ext-validate-tree-v1.json').read_text())
    folder = base / 'vector'
    folder.mkdir()
    for record in vector['records']:
        path = folder / record['path']
        if record['kind'] == 'd':
            path.mkdir(exist_ok=True)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(bytes.fromhex(record['data_hex']))
            path.chmod(0o600 | record['posix_exec'])
    expected = vector['windows' if windows else 'posix']['sha256']
    encoded = bytes.fromhex(vector['windows' if windows else 'posix']['encoded_hex'])
    assert hashlib.sha256(encoded).hexdigest() == expected
    assert digest(folder) == expected
    assert invoke(folder, tree=True) == expected
    rng = random.Random(0x5248554e)
    for number in range(16):
        path = folder / f'.binary-{number}'
        path.write_bytes(rng.randbytes(number * 991))
        if not windows:
            path.chmod(0o600 | (0o111 if number % 2 else 0))
        assert invoke(folder, tree=True) == digest(folder)
    (folder / 'empty2').mkdir()
    assert invoke(folder, tree=True) == digest(folder)
    print('ok canonical complete-tree golden bytes and independent binary hashes', flush=True)

    valid = prepare(base / 'valid')
    expected = digest(valid)
    assert invoke(valid) == expected
    assert not (valid / 'marker').exists()
    native_run = valid / ('run.exe' if windows else 'run')
    if not windows:
        shutil.copyfile('/bin/sh', native_run)
        native_run.chmod(0o755)
        assert invoke(valid) == digest(valid)
        # Nonzero execute mask alone does not establish X_OK for the owning user.
        native_run.chmod(0o645)
        assert invoke(valid) is None  # managed per-user executable requires committed owner execute
        native_run.chmod(0o755)
    good = manifest()
    for key in ['owner', 'name', 'title', 'version', 'protocol', run_key]:
        rejected(valid, manifest(**{key: None}), 'required ' + key)
    for key, value in [('owner', ''), ('owner', '..'), ('owner', 'other'), ('name', 'other'),
                       ('title', ''), ('title', 'x' * 129), ('version', 'x' * 65),
                       ('protocol', '1x'), ('protocol', '01'), ('protocol', '2')]:
        rejected(valid, manifest(**{key: value}), key + '=' + value)
    for owner in ['', '.', '..', '.leading', 'a/b', 'a\\b', 'a' * 101, 'é', 'a\n']:
        rejected(valid, good, 'argv owner', owner=owner)
    for text in [good + 'owner = owner\n', good + run_key + ' = run\n',
                 good + 'runtime = python3\nrun = script.py\n',
                 good.replace('Sample', 'bad\x00title'), good.replace('Sample', 'bad\x01title'),
                 good.replace('Sample', 'bad\x7ftitle'), good.replace('Sample', 'bad\u0085title'),
                 good.encode().replace(b'Sample', b'bad\xc0\xaftitle')]:
        rejected(valid, text, 'malformed metadata')
    rejected(valid, good + '[needs]\nrun = ' + 'x' * 4096 + '\n', 'needs.run cap')
    rejected(valid, good + '# ' + 'x' * 65536, 'manifest cap')
    settings = [
        'a.type = wat', 'invalid-key.type = int', '.type = int', 'a.type = int\na.type = int',
        'a.type = int\na.min = 9\na.max = 2', 'a.type = int\na.min = -1',
        'a.type = int\na.max = 2147483648', 'a.type = int\na.default = 2x',
        'a.type = int\na.min = 2\na.default = 1', 'a.type = int\na.max = 2\na.default = 3',
        'a.type = bool\na.default = true', 'a.type = choice',
        'a.type = choice\na.options = ', 'a.type = choice\na.options = a a',
        'a.type = choice\na.options = a b\na.default = c',
        'a.type = string\na.min = 0', 'a.type = bool\na.options = a b',
    ]
    for fields in settings:
        rejected(valid, good + '[settings]\n' + fields + '\n', fields)
    for fields in [
        'a.type = int\na.min = 2\na.max = 4\na.default = 00000000000003',
        'a.type = bool\na.default = yes', 'a.type = choice\na.options = a b\na.default = b',
        'a.default = plain text\na.future = ignored', 'a.type = string\na.default = ',
    ]:
        (valid / 'extension.ini').write_text(good + '[settings]\n' + fields + '\n')
        assert invoke(valid) == digest(valid), fields
    print('ok required metadata, identity, UTF8/control, settings and existing loader bounds', flush=True)

    (valid / 'extension.ini').write_text(good)
    for relative in ['', '/bin/sh', '../run', 'directory/../run', './run', 'a//b', 'a\\b', 'C:/run']:
        rejected(valid, manifest(**{run_key: relative}), 'managed run ' + relative)
    rejected(valid, manifest(**{run_key: 'missing'}), 'missing selected run')
    (valid / 'directory').mkdir()
    rejected(valid, manifest(**{run_key: 'directory'}), 'directory selected run')
    if not windows:
        (base / 'alias').symlink_to(valid, target_is_directory=True)
        (valid / 'extension.ini').write_text(good)
        assert invoke(base / 'alias') is None
        (valid / 'link').symlink_to(native_run)
        rejected(valid, manifest(**{run_key: 'link'}), 'linked run')
        (valid / 'link').unlink()
        (valid / 'data-link').symlink_to(native_run)
        (valid / 'extension.ini').write_text(good)
        assert invoke(valid) is None
        (valid / 'data-link').unlink()
        os.mkfifo(valid / 'fifo')
        assert invoke(valid) is None
        (valid / 'fifo').unlink()
    print('ok payload-relative nofollow execution paths and complete-tree special-file rejection', flush=True)

    # Static image rejection is independent of the manifest and tree digest.
    original = native_run.read_bytes()
    for value in [b'', b'garbage', b'\x7fELF', b'MZ', b'#!', b'#!/missing/interpreter\n']:
        native_run.write_bytes(value)
        rejected(valid, good, 'invalid executable bytes')
    if windows:
        pe = bytearray(original)
        offset = struct.unpack_from('<I', pe, 60)[0]
        for mutate in [lambda b: struct.pack_into('<H', b, offset + 4, 0xaa64),
                       lambda b: struct.pack_into('<H', b, offset + 22,
                                                 struct.unpack_from('<H', b, offset + 22)[0] | 0x2000),
                       lambda b: struct.pack_into('<H', b, offset + 92, 10),
                       lambda b: struct.pack_into('<I', b, 60, 0xfffffff0)]:
            changed = bytearray(pe)
            mutate(changed)
            native_run.write_bytes(changed)
            rejected(valid, good, 'unsupported PE image')
    elif mac:
        thin = bytearray(64)
        struct.pack_into('<IIIIIIII', thin, 0, 0xfeedfacf, 0x0100000c, 0, 2, 1, 8, 0, 0)
        for filetype in [1, 6, 8]:
            struct.pack_into('<I', thin, 12, filetype)
            native_run.write_bytes(thin)
            rejected(valid, good, 'MachO object/library')
        struct.pack_into('<I', thin, 12, 2)
        struct.pack_into('<I', thin, 4, 0x01000007)
        native_run.write_bytes(thin)
        rejected(valid, good, 'wrong MachO architecture')
    else:
        image = bytearray(original)
        for mutate in [lambda b: struct.pack_into('<H', b, 18, 183),
                       lambda b: struct.pack_into('<H', b, 16, 1),
                       lambda b: struct.pack_into('<Q', b, 24, 0),
                       lambda b: struct.pack_into('<Q', b, 32, 0xfffffffffffffff0)]:
            changed = bytearray(image)
            mutate(changed)
            native_run.write_bytes(changed)
            rejected(valid, good, 'unsupported ELF image')
    native_run.write_bytes(original)
    print('ok static current-host executable recognition and object/library rejection', flush=True)

    if not windows:
        script = b'#!/bin/sh\necho executed > marker\n'
        native_run.write_bytes(script)
        native_run.chmod(0o755)
        clean_env = dict(os.environ, PATH='/usr/bin:/bin')
        (valid / 'extension.ini').write_text(good)
        assert invoke(valid, env=clean_env) == digest(valid)
        native_run.write_bytes(b'#!/usr/bin/env sh\necho executed > marker\n')
        assert invoke(valid, env=clean_env) == digest(valid)
        for path in ['bin:/usr/bin:/bin', ':/usr/bin:/bin', '/usr/bin:/bin:', '/usr/bin::/bin']:
            assert invoke(valid, env=dict(os.environ, PATH=path)) is None, path
        unset = dict(os.environ)
        unset.pop('PATH', None)
        assert invoke(valid, env=unset) is None
        native_run.write_bytes(b'#!/usr/bin/env does-not-exist-rhun\n')
        assert invoke(valid, env=clean_env) is None
        native_run.write_bytes(b'#!/bin/sh -e -x\n')
        assert invoke(valid) is None
        native_run.write_bytes(b'#!/bin/sh\x00junk\n')
        assert invoke(valid) is None
        runtime_manifest = manifest(**{run_key: None, 'runtime': 'sh', 'run': 'script'})
        (valid / 'script').write_bytes(b'echo executed > marker\n')
        (valid / 'extension.ini').write_text(runtime_manifest)
        assert invoke(valid, env=clean_env) == digest(valid)
        assert invoke(valid, env=unset) == digest(valid)
        wrappers = base / 'runtime-wrappers'
        wrappers.mkdir()
        (wrappers / 'wrapped-sh').write_text('#!/bin/sh\nprintf forbidden > marker\n')
        (wrappers / 'wrapped-sh').chmod(0o755)
        (valid / 'extension.ini').write_text(runtime_manifest.replace('runtime = sh', 'runtime = wrapped-sh'))
        assert invoke(valid, env=dict(os.environ, PATH=str(wrappers) + ':/usr/bin:/bin')) == digest(valid)
        (valid / 'extension.ini').write_text(runtime_manifest)
        assert invoke(valid, env=dict(os.environ, PATH='bin:/usr/bin:/bin')) is None
        rejected(valid, runtime_manifest.replace('runtime = sh', 'runtime = nonexistent-rhun'),
                 'missing runtime', env=clean_env)
        rejected(valid, runtime_manifest.replace('run = script', 'run = /bin/sh'),
                 'external managed script')
        assert not (valid / 'marker').exists()
        if os.open in os.supports_dir_fd and os.mkdir in os.supports_dir_fd:
            long_launch = prepare(base / 'long-launch')
            descriptor = os.open(long_launch, os.O_RDONLY | os.O_DIRECTORY)
            components = ['d' * 200 + str(index) for index in range(19)]
            components.append('script' + 'x' * (4090 - len('/'.join(components).encode()) - 7))
            try:
                for component in components[:-1]:
                    os.mkdir(component, dir_fd=descriptor)
                    child = os.open(component, os.O_RDONLY | os.O_DIRECTORY, dir_fd=descriptor)
                    os.close(descriptor)
                    descriptor = child
                target = os.open(components[-1], os.O_CREAT | os.O_WRONLY, 0o600, dir_fd=descriptor)
                os.write(target, b'echo executed > marker\n')
                os.close(target)
            finally:
                os.close(descriptor)
            relative = '/'.join(components)
            assert len(relative.encode()) <= 4095
            assert len((str(long_launch) + '/' + relative).encode()) > 4095
            rejected(long_launch, manifest(**{run_key: None, 'runtime': 'sh', 'run': relative}),
                     'runtime absolute launch path exceeds supported limit', env=clean_env)
        native_run.write_bytes(script)
    print('ok runtime and shebang availability, PATH lookup and no-execution marker', flush=True)

    if helper:
        early = prepare(base / 'early')
        home = base / 'empty-home'
        home.mkdir()
        env = dict(os.environ, HOME=str(home), RHUN_VALIDATION_MARKER=native(early / 'marker'),
                   XDG_CONFIG_HOME=str(home / 'config'),
                   XDG_STATE_HOME=str(home / 'state'), PATH=os.environ.get('PATH', '/usr/bin:/bin'))
        if windows and args.probe:
            # Prove the execution marker works before relying on its absence through validation.
            subprocess.run([*runner, str(early / 'run.exe')], env=env, capture_output=True, timeout=30)
            assert (early / 'marker').exists()
            (early / 'marker').unlink()
        before = {str(path.relative_to(home)) for path in home.rglob('*')}
        assert invoke(early, binary=helper, env=env) == digest(early)
        assert not (early / 'marker').exists()
        assert {str(path.relative_to(home)) for path in home.rglob('*')} == before
        assert invoke(early, owner='wrong', binary=helper, env=env) is None
        print('ok actual early helper has no execution, state creation or UI startup', flush=True)

    # Fail before allocating or hashing oversized content; sparse storage keeps this quick.
    bounded = base / 'bounded'
    bounded.mkdir()
    with (bounded / 'large').open('wb') as target:
        target.truncate(64 * 1024 * 1024 + 1)
    assert invoke(bounded, tree=True) is None
    (bounded / 'large').unlink()
    current = bounded
    for depth in range(33):
        current = current / 'd'
        current.mkdir()
    assert invoke(bounded, tree=True) is None
    print('ok per-file and depth caps', flush=True)
    if args.resource:
        shutil.rmtree(bounded)
        bounded.mkdir()
        for index in range(4096):
            (bounded / str(index)).touch()
        assert invoke(bounded, tree=True) == digest(bounded)
        (bounded / 'overflow').touch()
        assert invoke(bounded, tree=True) is None
        print('ok exact regular-file count cap and overflow', flush=True)
        (bounded / 'overflow').unlink()
        for index in range(4096):
            (bounded / ('dir-' + str(index))).mkdir()
        assert invoke(bounded, tree=True) == digest(bounded)
        (bounded / 'directory-overflow').mkdir()
        assert invoke(bounded, tree=True) is None
        print('ok exact 8192-entry mixed tree and directory overflow', flush=True)
        shutil.rmtree(bounded)
        bounded.mkdir()
        for name in ['a', 'b']:
            with (bounded / name).open('wb') as target:
                target.truncate(64 * 1024 * 1024)
        assert invoke(bounded, tree=True) == digest(bounded)
        (bounded / 'extra-byte').write_bytes(b'x')
        assert invoke(bounded, tree=True) is None
        print('ok exact 64MiB file/128MiB aggregate and aggregate overflow', flush=True)
        shutil.rmtree(bounded)
        bounded.mkdir()
        if os.open in os.supports_dir_fd and os.mkdir in os.supports_dir_fd:
            # Build beyond macOS pathname limits using descriptor-relative creation.
            entries = []
            descriptor = os.open(bounded, os.O_RDONLY | os.O_DIRECTORY)
            prefix = ''
            try:
                for index in range(16):
                    name = f'd{index:02d}' + 'x' * 125
                    os.mkdir(name, dir_fd=descriptor)
                    child = os.open(name, os.O_RDONLY | os.O_DIRECTORY, dir_fd=descriptor)
                    os.close(descriptor)
                    descriptor = child
                    prefix = prefix + '/' + name if prefix else name
                    entries.append((prefix.encode(), b'd'))
                for index in range(4000):
                    name = f'f{index:04d}'
                    handle = os.open(name, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600, dir_fd=descriptor)
                    os.close(handle)
                    entries.append(((prefix + '/' + name).encode(), b'f'))
                value = hashlib.sha256(b'rhun-package-v1\0')
                for relative, kind in sorted(entries):
                    value.update(kind + struct.pack('<I', len(relative)) + relative)
                    if kind == b'f':
                        value.update(struct.pack('<QI', 0, 0) + hashlib.sha256(b'').digest())
                assert sum(len(path) for path, _ in entries) < 8 * 1024 * 1024
                assert invoke(bounded, tree=True) == value.hexdigest()
                for index in range(4000, 4096):
                    handle = os.open(f'f{index:04d}', os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600, dir_fd=descriptor)
                    os.close(handle)
                assert invoke(bounded, tree=True) is None
            finally:
                os.close(descriptor)
            print('ok independent deep path identity and aggregate 8MiB path cap', flush=True)

