#!/usr/bin/env python3
"""Exact anchored receipt acceptance and early helper identity binding."""
import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe', type=Path, required=True)
p.add_argument('--helper', type=Path)
p.add_argument('--wine')
p.add_argument('--wine-drive-root', type=Path)
a = p.parse_args()
runner = [a.wine] if a.wine else []

def native(path):
    return 'C:/' + str(path.relative_to(a.wine_drive_root)).replace(os.sep, '/') if a.wine else str(path)

with tempfile.TemporaryDirectory(prefix='rhun-validator-wire-', dir=a.wine_drive_root) as temporary:
    top = Path(temporary).resolve()
    fixture = top / 'wire'
    tag = bytes(range(64))
    tree, source = bytes(range(32)), bytes(range(32, 64))
    valid = b'RHEVAL1\0' + struct.pack('<II', 1, 192) + tag + tree + source + bytes(48)
    assert len(valid) == 192
    def check(wire=valid, length=192, expected_tag=tag, expected_tree=tree, expected_source=source,
              status=0, secondary=0):
        fixture.write_bytes(struct.pack('<Q', length) + wire + expected_tag + expected_tree + expected_source)
        result = subprocess.run([*runner, str(a.exe.resolve()), native(fixture)], capture_output=True, timeout=15)
        assert result.returncode == 0 and len(result.stdout) == 80 and not result.stderr, result
        assert struct.unpack('<2q', result.stdout[:16]) == (status, secondary), result.stdout.hex()
        assert result.stdout[16:] == (tree + source if status == 0 else b'\x55' * 64), result.stdout.hex()
    check()
    for length in [0, 1, 191, 193, 2**64 - 1]:
        check(length=length, status=-1008)
    for offset in [0, 7, 8, 12, 16, 79, 80, 111, 112, 143, 160, 191]:
        changed = bytearray(valid)
        changed[offset] ^= 1
        check(bytes(changed), status=-1008)
    for primary, secondary, expected in [(-12, 0, -12), (0, -5, -5), (-1008, -5, -1008)]:
        failed = valid[:80] + bytes(64) + struct.pack('<2q', primary, secondary) + bytes(32)
        check(failed, status=expected, secondary=secondary)
    for primary, secondary in [(1, 0), (0, 1), (-4096, 0), (0, -4096)]:
        failed = valid[:80] + bytes(64) + struct.pack('<2q', primary, secondary) + bytes(32)
        check(failed, status=-1008)
    failed = valid[:144] + struct.pack('<2q', -5, 0) + bytes(32)
    check(failed, status=-1008)
    print('ok exact receipt framing, tags, source/tree binding, errors and untouched outputs', flush=True)
    if a.helper and not a.wine and os.name != 'nt':
        folder = top / 'payload'
        folder.mkdir()
        platform = 'macos-arm64' if sys.platform == 'darwin' else 'linux-x86_64'
        (folder / 'extension.ini').write_text('owner = fixture\nname = example\ntitle = Test\nversion = 1\nprotocol = 1\nrun.' + platform + ' = run\n')
        (folder / 'run').write_text('#!/bin/sh\nprintf forbidden > marker\n')
        (folder / 'run').chmod(0o755)
        fd = os.open(folder, os.O_RDONLY | os.O_DIRECTORY)
        try:
            nonce = '0123456789abcdef' * 2
            command = [str(a.helper.resolve()), '--validate-extension-anchored', str(fd), str(folder),
                       'fixture', 'example', '1', '2', nonce, '-']
            def invoke(command=command):
                value = subprocess.run(command, pass_fds=(fd,), capture_output=True, timeout=30)
                assert len(value.stdout) == 192 and not value.stderr, value
                assert value.stdout[:16] == valid[:16], value.stdout.hex()
                assert value.stdout[160:] == bytes(32), value.stdout.hex()
                return value
            result = invoke()
            assert result.returncode == 0 and result.stdout[144:160] == bytes(16), result
            st = os.fstat(fd)
            expected_tag = struct.pack('<QQ', 1, 2) + bytes.fromhex(nonce) + struct.pack('<QQ', st.st_dev, st.st_ino) + bytes(16)
            assert result.stdout[16:80] == expected_tag, result.stdout.hex()
            final = command[:-1] + [result.stdout[112:144].hex()]
            assert invoke(final).returncode == 0
            standalone = subprocess.run([str(a.helper.resolve()), '--validate-extension', str(folder),
                                         'fixture', 'example', result.stdout[112:144].hex()], capture_output=True, timeout=30)
            assert standalone.returncode == 0 and standalone.stdout == b'ok ' + result.stdout[80:112].hex().encode() + b'\n', standalone
            uppercase = subprocess.run([str(a.helper.resolve()), '--validate-extension', str(folder),
                                        'fixture', 'example', 'AB' * 32], capture_output=True, timeout=30)
            assert uppercase.returncode == 1 and uppercase.stdout == b'error 1010\n' and not uppercase.stderr, uppercase
            assert invoke(command[:-1] + ['00' * 32]).returncode == 1
            for index, bad in [(2, '-1'), (2, str(2**64)), (6, '0'), (6, str(2**64)),
                               (7, '1x'), (8, nonce.upper()), (8, nonce[:-1]), (9, '--')]:
                changed = command.copy()
                changed[index] = bad
                assert invoke(changed).returncode == 1
            moved = folder.with_name('old-payload')
            folder.rename(moved)
            shutil.copytree(moved, folder)
            assert invoke().returncode == 1
            assert not (folder / 'marker').exists()
            os.fstat(fd)  # helper consumed only its inherited copy
        finally:
            os.close(fd)
        print('ok early anchored helper, inherited copy ownership, exact source and directory identity')
