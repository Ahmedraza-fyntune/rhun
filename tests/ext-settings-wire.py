#!/usr/bin/env python3
"""Check exact settings worker headers and counted field decoding."""
import argparse
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 1048576
CAP = LIMIT + 16384
TAG = struct.pack('<QQ', 17, 29) + bytes(range(16))


def header(kind, length, round=1, tag=TAG):
    return b'RHECJOB1' + struct.pack('<II', 1, kind) + tag + struct.pack('<QQ', length, round)


def delta(section=b'owner/a', key=b'setting.x', value=b'yes', remove=0):
    return struct.pack('<IIII', len(section), len(key), len(value), remove) + section + key + value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--wine')
    args = parser.parse_args()
    windows = bool(args.wine) or os.name == 'nt'
    executable = (args.exe or ROOT / ('build/windows/ext_settingswire_test.exe' if windows
                                     else 'build/ext_settingswire_test')).resolve()
    total = 0
    with tempfile.TemporaryDirectory(prefix='rhun-settings-wire-') as temporary:
        path = Path(temporary) / 'frame.bin'

        def call(wire, expected):
            nonlocal total
            path.write_bytes(wire)
            command = ([args.wine, 'Z:' + executable.as_posix(), 'Z:' + path.as_posix()]
                       if args.wine else [str(executable), str(path)])
            result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
            if result.returncode or result.stdout != expected or result.stderr:
                raise AssertionError((total, result.returncode, result.stdout[:200], result.stderr[:1000], expected[:200]))
            if path.read_bytes() != wire:
                raise AssertionError('fixture mutated its input')
            total += 1

        def checked(kind, length, round, okay=True, frame=None, tag=TAG):
            frame = header(kind, length, round) if frame is None else frame
            status = struct.pack('<qQQQ', 0, kind, length, round) if okay else struct.pack('<qQQQ', -71, 0, 0, 0)
            call(struct.pack('<Q', 1) + tag + frame, status)

        valid = [(1, 56, 0), (2, 48, 0), (2, LIMIT + 48, 3), (3, 24, 1),
                 (4, 48, 2), (5, 0, 1), (6, 80, 3), (6, LIMIT + 80, 1),
                 (7, 0, 0), (7, 0, 3), (8, 32, 0), (8, 32, 3), (9, 0, 1), (10, 32, 3)]
        for kind, length, round in valid:
            checked(kind, length, round)
            call(struct.pack('<Q', 3) + TAG + struct.pack('<QQQ', kind, length, round),
                 header(kind, length, round))
        for kind, length, round in [(0, 0, 0), (11, 0, 0), (1, 55, 0), (1, 56, 1),
                                    (1, CAP + 1, 0), (2, 47, 0), (2, LIMIT + 49, 0),
                                    (3, 23, 1), (3, 24, 0), (4, 47, 1), (4, 48, 0),
                                    (5, 1, 1), (5, 0, 0), (6, 79, 1), (6, LIMIT + 81, 1),
                                    (7, 1, 0), (8, 31, 0), (8, 33, 1), (9, 0, 0),
                                    (10, 32, 0), (10, 31, 1), (8, 32, 4)]:
            checked(kind, length, round, False)
        source = header(5, 0, 1)
        for offset in [0, 7, 8, 11, 16, 23, 24, 31, 32, 47]:
            frame = bytearray(source)
            frame[offset] ^= 0x80
            checked(5, 0, 1, False, bytes(frame))
        for tag in [struct.pack('<QQ', 0, 29) + TAG[16:],
                    struct.pack('<QQ', 17, 1 << 63) + TAG[16:]]:
            checked(5, 0, 1, False, header(5, 0, 1, tag), tag)

        def decoded(body, count, okay=True):
            call(struct.pack('<QQ', 2, count) + body,
                 struct.pack('<qQQQ', 0 if okay else -71, 0, 0, 0))

        decoded(delta(), 1)
        decoded(delta(value=b'', remove=1), 1)
        decoded(delta('雪'.encode(), '鍵'.encode(), '値'.encode()), 1)
        decoded(delta() + delta(key=b'setting.y'), 2)
        decoded(b''.join(delta(key=str(i).encode()) for i in range(128)), 128)
        for body, count in [(b'', 0), (b'', 129), (delta()[:-1], 1), (delta() + b'x', 1),
                            (delta() * 2, 2), (delta(key=b'bad=key'), 1),
                            (delta(value=b'x\ny'), 1), (delta(section=b'\xc0\xaf'), 1),
                            (delta(value=b'\0'), 1), (delta(remove=2), 1),
                            (delta(value=b'ignored', remove=1), 1),
                            (struct.pack('<IIII', 0xffffffff, 1, 0, 0), 1)]:
            decoded(body, count, False)
        generator = random.Random(1800)
        for count in [1, 2, 7, 31]:
            entries = [delta(key=('setting.' + str(i)).encode(),
                             value=bytes(generator.choice(b'abc012 \t') for _ in range(63)))
                       for i in range(count)]
            decoded(b''.join(entries), count)
    print(f'ok   settings worker framing: {total} exact header, correlation and counted field cases', flush=True)


if __name__ == '__main__':
    main()
