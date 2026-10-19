#!/usr/bin/env python3
"""Check enqueue-only queue limits and isolated allocation/forbidden-operation faults."""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, **kwargs):
    result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=120, **kwargs)
    if result.returncode:
        raise AssertionError(f'{command[0]}: exit {result.returncode}, '
                             f'{(result.stdout + result.stderr)[:4000]!r}')
    return result


def fault_fixture(platform, folder, kind='enqueue'):
    builder = None
    if platform == 'windows':
        spec = importlib.util.spec_from_file_location('enqueue_windows_builder', ROOT / 'tools/build-windows.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
    objects = []
    if kind not in ('enqueue', 'flush', 'settingsqueue'):
        raise ValueError('unknown transport fixture kind')
    for name, relative in [('transport', 'src/app/ext' + kind + '.s'),
                           ('fixture', 'tests/ext_' + kind + '_test.s')]:
        text = (ROOT / relative).read_text()
        if name == 'transport' and kind == 'enqueue':
            marker = 'call mem_alloc_try'
            if text.count(marker) != 1:
                raise AssertionError('enqueue allocation fault no longer matches')
            text = text.replace(marker, 'call ee_alloc')
            for forbidden in ('ext_send', 'ext_flush', 'memmove'):
                text = re.sub(r'\bcall ' + forbidden + r'\b', 'call ee_poison', text)
        if name == 'transport' and kind == 'flush':
            for original, replacement in [('SYS SYS_write', 'call ef_write'),
                                          ('SYS SYS_fcntl', 'call ef_fcntl'),
                                          ('call watch_set_events', 'call ef_watch'),
                                          ('call time_ms', 'call ef_time')]:
                if original not in text:
                    raise AssertionError('flush fault interception no longer matches: ' + original)
                text = text.replace(original, replacement)
        if name == 'transport' and kind == 'settingsqueue':
            if text.count('call ext_settings_memory_try') != 3:
                raise AssertionError('settings queue allocation interception no longer matches')
            text = text.replace('call ext_settings_memory_try', 'call sq_alloc')
        path = folder / (name + '.s')
        obj = path.with_suffix('.obj' if builder else '.o')
        if builder:
            text = re.sub(r'(?m)^\.section \.rodata$', '.section .rdata,"dr"', text)
        path.write_text(text)
        define = 'TEST_SETTINGS_QUEUE_FAULT' if kind == 'settingsqueue' else 'TEST_ENQUEUE_FAULT'
        if platform == 'macos':
            translated = folder / (name + '-a64.s')
            run([sys.executable, ROOT / 'tools/arm64.py', '-I', ROOT / 'src', '-D', 'MACOS',
                 '-D', define, path, translated])
            run(['as', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', obj, translated])
        elif builder:
            run([builder.tool('llvm-mc'), '-triple=x86_64-pc-windows-msvc', '-filetype=obj',
                 '-defsym=WINDOWS=1', '-defsym=' + define + '=1', '-I', ROOT / 'src',
                 '-I', ROOT / 'src/win', path, '-o', obj])
        else:
            run(['as', '--64', '-I', ROOT / 'src', '--defsym', define + '=1',
                 '-o', obj, path])
        objects.append(obj)
    excluded = {'src/main.s', 'src/app/ext' + kind + '.s'}
    if platform != 'linux':
        excluded.update(('src/start.s', 'src/plat/wayland.s', 'src/plat/x11.s', 'src/plat/appearance.s'))
    build = ROOT / ('build/windows' if builder else 'build/obj')
    for path in sorted((ROOT / 'src').rglob('*.s')):
        relative = path.relative_to(ROOT).as_posix()
        if relative in excluded or relative.startswith('src/mac/') and platform != 'macos' or relative.startswith('src/win/') and not builder:
            continue
        name = relative.replace('/', '_')
        obj = build / (name + '.obj' if builder else name[:-2] + '.o')
        if not obj.is_file():
            raise AssertionError('build runtime first: ' + str(obj))
        objects.append(obj)
    objects.append(build / ('build_windows_assets.s.obj' if builder else 'build_assets.o'))
    executable = folder / ('ext_' + kind + '_fault' + ('.exe' if builder else ''))
    if platform == 'macos':
        command = ['clang', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', executable, *objects]
        for framework in ('AppKit', 'QuartzCore', 'IOSurface', 'CoreServices', 'Carbon'):
            command.extend(('-framework', framework))
    elif builder:
        libraries = [build / (path.stem + '.lib') for path in sorted((ROOT / 'src/win').glob('*.def'))]
        command = [builder.tool('lld-link'), '/nodefaultlib', '/entry:win_start', '/subsystem:console,6.02',
                   '/stack:33554432,33554432', '/dynamicbase', '/nxcompat', '/largeaddressaware',
                   '/out:' + str(executable), *objects, *libraries, build / 'rhun.res']
    else:
        command = ['ld', '-static', '-nostdlib', '--no-dynamic-linker', '-z', 'noexecstack',
                   '-o', executable, *objects]
    run(command)
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--wine')
    parser.add_argument('--faults', action='store_true')
    args = parser.parse_args()
    windows = bool(args.wine) or os.name == 'nt'
    executable = (args.exe or ROOT / ('build/windows/ext_enqueue_test.exe' if windows
                                     else 'build/ext_enqueue_test')).resolve()
    expected = (ROOT / 'tests/data/ext-enqueue.expected').read_bytes()

    def check(exe):
        command = [args.wine, 'Z:' + exe.resolve().as_posix()] if args.wine else [exe]
        result = run(command)
        if result.stdout + result.stderr != expected:
            raise AssertionError(f'enqueue fixture output: {(result.stdout + result.stderr)[:4000]!r}')

    check(executable)
    print('ok   bounded enqueue queue limits and ownership', flush=True)
    if args.faults:
        platform = 'windows' if windows else 'macos' if sys.platform == 'darwin' else 'linux'
        with tempfile.TemporaryDirectory(prefix='rhun-enqueue-fault-') as temporary:
            check(fault_fixture(platform, Path(temporary)))
        print('ok   enqueue allocation refusal and forbidden operation faults', flush=True)


if __name__ == '__main__':
    main()
