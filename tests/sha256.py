#!/usr/bin/env python3
"""Compare the native streaming package hash with hashlib on independent binary inputs."""
import argparse
import hashlib
import os
from pathlib import Path
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--exe', type=Path)
parser.add_argument('--wine')
args = parser.parse_args()
exe = args.exe or ROOT / ('build/windows/sha256_test.exe' if os.name == 'nt'
                         else 'build/sha256_test')
exe = exe.resolve()
runner = [args.wine] if args.wine else []


def call(*values):
    return subprocess.run([*runner, str(exe), *map(str, values)],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)


def native_path(path):
    return 'Z:' + str(path) if args.wine else str(path)


result = call()
assert result.returncode == 0, (result.returncode, result.stdout)
assert result.stdout == (ROOT / 'tests/data/sha256.expected').read_bytes(), result.stdout
print('ok sha256/native known answers, streaming splits and rejection invariants', flush=True)

rng = random.Random(0x5248554e)
boundaries = [0, 1, 2, 3, 7, 31, 32, 54, 55, 56, 57, 62, 63, 64, 65, 66,
              111, 118, 119, 120, 121, 126, 127, 128, 129, 255, 256, 257,
              4095, 4096, 4097, 65535, 65536, 65537, 1048576, 2097152]
chunks = [1, 3, 7, 55, 56, 63, 64, 65, 127, 4096, 2097152]
cases = [(length, chunks[i % len(chunks)]) for i, length in enumerate(boundaries)]
cases += [(length, length + 1) for length in [55, 56, 63, 64, 65, 119, 120, 127, 128, 129]]
cases += [(rng.randrange(131073), rng.randrange(1, 8193)) for _ in range(24)]
with tempfile.TemporaryDirectory(prefix='rhun-sha256-') as temporary:
    path = Path(temporary) / 'binary input.dat'
    for number, (length, chunk) in enumerate(cases):
        data = rng.randbytes(length)
        path.write_bytes(data)
        result = call(native_path(path), chunk)
        assert result.returncode == 0, (number, length, chunk, result.returncode, result.stdout)
        expected = hashlib.sha256(data).hexdigest().encode() + b'\n'
        assert result.stdout == expected, (number, length, chunk, expected, result.stdout)
    print(f'ok sha256/{len(cases)} independent binary and padding-boundary cases', flush=True)
    for chunk in ['0', '-1', '1x', '2097153', '999999999999999999999999999999999']:
        result = call(native_path(path), chunk)
        assert result.returncode != 0, (chunk, result.stdout)
    path.write_bytes(b'x' * 2097153)
    result = call(native_path(path), 64)
    assert result.returncode != 0, result.stdout
    print('ok sha256/test-driver input bounds', flush=True)
