#!/usr/bin/env python3
"""Rooted complete-or-error managed selection snapshots."""
import argparse
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def index(generation, active=None, previous=None):
    return struct.pack('<8sIIQII', b'RHEXIDX\0', 1, 1 if active else 2, generation, 0, 0) + (
        active or b'\0'*64) + (previous or b'\0'*64)


def encoded(value):
    return value.encode('ascii').hex()


def identity(root, owner='Foo', name='CON.'):
    path = root / '.installed' / encoded(owner) / encoded(name)
    path.mkdir(parents=True, exist_ok=True)
    return path


class Fixture:
    def __init__(self, executable, wine=None, drive=None):
        self.command = ([wine] if wine else []) + [str(executable.resolve())]
        self.wine, self.drive = wine, drive.resolve() if drive else None

    def owned_cli(self, root):
        executable = Path(self.command[-1]).with_name(Path(self.command[-1]).name.replace('_read_', '_cli_'))
        argument = str(root.resolve())
        if self.wine:
            argument = 'C:/' + root.resolve().relative_to(self.drive).as_posix()
        result = subprocess.run([*self.command[:-1], str(executable), '--emit-owned-root', argument], capture_output=True, timeout=30)
        assert result.returncode == 0 and not result.stderr and len(result.stdout) == 128, result
        assert result.stdout[:8] == b'RHESTOR\0' and struct.unpack_from('<QQ', result.stdout, 48) == (7,9)
        assert result.stdout[64:80] == bytes(range(16))

    def lookup(self, root, owner, name, expected, match_status):
        executable = Path(self.command[-1]).with_name(Path(self.command[-1]).name.replace('_read_', '_lookup_'))
        argument = str(root.resolve())
        if self.wine:
            argument = 'C:/' + root.resolve().relative_to(self.drive).as_posix()
        result = subprocess.run([*self.command[:-1], str(executable), argument, owner, name],
                                capture_output=True, timeout=30)
        assert result.returncode == 0 and not result.stderr and len(result.stdout) == 64, result
        words = struct.unpack('<8q', result.stdout)
        triple = (0, expected, 0) if expected else (1, 0, 0)
        assert words[:3] == triple and words[3:6] == triple and words[6:] == (match_status, 0), words

    def run(self, root, expected=0, cancel=0, repeat=1):
        argument = str(root.resolve())
        if self.wine:
            argument = 'C:/' + root.resolve().relative_to(self.drive).as_posix()
        options = {}
        if os.name == 'posix' and not self.wine:
            import resource
            options['preexec_fn'] = lambda: resource.setrlimit(resource.RLIMIT_NOFILE, (32, 32))
        result = subprocess.run([*self.command, argument, str(cancel), str(repeat)],
                                capture_output=True, timeout=60, **options)
        assert result.returncode == 0 and result.stderr == b'', (result.returncode, result.stdout[:100], result.stderr)
        assert len(result.stdout) >= 24, result.stdout
        status, secondary, length = struct.unpack_from('<qqQ', result.stdout)
        allowed = expected if isinstance(expected, tuple) else (expected,)
        assert status in allowed and secondary == 0 and len(result.stdout) == 24+length, (status, secondary, length, expected)
        if status:
            assert length == 0, (status, length)
            return [], []
        wire = result.stdout[24:]
        assert wire[:8] == b'RHESTOR\0' and len(wire) >= 128
        entries, owners, live, reserved = struct.unpack_from('<IIII', wire, 16)
        assert reserved == 0 and entries <= 4096 and owners <= 4096 and live <= 128
        assert struct.unpack_from('<Q', wire, 32)[0] == entries
        assert len(wire) == 128+entries*392+owners*112
        rows = []
        for offset in range(128, 128+entries*392, 392):
            owner = wire[offset:offset+104].split(b'\0')[0].decode('ascii')
            name = wire[offset+104:offset+208].split(b'\0')[0].decode('ascii')
            generation, error, count = struct.unpack_from('<QqQ', wire, offset+208)
            record = wire[offset+232:offset+392]
            rows.append((owner, name, generation, error, count, record))
        assert [(r[0], r[1]) for r in rows] == sorted((r[0], r[1]) for r in rows)
        summaries = []
        for offset in range(128+entries*392, len(wire), 112):
            summaries.append((wire[offset:offset+104].split(b'\0')[0].decode('ascii'),
                              struct.unpack_from('<Q', wire, offset+104)[0]))
        return rows, summaries


