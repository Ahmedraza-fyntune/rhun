#!/usr/bin/env python3
"""Verify confined native handle opens, stable identity, creation and independent scans."""
import argparse
import os
from pathlib import Path
import struct
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--exe', type=Path, required=True)
parser.add_argument('--wine')
parser.add_argument('--wine-drive-root', type=Path)
args = parser.parse_args()
exe = str(args.exe.resolve())
runner = [args.wine] if args.wine else []
windows = bool(args.wine) or os.name == 'nt'


def call(root, name, kind=3, flags=0):
    root = str(root)
    if args.wine:
        root = ('C:/' + str(Path(root).relative_to(args.wine_drive_root)).replace(os.sep, '/')
                if args.wine_drive_root else 'Z:' + root)
    result = subprocess.run([*runner, exe, root, name, str(kind), str(flags)],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert result.returncode == 0, (name, result.returncode, result.stderr)
    assert len(result.stdout) == 96, (name, result.stdout, result.stderr)
    status, kind, size, executable = struct.unpack_from('<qQQQ', result.stdout)
    identity = result.stdout[40:72]
    count = struct.unpack_from('<Q', result.stdout, 88)[0]
    return status, kind, size, executable, identity, result.stdout[72:88], count


with tempfile.TemporaryDirectory(prefix='rhun-ext-root-', dir=args.wine_drive_root) as temporary:
    base = Path(temporary).resolve()
    root = base / 'payload'
    root.mkdir()
    data = b'hello native roots\x00\xff'
    (root / 'file').write_bytes(data)
    (root / 'other').write_bytes(data)
    (root / '.hidden').write_bytes(b'')
    for name in ['file', 'other', '.hidden']:
        status, kind, size, executable, identity, prefix, count = call(root, name, 1)
        assert status == 0 and kind == 1 and size == (len(data) if name != '.hidden' else 0)
        assert identity[16:] == b'\0' * 16
        if not windows:
            st = (root / name).stat()
            assert struct.unpack('<QQ', identity[:16]) == (st.st_dev, st.st_ino)
            assert executable == st.st_mode & 0o111
        else:
            assert executable == 0
        assert count == min(size, 16)
        assert prefix[:count] == (data if name != '.hidden' else b'')[:16]
    assert call(root, 'file')[4] != call(root, 'other')[4]
    assert call(root, 'file', 2)[0] != 0
    assert call(root, 'missing')[0] != 0
    assert call(root, 'new', 1, 7)[0] == 0
    assert call(root, 'new', 1, 7)[0] == -17
    assert call(root, 'directory', 2, 6)[0] == 0
    assert call(root, 'directory', 2, 2)[0] == 0
    assert call(root, 'directory', 2, 6)[0] == -17
    assert call(root, 'directory', 1)[0] != 0
    assert call(root, '--self')[1] == 2
    (root / 'unicode\u0085control').write_bytes(b'existing')
    assert call(root, 'unicode\u0085control')[0] == -22
    (root / 'unicode\u0085control').unlink()
    for name in ['', '.', '..', '../file', 'directory/file', 'a/b', 'line\nfeed']:
        assert call(root, name)[0] != 0, name
    for kind, flags in [(0, 0), (4, 0), (1, 4), (3, 2), (2, 1), (1, 16)]:
        assert call(root, 'file', kind, flags)[0] != 0, (kind, flags)
    if windows:
        for name in ['NUL', 'NUL.txt', 'NUL .txt', 'cOn', 'COM1', 'COM².log',
                     'LPT¹', 'CLOCK$', 'CONIN$', 'CONOUT$.txt', 'file.', 'file ',
                     'a:b', 'a\\b', 'a?b', 'a*b', 'a|b', 'a<b', 'a>b', 'a"b']:
            assert call(root, name)[0] != 0, name
        assert call(root, 'FiLe')[4] == call(root, 'file')[4]
        try:
            if args.wine:
                # Unix host symlinks are transparent in Wine, so create actual NT reparses.
                for link, target, directory in [(base / 'root-alias', root, True),
                                                 (root / 'file-link', root / 'file', False)]:
                    def wine_path(path):
                        return 'C:/' + str(path.relative_to(args.wine_drive_root)).replace(os.sep, '/')
                    command = ['mklink', *(['/D'] if directory else []),
                               wine_path(link), wine_path(target)]
                    result = subprocess.run([args.wine, 'cmd', '/c', *command], capture_output=True)
                    if result.returncode:
                        raise OSError(result.stderr.decode(errors='replace'))
            else:
                (base / 'root-alias').symlink_to(root, target_is_directory=True)
                (root / 'file-link').symlink_to(root / 'file')
        except OSError:
            print('skip native reparse fixture: link creation unavailable', flush=True)
        else:
            assert call(base / 'root-alias', 'file')[0] != 0
            assert call(root, 'file-link')[0] != 0
    elif os.name == 'posix':
        (base / 'alias').symlink_to(root, target_is_directory=True)
        (root / 'dir-link').symlink_to(root / 'directory', target_is_directory=True)
        (root / 'file-link').symlink_to(root / 'file')
        assert call(base / 'alias', 'file')[0] != 0
        assert call(base / 'alias' / 'directory', '--self')[0] != 0
        assert call(root / 'dir-link', '--self')[0] != 0
        assert call(root, 'file-link')[0] != 0
        os.mkfifo(root / 'fifo')
        assert call(root, 'fifo')[0] != 0
    print('ok rooted opens, identity, nofollow ancestors, aliases and exclusive creation', flush=True)
    scan = base / 'scan'
    scan.mkdir()
    for index in range(1500):
        (scan / (str(index) + 'x' * 100)).touch()
    # Nested scans catch dup/DuplicateHandle sharing a cursor after the first native batch.
    value = call(scan, '--scan')
    assert value[0] == 0
    assert value[1:4] == (1500, 1500, 1500), value[:4]
    print('ok rooted independent nested and repeated directory streams', flush=True)
