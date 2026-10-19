#!/usr/bin/env python3
"""Native read/EOF/allocation/partial-scan failure propagation and heap-free rooted access."""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--wine')
parser.add_argument('--wine-drive-root', type=Path)
parser.add_argument('--validator-exe', type=Path)
parser.add_argument('--root-exe', type=Path)
args = parser.parse_args()
windows = bool(args.wine) or os.name == 'nt'
runner = [args.wine] if args.wine else []


def native(path):
    if args.wine:
        return 'C:/' + str(Path(path).relative_to(args.wine_drive_root))
    return str(path)


with tempfile.TemporaryDirectory(prefix='rhun-ev-fault-', dir=args.wine_drive_root) as temporary:
    root = Path(temporary).resolve()
    if args.validator_exe:
        validator, rooted = args.validator_exe.resolve(), args.root_exe.resolve()
    else:
        spec = importlib.util.spec_from_file_location('ev_build', ROOT / 'tests/faults/ext_validate_build.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        validator = builder.build(root / 'validator', windows)
        rooted = builder.build(root / 'rooted', windows, True)
    payload = root / 'payload'
    payload.mkdir()
    program = 'run.exe' if windows else 'run'
    if windows:
        (payload / program).write_bytes(validator.read_bytes())
    else:
        (payload / program).write_bytes(b'#!/bin/sh\nexit 0\n')
        (payload / program).chmod(0o755)
    target = 'windows-x64' if windows else 'macos-arm64' if os.uname().sysname == 'Darwin' else 'linux-x86_64'
    (payload / 'extension.ini').write_text('owner=owner\nname=sample\ntitle=Sample\nversion=1\nprotocol=1\nrun.' + target + '=' + program + '\n')
    for number in range(4):
        (payload / ('.data-' + str(number))).write_bytes(b'x' * (70000 + number))

    def validate(env):
        result = subprocess.run([*runner, str(validator), '--validate-extension', native(payload), 'owner', 'sample'],
                                env=dict(os.environ, **env), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        assert len(result.stdout) <= 80
        if result.returncode == 0:
            assert re.fullmatch(rb'ok [0-9a-f]{64}\n', result.stdout), result.stdout
            return True
        assert re.fullmatch(rb'error [0-9]+\n', result.stdout), (result.returncode, result.stdout, result.stderr)
        return False

    assert validate({})
    # Cover manifest reads, image/interpreter reads, data reads, EOF probes, and completed scan failure.
    failures = 0
    for number in range(1, 25):
        if not validate({'RHUN_EV_READ_N': str(number)}):
            failures += 1
    assert failures >= 12, failures
    assert not validate({'RHUN_EV_READ_N': '1', 'RHUN_EV_ZERO': '1'})
    assert not validate({'RHUN_EV_SCAN_FAIL': '1'})
    for number in range(1, 6):
        assert not validate({'RHUN_EV_ALLOC_N': str(number)}), number
    print('ok validator native IO, early EOF, allocation and scan failure propagation', flush=True)
    for name in [program, '--self', '--scan']:
        result = subprocess.run([*runner, str(rooted), native(payload), name],
                                env=dict(os.environ, RHUN_EV_ALLOC_N='1'), stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=30)
        assert result.returncode == 0 and len(result.stdout) == 96
        assert struct.unpack_from('<q', result.stdout)[0] == 0, (name, result.stdout, result.stderr)
    print('ok rooted child open/read/stat/identity/close/reopen without allocation', flush=True)

    # A failed close is never flattened into a missing child or lost during ancestor unwind.
    root_stats = len(payload.relative_to(args.wine_drive_root).parts) + 1 if args.wine else len(payload.parts) - 1
    root_closes = root_stats - 1 if windows else root_stats
    for name in [program, '--self']:
        for fail_close in [False, True]:
            env = dict(os.environ, RHUN_EV_STAT_N=str(root_stats + 1))
            if fail_close:
                env['RHUN_EV_CLOSE_N'] = str(root_closes + 1)
            result = subprocess.run([*runner, str(rooted), native(payload), name], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
            assert result.returncode == 0 and len(result.stdout) == 96
            primary = struct.unpack_from('<q', result.stdout)[0]
            cleanup = struct.unpack_from('<q', result.stdout, 32)[0]
            assert (primary, cleanup) == (-2, -5 if fail_close else 0), (name, primary, cleanup, root_stats)
    for fields, expected in [({'RHUN_EV_STAT_N': '1', 'RHUN_EV_CLOSE_N': '1'}, (-2, -5)),
                             ({'RHUN_EV_CLOSE_N': '1'}, (-5, -5))]:
        result = subprocess.run([*runner, str(rooted), native(payload), program],
                                env=dict(os.environ, **fields), stdout=subprocess.PIPE, timeout=30)
        assert (struct.unpack_from('<q', result.stdout)[0], struct.unpack_from('<q', result.stdout, 32)[0]) == expected
    print('ok rooted classification+close, reopen+close and ancestor cleanup double faults', flush=True)