def checks(fixture, folder):
    root = folder / 'store'
    root.mkdir()
    assert fixture.run(root, repeat=32) == ([], [])
    (root / '.change.lock').touch()
    fixture.lookup(root, 'Foo', 'missing', 0, 0)
    fixture.owned_cli(root)
    first = identity(root)
    old = index(1, b'a'*64)
    current = index(2, b'b'*64, b'a'*64)
    (first / '0000000000000001.idx').write_bytes(old)
    (first / '0000000000000002.idx').write_bytes(current)
    (first / '.pending-unselected').write_bytes(index(99, b'c'*64))
    rows, _ = fixture.run(root, repeat=32)
    assert len(rows) == 1 and rows[0][2:] == (2, 0, 3, current), rows
    other = identity(root, 'foo', 'NUL.')
    (other / '0000000000000001.idx').write_bytes(index(1))
    empty = identity(root, 'Foo', 'empty')
    (empty / '.pending').write_bytes(b'')
    rows, summaries = fixture.run(root, repeat=32)
    assert [(r[0], r[1], r[2], r[3]) for r in rows] == [
        ('Foo', 'CON.', 2, 0), ('Foo', 'empty', 0, 0), ('foo', 'NUL.', 1, 0)], rows
    assert summaries == [('Foo', 2), ('foo', 1)], summaries
    for corrupt in (b'', current[:-1], current+b'x', b'x'*160):
        (first / '0000000000000002.idx').write_bytes(corrupt)
        rows, _ = fixture.run(root, repeat=32)
        row = rows[0]
        assert row[2] == 2 and row[3] == -5 and row[5] == b'\0'*160, row
    (first / '0000000000000002.idx').write_bytes(current)
    high = index((1 << 64)-1)
    (first / 'ffffffffffffffff.idx').write_bytes(high)
    rows, _ = fixture.run(root)
    assert rows[0][2] == (1 << 64)-1 and rows[0][5] == high
    (first / 'ffffffffffffffff.idx').unlink()
    fixture.lookup(root, 'Foo', 'CON.', 0, 0)
    fixture.lookup(root, 'Foo', 'missing', 0, 0)
    print('ok ext-store/read/current-previous-tombstone-corrupt-highest', flush=True)
    fixture.run(root, expected=-125, cancel=1, repeat=32)
    fixture.run(root, expected=-125, cancel=8, repeat=32)
    print('ok ext-store/read/sticky-cancel-and-retry', flush=True)
    if os.name == 'posix' and not fixture.wine:
        target = folder / 'outside'
        target.mkdir()
        link = identity(root, 'Foo', 'linked')
        link.rmdir()
        link.symlink_to(target, target_is_directory=True)
        rows, _ = fixture.run(root, repeat=32)
        row = next(row for row in rows if row[1] == 'linked')
        assert row[3] in (-20, -40) and row[2] == 0 and row[5] == b'\0'*160, row
        link.unlink()
        (first / '0000000000000002.idx').unlink()
        (first / '0000000000000002.idx').symlink_to(target / 'record')
        rows, _ = fixture.run(root, repeat=32)
        assert rows[0][3] in (-20, -40) and rows[0][2] == 2, rows[0]
        (first / '0000000000000002.idx').unlink()
        (first / '0000000000000002.idx').write_bytes(current)
        owner = root / '.installed' / encoded('badowner')
        owner.symlink_to(target, target_is_directory=True)
        fixture.run(root, expected=(-20, -40), repeat=32)
        owner.unlink()
        installed = root / '.installed'
        installed.rename(root / '.saved')
        installed.symlink_to(target, target_is_directory=True)
        fixture.run(root, expected=(-20, -40), repeat=32)
        installed.unlink()
        (root / '.saved').rename(installed)
        print('ok ext-store/read/static-linked-ancestors-and-leaf', flush=True)
    for parent, count in ((root / '.installed', 0), (root / '.installed' / encoded('Foo'), 0), (empty, 1)):
        present = len(list(parent.iterdir()))
        paths = [parent / ('.flood-' + str(i)) for i in range(4096-present)]
        for path in paths:
            path.write_bytes(b'')
        rows, _ = fixture.run(root)
        if parent == empty:
            row = next(row for row in rows if row[1] == 'empty')
            assert row[4] == 4096 and row[3] == 0
        extra = parent / '.overflow'
        extra.write_bytes(b'')
        if parent == empty:
            rows, _ = fixture.run(root)
            row = next(row for row in rows if row[1] == 'empty')
            assert row[3] == -27 and row[4] == 4097 and row[5] == b'\0'*160, row
        else:
            fixture.run(root, expected=-27)
        extra.unlink()
        for path in paths:
            path.unlink()
    print('ok ext-store/read/hidden-flood-cap-all-levels', flush=True)
    root2 = folder / 'many'
    root2.mkdir()
    for i in range(4096):
        identity(root2, 'owner'+str(i).zfill(4), 'name')
    rows, summaries = fixture.run(root2)
    assert len(rows) == len(summaries) == 4096
    identity(root2, 'extra', 'name')
    fixture.run(root2, expected=-27)
    print('ok ext-store/read/owner-and-total-identity-cap', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--wine')
    parser.add_argument('--wine-drive-root', type=Path)
    args = parser.parse_args()
    windows = bool(args.wine) or os.name == 'nt'
    executable = args.exe or ROOT / ('build/windows/ext_store_read_test.exe' if windows else 'build/ext_store_read_test')
    if args.wine:
        assert args.wine_drive_root
    with tempfile.TemporaryDirectory(prefix='rhun-ext-store-read-', dir=args.wine_drive_root) as directory:
        checks(Fixture(executable, args.wine, args.wine_drive_root), Path(directory).resolve())


if __name__ == '__main__':
    main()
