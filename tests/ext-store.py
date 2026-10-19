#!/usr/bin/env python3
"""Exact managed identity and bounded relocation-free snapshot wire."""
import argparse
from pathlib import Path
import os
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wine')
    parser.add_argument('--identity-exe', type=Path)
    parser.add_argument('--wire-exe', type=Path)
    args = parser.parse_args()
    windows = bool(args.wine) or os.name == 'nt'
    prefix = [args.wine] if args.wine else []
    out = ROOT / ('build/windows' if windows else 'build')
    suffix = '.exe' if windows else ''
    identity = args.identity_exe or out / ('ext_store_identity_test' + suffix)
    wire = args.wire_exe or out / ('ext_store_wire_test' + suffix)
    result = subprocess.run([*prefix, str(identity.resolve())], capture_output=True, timeout=30)
    assert result.returncode == 0 and result.stdout + result.stderr == (
        ROOT / 'tests/data/ext-store-identity.expected').read_bytes(), result
    print('ok ext-store/identity', flush=True)
    result = subprocess.run([*prefix, str(wire.resolve())], capture_output=True, timeout=30)
    assert result.returncode == 0 and result.stderr == b'', result
    original = result.stdout
    assert len(original) == 128 + 392*4 + 112*2
    assert original[:8] == b'RHESTOR\0'
    assert struct.unpack_from('<IIII', original, 16) == (4, 2, 1, 0)
    keys = [(original[128+i*392:128+i*392+104].split(b'\0')[0],
             original[128+i*392+104:128+i*392+208].split(b'\0')[0]) for i in range(4)]
    assert keys == [(b'Foo', b'CON.'), (b'Foo', b'bad'), (b'foo', b'empty'), (b'foo', b'z')], keys
    cases = [('roundtrip', original, True)]
    for length in (0, 1, 8, 127, 128, len(original)-1):
        cases.append(('truncated-' + str(length), original[:length], False))
    cases.append(('excess', original+b'\0', False))
    for offset in (0, 8, 12, 16, 20, 24, 28, 32, 48, 56, 64, 80, 111, 112, 120):
        changed = bytearray(original)
        changed[offset] ^= 1
        cases.append(('header-' + str(offset), changed, False))
    for offset in (128, 128+4, 128+104, 128+104+5, 128+208, 128+216,
                   128+232, 128+232+32, 128+392+232, 128+392*2+232,
                   128+392*4,):
        changed = bytearray(original)
        changed[offset] ^= 0x7f
        cases.append(('row-' + str(offset), changed, False))
    for offset, value in ((40, 4097), (128+224, 4097), (128+392*4+104, 0)):
        changed = bytearray(original)
        struct.pack_into('<Q', changed, offset, value)
        cases.append(('invalid-native-count-' + str(offset), changed, False))
    # A record count cannot authorize huge allocation before exact framing.
    for offset in (16, 20):
        changed = bytearray(original)
        struct.pack_into('<I', changed, offset, 0xffffffff)
        cases.append(('count-overflow-' + str(offset), changed, False))
    changed = bytearray(original)
    changed[128:128+392] = original[128+392:128+784]
    cases.append(('duplicate', changed, False))
    changed = bytearray(original)
    changed[128:128+392], changed[128+392:128+784] = original[128+392:128+784], original[128:128+392]
    cases.append(('unsorted', changed, False))
    # Exact maximum framing remains below 2MiB and validates in linear time.
    header = bytearray(original[:128])
    struct.pack_into('<IIIIQQ', header, 16, 4096, 4096, 0, 0, 4096, 4096)
    rows, owners = bytearray(), bytearray()
    for number in range(4096):
        owner = ('owner%04d' % number).encode()
        row = bytearray(392)
        row[:len(owner)] = owner
        row[104:108] = b'name'
        struct.pack_into('<QQ', row, 208, 1, 0)
        struct.pack_into('<Q', row, 224, 1)
        row[232:] = struct.pack('<8sIIQII', b'RHEXIDX\0', 1, 2, 1, 0, 0) + bytes(128)
        rows.extend(row)
        summary = bytearray(112)
        summary[:len(owner)] = owner
        struct.pack_into('<Q', summary, 104, 1)
        owners.extend(summary)
    boundary = header + rows + owners
    assert len(boundary) == 2064512
    cases.append(('boundary-4096', boundary, True))
    cases.append(('boundary-4097-excess', boundary + bytes(392), False))
    with tempfile.TemporaryDirectory(prefix='rhun-ext-store-wire-') as directory:
        path = Path(directory) / 'wire'
        for name, data, accepted in cases:
            path.write_bytes(data)
            argument = 'Z:' + str(path) if args.wine else str(path)
            result = subprocess.run([*prefix, str(wire.resolve()), argument], capture_output=True, timeout=30)
            assert result.returncode == 0 and result.stdout + result.stderr == (
                b'ok\n' if accepted else b'rejected\n'), (name, result.returncode, result.stdout, result.stderr)
            print('ok ext-store/wire/' + name, flush=True)


if __name__ == '__main__':
    main()
