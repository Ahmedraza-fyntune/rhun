#!/usr/bin/env python3
"""Private candidate views, independent source commitments and deterministic binding mutations."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
from fixture_exchange import FixtureExchange

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe', type=Path, required=True)
p.add_argument('--wine')
p.add_argument('--wine-drive-root', type=Path)
p.add_argument('--probe', type=Path)
a = p.parse_args()
windows = bool(a.wine) or os.name == 'nt'
platform = 'windows-x64' if windows else 'macos-arm64' if sys.platform == 'darwin' else 'linux-x86_64'
runner = [a.wine] if a.wine else []

def native(path):
    return 'C:/' + str(path.relative_to(a.wine_drive_root)).replace(os.sep, '/') if a.wine else str(path)

def body(extra=''):
    return ('owner = fixture\nname = example\ntitle = Example\nversion = 1\nprotocol = 1\n'
            'run.' + platform + ' = ' + ('run.exe' if windows else 'run') + '\n' + extra)

def prepare(folder, extra=''):
    folder.mkdir()
    (folder / 'extension.ini').write_text(body(extra))
    program = folder / ('run.exe' if windows else 'run')
    if windows:
        shutil.copyfile(a.probe or a.exe, program)
    else:
        program.write_bytes(b'#!/bin/sh\nprintf forbidden > marker\n')
        program.chmod(0o755)
    (folder / 'syntax').mkdir()
    (folder / 'syntax' / '.hidden.syn').write_text('name = Hidden\nkeywords = a b c\n')
    (folder / 'themes').mkdir()
    (folder / 'themes' / 'sample.theme').write_text('name = Sample\nkind = dark\nbg = #123456\n')
    return folder

def source_commitment(folder):
    program = 'run.exe' if windows else 'run'
    records = [('extension.ini', 1), (program, 2)]
    records += [(str(x.relative_to(folder)).replace(os.sep, '/'), 4) for x in (folder / 'syntax').iterdir() if x.is_file() and x.name.endswith('.syn')]
    records += [(str(x.relative_to(folder)).replace(os.sep, '/'), 8) for x in (folder / 'themes').iterdir() if x.is_file() and x.name.endswith('.theme')]
    value = hashlib.sha256(b'rhun-prepared-sources-v1\0')
    value.update(struct.pack('<I', len(records)))
    for name, roles in sorted(records):
        file = folder / name
        name = name.encode()
        st = file.stat()
        value.update(struct.pack('<I', len(name)) + name)
        value.update(struct.pack('<QI', st.st_size, 0 if windows else st.st_mode & 0o111))
        value.update(hashlib.sha256(file.read_bytes()).digest() + struct.pack('<I', roles))
    resolved = (native(folder) + '/' + program).encode()
    value.update(struct.pack('<I', len(resolved)) + resolved)
    return value.digest()

def run(folder, mutation=None, expected=0, expected_prepare=0, counts=(1, 1, 1, 4)):
    with FixtureExchange([*runner, str(a.exe.resolve()), native(folder), 'fixture', 'example'],
                         timeout=30, output_bound=224) as exchange:
        first = exchange.read(128)
        fields = struct.unpack('<8q', first[:64])
        assert fields[0] == expected_prepare, (folder.name, expected_prepare, fields)
        if expected_prepare == 0:
            assert fields[1] == 0 and fields[2:6] == counts, fields
            assert first[64:96] == source_commitment(folder), (first[64:96].hex(), source_commitment(folder).hex())
            assert 0 < fields[7] <= 64 * 1024 * 1024, fields
            if mutation:
                mutation(folder)
            exchange.send(b'1')
        result, errors = exchange.finish()
        assert exchange.process.returncode == 0 and not errors, (exchange.process.returncode, result, errors)
        assert len(result) == 96, result
        status, secondary = struct.unpack('<2q', result[:16])
        assert status == expected and secondary == 0, (expected, status, secondary)
        assert struct.unpack('<2q', result[80:]) == (0, 0), result.hex()
        if expected or expected_prepare:
            assert result[16:80] == bytes(64), result.hex()
        else:
            assert result[48:80] == first[64:96], result.hex()
    assert not (folder / 'marker').exists()

with tempfile.TemporaryDirectory(prefix='rhun-ext-products-', dir=a.wine_drive_root) as temporary:
    top = Path(temporary).resolve()
    suffix = '[commands]\nhello = Hello | ctrl+h\n[settings]\nb.type = bool\nb.default = yes\n'
    folder = prepare(top / 'valid', suffix)
    run(folder)
    for fixture in ('ext_prepare_lifetime_test', 'ext_prepare_doc_lifetime_test'):
        lifetime = a.exe.resolve().with_name(fixture + ('.exe' if windows else ''))
        if lifetime.exists():
            with FixtureExchange([*runner, str(lifetime), native(folder)], timeout=30,
                                 output_bound=0) as exchange:
                output, errors = exchange.finish()
                assert exchange.process.returncode == 0 and not output and not errors, (
                    lifetime, exchange.process.returncode, output, errors)
    folder = prepare(top / 'suffix-only', suffix)
    (folder / 'syntax' / '.syn').write_text('name = Suffix Grammar\n')
    (folder / 'themes' / '.theme').write_text('name = Suffix Theme\nbg = #123456\n')
    run(folder, counts=(1, 2, 2, 6))
    changes = [
        lambda f: (f / 'extension.ini').write_text(body(suffix.replace('Hello', 'Other'))),
        lambda f: (f / 'syntax' / '.hidden.syn').write_text('name = Hidden\nkeywords = x y z\n'),
        lambda f: (f / 'themes' / 'sample.theme').write_text('name = Sample\nkind = dark\nbg = #654321\n'),
        lambda f: (f / 'syntax' / 'added.syn').write_text('name = Added\n'),
        lambda f: (f / 'themes' / 'added.theme').write_text('name = Added\n'),
        lambda f: (f / 'themes' / 'sample.theme').unlink(),
    ]
    if not windows:
        changes += [lambda f: (f / 'run').write_text('#!/bin/sh\nprintf different > marker\n'),
                    lambda f: (f / 'run').chmod(0o700)]
    for index, change in enumerate(changes):
        run(prepare(top / ('mutate-' + str(index)), suffix), change, -1008)
    for index, (relative, content, error) in enumerate([
        ('syntax/.hidden.syn', 'name = Bad\nunknown = bad\n', -1011),
        ('themes/sample.theme', 'name = Bad\nbg = #12zzzz\n', -1012),
        ('themes/sample.theme', 'name = ' + 'x' * 129 + '\n', -1012),
    ]):
        folder = prepare(top / ('invalid-' + str(index)), suffix)
        (folder / relative).write_text(content)
        run(folder, expected_prepare=error)
    # Case-insensitive filesystems must still reject a managed spelling alias deterministically.
    folder = prepare(top / 'case', suffix)
    (folder / ('run.exe' if windows else 'run')).rename(folder / ('Run.exe' if windows else 'Run'))
    with FixtureExchange([*runner, str(a.exe.resolve()), native(folder), 'fixture', 'example'],
                         timeout=30, output_bound=224) as exchange:
        first = exchange.read(128)
        prepare_status = struct.unpack('<q', first[:8])[0]
        if prepare_status == 0:
            exchange.send(b'1')
        result, errors = exchange.finish()
        assert exchange.process.returncode == 0 and len(result) == 96 and not errors, (
            exchange.process.returncode, first, result, errors)
        final_status = struct.unpack('<q', result[:8])[0]
    assert prepare_status != 0 or final_status == -1008, (prepare_status, final_status)
    # Same content at a substituted directory is not the held anchor.
    folder = prepare(top / 'anchor', suffix)
    def substitute(f):
        moved = f.with_name('old-anchor')
        f.rename(moved)
        shutil.copytree(moved, f)
    run(folder, substitute, -1008)
print('ok private products, independent source commitments, exact spelling and mutation binding')
