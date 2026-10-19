#!/usr/bin/env python3
"""Nonblocking root guards and stable external/package lease ownership."""
import argparse
from pathlib import Path
import os
import queue
import struct
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]


def line(process, expected):
    result = queue.Queue()
    threading.Thread(target=lambda: result.put(process.stdout.readline()), daemon=True).start()
    assert result.get(timeout=20) == expected


class Fixture:
    def __init__(self, executable, wine=None, drive=None):
        self.command = ([wine] if wine else [])+[str(executable.resolve())]
        self.wine, self.drive = wine, drive.resolve() if drive else None

    def args(self, root, exclusive=0, create=0, hold=0, lease=None):
        argument = str(root.resolve())
        if self.wine:
            argument = 'C:/' + root.resolve().relative_to(self.drive).as_posix()
        arguments = [*self.command, argument, str(exclusive), str(create), str(hold)]
        if lease is not None:
            arguments += list(map(str, lease))
        return arguments

    def probe(self, root, expected=0, **kwargs):
        result = subprocess.run(self.args(root, **kwargs), capture_output=True, timeout=30)
        assert result.returncode == 0 and result.stderr == b'' and len(result.stdout) == 16, result
        status, secondary = struct.unpack('<qq', result.stdout)
        allowed = expected if isinstance(expected, tuple) else (expected,)
        assert status in allowed and secondary == 0, (kwargs, status, secondary)

    def hold(self, root, **kwargs):
        process = subprocess.Popen(self.args(root, hold=1, **kwargs), stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            line(process, b'READY\n')
        except BaseException:
            process.kill()
            process.communicate(timeout=20)
            raise
        return process


def finish(process):
    process.stdin.write(b'g')
    process.stdin.flush()
    output, error = process.communicate(timeout=20)
    assert process.returncode == 0 and output == b'RELEASED\n' and error == b'', (process.returncode, output, error)


def checks(fixture, folder):
    root = folder / 'store'
    root.mkdir()
    fixture.probe(root, expected=-2)
    fixture.probe(root, exclusive=0, create=1, expected=-22)
    fixture.probe(root, exclusive=1, create=1)
    assert (root / '.change.lock').is_file()
    for exclusive in (0, 1):
        holder = fixture.hold(root, exclusive=exclusive)
        try:
            fixture.probe(root, exclusive=0, expected=-11 if exclusive else 0)
            fixture.probe(root, exclusive=1, expected=-11)
            finish(holder)
            fixture.probe(root, exclusive=1)
        finally:
            if holder.poll() is None:
                holder.kill()
                holder.communicate(timeout=20)
        holder = fixture.hold(root, exclusive=exclusive)
        holder.kill()
        holder.communicate(timeout=20)
        fixture.probe(root, exclusive=1)
    print('ok ext-store/guard/independent-locks-death-release', flush=True)
    legacy = ('Foo', 'CON.', '-', 0, 1)
    fixture.probe(root, exclusive=1, create=1, lease=legacy)
    leasepath = root / '.leases/legacy' / 'Foo'.encode().hex() / ('CON.'.encode().hex()+'.lock')
    assert leasepath.is_file()
    # Logical case-only/reserved names never alias on disk.
    fixture.probe(root, exclusive=1, lease=('foo', 'NUL.', '-', 0, 1))
    assert (root / '.leases/legacy' / 'foo'.encode().hex() / ('NUL.'.encode().hex()+'.lock')).is_file()
    root2 = root / '.packages' / 'Foo'.encode().hex() / 'CON.'.encode().hex() / ('a'*64)
    root2.mkdir(parents=True)
    (root2 / 'lease').write_bytes(b'')
    for identifier in ('-', 'a'*64):
        for exclusive in (0, 1):
            lease = ('Foo', 'CON.', identifier, exclusive, 0)
            holder = fixture.hold(root, lease=lease)
            try:
                fixture.probe(root, lease=('Foo', 'CON.', identifier, 0, 0), expected=-11 if exclusive else 0)
                fixture.probe(root, lease=('Foo', 'CON.', identifier, 1, 0), expected=-11)
                # Lease outlives root guard: another writer still takes .change.lock.
                fixture.probe(root, exclusive=1)
                finish(holder)
                fixture.probe(root, lease=('Foo', 'CON.', identifier, 1, 0))
            finally:
                if holder.poll() is None:
                    holder.kill()
                    holder.communicate(timeout=20)
    print('ok ext-store/lease/shared-exclusive-independent-root-lifetime', flush=True)
    (root / '.change.lock').chmod(0o444)
    leasepath.chmod(0o444)
    fixture.probe(root, exclusive=1, lease=('Foo', 'CON.', '-', 1, 0))
    fixture.probe(root, lease=('bad/owner', 'name', '-', 0, 0), expected=-22)
    fixture.probe(root, lease=('é', 'name', '-', 0, 0), expected=-22)
    fixture.probe(root, lease=('Foo', 'CON.', 'A'*64, 0, 0), expected=-22)
    fixture.probe(root, lease=('Foo', 'CON.', 'b'*64, 0, 1), expected=-22) # shared guard cannot create
    fixture.probe(root, exclusive=1, lease=('Foo', 'CON.', 'b'*64, 0, 1), expected=-2)
    assert not (root2.parent / ('b'*64)).exists()
    print('ok ext-store/lease/readonly-existing-and-invalid-no-side-effects', flush=True)
    if os.name == 'posix' and not fixture.wine:
        leasepath.chmod(0o600)
        leasepath.unlink()
        target = folder / 'outside'
        target.write_bytes(b'keep')
        leasepath.symlink_to(target)
        fixture.probe(root, lease=('Foo', 'CON.', '-', 0, 0), expected=(-20, -40))
        assert target.read_bytes() == b'keep'
        print('ok ext-store/lease/static-linked-file-rejected', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--wine')
    parser.add_argument('--wine-drive-root', type=Path)
    args = parser.parse_args()
    windows = bool(args.wine) or os.name == 'nt'
    executable = args.exe or ROOT / ('build/windows/ext_store_guard_test.exe' if windows else 'build/ext_store_guard_test')
    if args.wine:
        assert args.wine_drive_root
    with tempfile.TemporaryDirectory(prefix='rhun-ext-store-guard-', dir=args.wine_drive_root) as directory:
        checks(Fixture(executable, args.wine, args.wine_drive_root), Path(directory).resolve())


if __name__ == '__main__':
    main()
