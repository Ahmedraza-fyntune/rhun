#!/usr/bin/env python3
"""Private candidate allocation and IO failure cleanup at every relevant ordinal."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe', type=Path)
p.add_argument('--capture-mutant', type=Path)
p.add_argument('--role-mutant', type=Path)
p.add_argument('--windows', action='store_true')
p.add_argument('--wine')
p.add_argument('--wine-drive-root', type=Path)
p.add_argument('--probe', type=Path)
a = p.parse_args()
ROOT = Path(__file__).resolve().parent.parent
runner = [a.wine] if a.wine else []
windows = a.windows or bool(a.wine) or os.name == 'nt'
platform = 'windows-x64' if windows else 'macos-arm64' if sys.platform == 'darwin' else 'linux-x86_64'
spec = importlib.util.spec_from_file_location('ev_build', ROOT / 'tests/faults/ext_validate_build.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def native(path):
    return 'C:/' + str(path.relative_to(a.wine_drive_root)).replace(os.sep, '/') if a.wine else str(path)

with tempfile.TemporaryDirectory(prefix='rhun-ep-fault-', dir=a.wine_drive_root) as temporary:
    top = Path(temporary).resolve()
    exe = a.exe.resolve() if a.exe else module.build(top / 'objects', windows, fixture_name='tests/ext_prepare_test.s')
    root = top / 'payload'
    root.mkdir()
    program = 'run.exe' if windows else 'run'
    if windows:
        shutil.copyfile(a.probe or ROOT / 'build/windows/ext_validate_probe_test.exe', root / program)
    else:
        (root / program).write_text('#!/bin/sh\nprintf forbidden > marker\n')
        (root / program).chmod(0o755)
    (root / 'extension.ini').write_text('owner = fixture\nname = example\ntitle = Example\nversion = 1\nprotocol = 1\nrun.' + platform + ' = ' + program + '\n[commands]\na = A | ctrl+a\nb = B\n[settings]\nchoice.type = choice\nchoice.options = a b\nchoice.default = b\ncount.type = int\ncount.min = 1\ncount.max = 5\ncount.default = 3\nflag.type = bool\nflag.default = yes\n')
    (root / 'syntax').mkdir()
    (root / 'syntax' / 'case.syn').write_text('name = Fault\nkeywords = alpha beta gamma\nregion = start end string\n')
    (root / 'themes').mkdir()
    (root / 'themes' / 'case.theme').write_text('name = Fault\nkind = dark\nbg = #123456\n')
    def check(env=None):
        r = subprocess.run([*runner, str(exe), native(root), 'fixture', 'example'], input=b'1',
                           env=dict(os.environ, **(env or {})), capture_output=True, timeout=30)
        assert r.returncode == 0 and len(r.stdout) == 224 and not r.stderr, (env, r)
        first = struct.unpack_from('<2q', r.stdout)
        final = struct.unpack_from('<2q', r.stdout, 128)
        release, live = struct.unpack_from('<2q', r.stdout, 208)
        assert live == 0, (env, first, final, release, live)
        failed = first[0] != 0 or final[0] != 0 or release != 0
        if failed:
            assert r.stdout[144:208] == bytes(64), (env, r.stdout.hex())
        assert not (root / 'marker').exists()
        return failed
    assert not check()
    failures = 0
    clean_tail = 0
    for ordinal in range(1, 513):
        if check({'RHUN_EV_ALLOC_N': str(ordinal)}):
            failures += 1
            clean_tail = 0
        else:
            clean_tail += 1
        if clean_tail == 24:
            break
    assert failures >= 40 and clean_tail == 24, (failures, ordinal)
    print('ok all candidate/second-validation allocation ordinals, no leaked products or side effects', flush=True)
    for key in ['RHUN_EV_READ_N', 'RHUN_EV_STAT_N', 'RHUN_EV_CLOSE_N']:
        failures = 0
        clean_tail = 0
        for ordinal in range(1, 257):
            if check({key: str(ordinal)}):
                failures += 1
                clean_tail = 0
            else:
                clean_tail += 1
            if clean_tail == 8:
                break
        assert failures >= 8 and clean_tail == 8, (key, failures, ordinal)
    assert check({'RHUN_EV_READ_N': '1', 'RHUN_EV_ZERO': '1'})
    assert check({'RHUN_EV_SCAN_FAIL': '1'})
    print('ok read/stat/close ordinals, partial-scan/EOF failures and mandatory cleanup', flush=True)
    assert not check({'RHUN_EP_PARTIAL': '1'})
    assert check({'RHUN_EP_IMAGE_MODE': '4'})  # exact native attempt budget includes EINTR
    if not windows:
        (root / program).write_bytes(b'#!/bin/sh x y\n')
        assert check()
        assert check({'RHUN_EP_IMAGE_MODE': '2'})
        if not a.exe:
            saved = exe
            exe = module.build(top / 'short-read-mutant', windows, fixture_name='tests/ext_prepare_test.s', image_read_bypass=True)
            assert not check({'RHUN_EP_IMAGE_MODE': '2'}), 'short-read guard mutation was not detected'
            exe = saved
    probe = a.probe or ROOT / ('build/windows/ext_validate_probe_test.exe' if windows else 'build/ext_validate_probe_test')
    image = bytearray(probe.read_bytes())
    image[:2 if windows else 4] = bytes(2 if windows else 4)
    (root / program).write_bytes(image)
    assert check()
    assert check({'RHUN_EP_IMAGE_MODE': '1'})
    if a.capture_mutant or not a.exe:
        saved = exe
        exe = a.capture_mutant.resolve() if a.capture_mutant else module.build(top / 'capture-mutant', windows, fixture_name='tests/ext_prepare_test.s', capture_bypass=True)
        assert not check({'RHUN_EP_IMAGE_MODE': '1'}), 'captured-span guard mutation was not detected'
        exe = saved
    shutil.copyfile(probe, root / program)
    assert not check({'RHUN_EP_PARTIAL': '1'})
    assert check({'RHUN_EP_IMAGE_MODE': '3'})
    if not windows:
        for mode in [0o644, 0o645]:
            (root / program).chmod(mode)
            assert check()
        for mode in [0o700, 0o755]:
            (root / program).chmod(mode)
            assert not check()
    if platform == 'linux-x86_64':
        header = bytearray(64)
        header[:7] = b'\x7fELF\x02\x01\x01'
        struct.pack_into('<HHIQQQ', header, 16, 2, 62, 1, 0x400000, 64, 0)
        struct.pack_into('<HHHHHH', header, 52, 64, 56, 1, 0, 0, 0)
        (root / program).write_bytes(header)
        assert check({'RHUN_EP_IMAGE_MODE': '3'})
    print('ok committed executable bytes/size/EOF/permissions, partials, EINTR and guard mutation gates', flush=True)
    (root / 'syntax' / 'case.syn').unlink()
    (root / 'themes' / 'case.theme').unlink()
    shutil.copyfile(probe, root / 'syntax' / 'run.syn')
    if not windows:
        (root / 'syntax' / 'run.syn').chmod(0o755)
    (root / 'extension.ini').write_text('owner = fixture\nname = example\ntitle = Example\nversion = 1\nprotocol = 1\nrun.' + platform + ' = syntax/run.syn\n')
    assert check()
    assert check({'RHUN_EP_HIDE_PLAN': '1'})
    if a.role_mutant or not a.exe:
        saved = exe
        exe = a.role_mutant.resolve() if a.role_mutant else module.build(top / 'role-mutant', windows, fixture_name='tests/ext_prepare_test.s', source_role_bypass=True)
        assert not check({'RHUN_EP_HIDE_PLAN': '1'}), 'asset parser-role guard mutation was not detected'
        exe = saved
    print('ok launch-only source cannot conceal an unparsed asset, parser-role guard mutation detected', flush=True)
