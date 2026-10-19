#!/usr/bin/env python3
"""Exercise the actual native INI merger, preservation, bounds and allocation failures."""
import argparse
import importlib.util
import os
from pathlib import Path
import random
import re
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 1048576


def checked(command):
    p = subprocess.run(list(map(str, command)), stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, timeout=120)
    if p.returncode:
        raise AssertionError(p.stdout.decode(errors='replace')[:5000])


def fault_build(platform, runtime, folder):
    spec = importlib.util.spec_from_file_location('task_core_driver', ROOT / 'tests/task-core.py')
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    driver.ROOT = runtime
    if platform == 'windows':
        spec = importlib.util.spec_from_file_location('win_builder', ROOT / 'tools/build-windows.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
    objects = []
    for relative, name in [('src/app/extchoices.s', 'choices'), ('tests/ext_choices_test.s', 'fixture')]:
        text = (ROOT / relative).read_text()
        if name == 'choices':
            assert text.count('call mem_alloc_try') == 1
            text = text.replace('call mem_alloc_try', 'call ect_alloc')
        if platform == 'windows':
            text = re.sub(r'(?m)^\.section \.rodata$', '.section .rdata,"dr"', text)
        source = folder / (name + '.s')
        source.write_text(text)
        obj = folder / (name + ('.obj' if platform == 'windows' else '.o'))
        if platform == 'macos':
            translated = folder / (name + '-arm64.s')
            checked([sys.executable, ROOT / 'tools/arm64.py', '-I', ROOT / 'src', '-D', 'MACOS', source, translated])
            checked(['as', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', obj, translated])
        elif platform == 'windows':
            checked([builder.tool('llvm-mc'), '-triple=x86_64-pc-windows-msvc', '-filetype=obj',
                     '-defsym=WINDOWS=1', '-I', ROOT / 'src', '-I', ROOT / 'src/win', source, '-o', obj])
        else:
            checked(['as', '--64', '-I', ROOT / 'src', '-o', obj, source])
        objects.append(obj)
    excluded = {'src_app_extchoices.o', 'src_app_extchoices.s.obj'}
    objects.extend(o for o in driver.runtime_objects(platform) if o.name not in excluded)
    for source in ('src_app_taskcore', 'src_memtry'):
        objects.append(runtime / ('build/windows/' + source + '.s.obj' if platform == 'windows'
                                  else 'build/obj/' + source + '.o'))
    exe = folder / ('ext-choices.exe' if platform == 'windows' else 'ext-choices')
    if platform == 'macos':
        command = ['clang', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', exe, *objects]
        for framework in ('AppKit', 'QuartzCore', 'IOSurface', 'CoreServices', 'Carbon'):
            command.extend(('-framework', framework))
    elif platform == 'windows':
        libraries = [runtime / 'build/windows' / (s.stem + '.lib') for s in sorted((runtime / 'src/win').glob('*.def'))]
        command = [builder.tool('lld-link'), '/nodefaultlib', '/entry:win_start', '/subsystem:console,6.02',
                   '/stack:33554432,33554432', '/dynamicbase', '/nxcompat', '/largeaddressaware',
                   '/out:' + str(exe), *objects, runtime / 'build/windows/rhun.res', *libraries]
    else:
        command = ['ld', '-static', '-nostdlib', '--no-dynamic-linker', '-z', 'noexecstack', '-o', exe, *objects]
    checked(command)
    return exe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--runtime-root', type=Path, default=ROOT)
    parser.add_argument('--wine')
    parser.add_argument('--faults', action='store_true')
    parser.add_argument('--fault-exe', type=Path)
    args = parser.parse_args()
    platform = 'windows' if args.wine or os.name == 'nt' else 'macos' if sys.platform == 'darwin' else 'linux'
    with tempfile.TemporaryDirectory(prefix='rhun-ext-choices-') as temporary:
        folder = Path(temporary)
        exe = args.exe or ROOT / ('build/windows/ext_choices_test.exe' if platform == 'windows' else 'build/ext_choices_test')
        fault = args.fault_exe or (fault_build(platform, args.runtime_root.resolve(), folder) if args.faults else None)
        total = 0

        def call(snapshot, deltas, expected=None, error=None, count=None, fail=False):
            nonlocal total
            wire = struct.pack('<QQQ', len(snapshot), len(deltas) if count is None else count, int(fail)) + snapshot
            for section, key, value, remove in deltas:
                wire += struct.pack('<QQQQ', len(section), len(key), len(value), remove) + section + key + value
            path = folder / 'request.bin'
            path.write_bytes(wire)
            target = fault if fail else exe
            command = [str(target.resolve()), str(path)]
            if args.wine:
                command = [args.wine, 'Z:' + target.resolve().as_posix(), 'Z:' + path.as_posix()]
            p = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
            assert p.returncode == 0 and len(p.stdout) >= 8, (total, p.returncode, p.stdout[:200], p.stderr[:500])
            status = struct.unpack_from('<q', p.stdout)[0]
            body = p.stdout[8:]
            if error is not None:
                assert status == error and not body, (total, status, error, body[:100])
            else:
                assert status == len(body), (total, status, len(body))
                if expected is not None:
                    assert body == expected, (total, body[:300], expected[:300])
            assert path.read_bytes() == wire
            total += 1
            return body

        change = [(b'owner/tool', b'pinned', b'yes', 0)]
        block = b'[owner/tool]\npinned=yes\n'
        call(b'', change, block)
        source = b'; keep\r\nglobal=ok\r\n[owner/tool]\r\npinned=no\r\nsetting.unknown = untouched\r\n[providers]\ncomplete.py = other/tool\n[removed/tool]\ndisabled=yes\n'
        expected = source.replace(b'[owner/tool]\r\npinned=no\r\n', b'[owner/tool]\r\npinned=yes\n')
        call(source, change, expected)
        call(b'[owner/tool]\npinned=no\n[owner/tool]\npinned=yes\n', change,
             b'[owner/tool]\npinned=yes\n[owner/tool]\n')
        call(b'[Owner/tool]\npinned=no\n', change, b'[Owner/tool]\npinned=no\n' + block)
        call(b'# no final newline', change, b'# no final newline\n' + block)
        call(b'[owner/tool]\npinned=no', [(b'owner/tool', b'pinned', b'', 1)], b'[owner/tool]\n')
        call(b'# retained', [(b'owner/tool', b'missing', b'', 1)], b'# retained')
        call(b'', [(b'owner/tool', b'empty', b'', 0)], b'[owner/tool]\nempty=\n')
        call(b'[]\nunknown=yes\n[[nested]]\nk=v\n[owner/tool]\n[legacy=x\n',
             [(b'owner/tool', b'[legacy', b'y', 0)],
             b'[]\nunknown=yes\n[[nested]]\nk=v\n[owner/tool]\n[legacy=y\n')
        call(b'[owner/tool]\nsetting.a[b=x\n', [(b'owner/tool', b'setting.a[b', b'y', 0)],
             b'[owner/tool]\nsetting.a[b=y\n')
        call(b'\r \t[owner/tool]\r \t\n\t pinned \r = no\n', change,
             b'\r \t[owner/tool]\r \t\npinned=yes\n')
        unicode = '雪'.encode()
        call(b'', [(unicode, unicode, unicode, 0)], b'[' + unicode + b']\n' + unicode + b'=' + unicode + b'\n')
        for bad in (b'bad line', b'[]\n =empty-key', b'[broken', b'k=v\x00', b'k=\x01', b'k=\x7f',
                    b'k=\xc0\xaf', b'k=\xed\xa0\x80', b'k=\xf4\x90\x80\x80', b'k=\xe2\x82'):
            call(bad, change, error=-22)
        for section, key, value in [(b'', b'key', b'x'), (b' x', b'key', b'x'), (b'x', b'key ', b'x'),
                                    (b'x', b'k=e', b'x'), (b'x', b'#key', b'x'), (b'x', b';key', b'x'),
                                    (b'x\ny', b'k', b'x'), (b'x', b'k', b'x\ny'), (b'x', b'k', b'x\ry'),
                                    (b'x', b'k', b'\x00'), (b'x', b'k', b'\xc0\xaf'),
                                    (b'x', b'[legacy', b'x]'), (b'x', b'[legacy', b'x] '),
                                    (b'x', b'[legacy', b'x]\t')]:
            call(b'', [(section, key, value, 0)], error=-22)
        call(b'', change * 2, error=-22)
        call(b'', [(b'x', b'k', b'ignored\n', 2)], error=-22)
        call(b'', [], error=-22)
        call(b'', change, error=-7, count=129)
        long_key = b'setting.' + b'a' * 1500
        long_value = b'v' * 70000
        call(b'', [(b'owner/tool', long_key, long_value, 0)],
             b'[owner/tool]\n' + long_key + b'=' + long_value + b'\n')
        full = b'#' + b'x' * (LIMIT - 1)
        call(full, [(b'x', b'missing', b'', 1)], full)
        call(full + b'x', change, error=-27)
        call(full, change, error=-27)
        call(b'', [(b'x', b'key', b'x' * LIMIT, 0)], error=-27)
        many = [(b'owner/tool', b'key' + str(i).encode(), b'value', 0) for i in range(128)]
        call(b'', many, b'[owner/tool]\n'+b''.join(k + b'=value\n' for _, k, _, _ in many))
        many_lines = b'[owner/tool]\n' + b'unknown=v\n' * 17000
        updated = call(many_lines, change, block + b'unknown=v\n' * 17000)
        call(updated, change, updated)
        giant_section = b's' * (512 * 1024)
        adversarial = b'[' + giant_section + b']\n' + b'k=v\n' * 100000
        call(adversarial, [(giant_section, b'k', b'', 1)], b'[' + giant_section + b']\n')
        rng = random.Random(1800)
        for i in range(80):
            section = b'owner/' + str(i).encode()
            before = b'; untouched ' + str(rng.randrange(100000)).encode() + b'\n'
            raw = before + b'[' + section + b']\r\nkeep = stay\r\nkey = old\r\n[other]\nkey=other\n'
            value = str(rng.randrange(100000)).encode()
            want = raw.replace(b'key = old\r\n', b'').replace(b'['+section+b']\r\n', b'['+section+b']\r\nkey='+value+b'\n')
            call(raw, [(section, b'key', value, 0)], want)
        call(b'[owner/tool]', change, block)
        call(b'[owner/tool]\r\n; retained\r\n', change, b'[owner/tool]\r\npinned=yes\n; retained\r\n')
        group = [(b'owner/tool', b'a', b'1', 0), (b'other', b'b', b'2', 0), (b'owner/tool', b'c', b'3', 0)]
        call(b'', group, b'[owner/tool]\na=1\nc=3\n[other]\nb=2\n')
        call(b'[owner/tool]\n; keep\n[other]\n', group, b'[owner/tool]\na=1\nc=3\n; keep\n[other]\nb=2\n')
        cycle = b'; keep\r\n[owner/tool]\r\nunknown=retained\r\n'
        for i in range(64):
            value = str(i%2).encode()
            cycle = call(cycle, [(b'owner/tool', b'pinned', value, 0)], b'; keep\r\n[owner/tool]\r\npinned='+value+b'\nunknown=retained\r\n')
            assert cycle.count(b'[owner/tool]') == 1
            cycle = call(cycle, [(b'owner/tool', b'pinned', b'', 1)], b'; keep\r\n[owner/tool]\r\nunknown=retained\r\n')
        if fault:
            call(source, change, error=-12, fail=True)
            call(b'bad line', change, error=-22, fail=True)
        print(f'ok extension choices: {total} native preservation, grammar, limit and fault cases', flush=True)


if __name__ == '__main__':
    main()
