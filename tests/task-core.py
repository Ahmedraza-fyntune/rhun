#!/usr/bin/env python3
"""Run the managed-task core golden test and optional private allocation-failure build."""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def checked(command):
    result = subprocess.run(list(map(str, command)), cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=120)
    if result.returncode:
        raise AssertionError(f'{command[0]} exited {result.returncode}: {result.stdout.decode(errors="replace")[:4000]}')


def runtime_objects(platform):
    excluded = {'src/main.s', 'src/app/taskcore.s', 'src/memtry.s'}
    if platform != 'linux':
        excluded.update(('src/start.s', 'src/plat/wayland.s', 'src/plat/x11.s', 'src/plat/appearance.s'))
    objects = []
    for source in sorted((ROOT / 'src').rglob('*.s')):
        relative = source.relative_to(ROOT)
        path = relative.as_posix()
        if path in excluded:
            continue
        if path.startswith('src/mac/') and platform != 'macos':
            continue
        if path.startswith('src/win/') and platform != 'windows':
            continue
        if platform == 'windows':
            obj = ROOT / 'build/windows' / ('_'.join(relative.parts) + '.obj')
        else:
            obj = ROOT / 'build/obj' / (path.replace('/', '_')[:-2] + '.o')
        # An unrelated new source may not be in the last product build yet.
        # Exact source-to-object names avoid stale removed modules; unresolved dependencies fail linking.
        if obj.is_file():
            objects.append(obj)
    if not objects:
        raise AssertionError('build the native test target before the fault fixture')
    assets = ROOT / ('build/windows/build_windows_assets.s.obj' if platform == 'windows' else 'build/obj/build_assets.o')
    if not assets.is_file():
        raise AssertionError(f'build the native test target first: missing {assets}')
    objects.append(assets)
    return objects


def build_fault(platform, folder):
    copies = []
    for source, name in [('src/app/taskcore.s', 'core'), ('src/memtry.s', 'memory'),
                         ('tests/task_core_test.s', 'test')]:
        text = (ROOT / source).read_text()
        if name != 'test':
            if 'call mem_alloc_try' not in text:
                raise AssertionError(f'private allocation fixture no longer matches {source}')
            text = text.replace('call mem_alloc_try', 'call tct_fault_alloc')
        path = folder / (name + '.s')
        path.write_text(text)
        copies.append((path, name))
    objects = []
    if platform == 'windows':
        spec = importlib.util.spec_from_file_location('rhun_windows_builder', ROOT / 'tools/build-windows.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        mc, linker = builder.tool('llvm-mc'), builder.tool('lld-link')
    for path, name in copies:
        obj = folder / (name + ('.obj' if platform == 'windows' else '.o'))
        definitions = ['TEST_TASK_CORE_FAULT'] if name == 'test' else []
        if platform == 'macos':
            translated = folder / (name + '-a64.s')
            command = [sys.executable, ROOT / 'tools/arm64.py', '-I', ROOT / 'src', '-D', 'MACOS']
            for definition in definitions:
                command.extend(('-D', definition))
            checked([*command, path, translated])
            checked(['as', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', obj, translated])
        elif platform == 'windows':
            path.write_text(re.sub(r'(?m)^\.section \.rodata$', '.section .rdata,"dr"', path.read_text()))
            command = [mc, '-triple=x86_64-pc-windows-msvc', '-filetype=obj', '-defsym=WINDOWS=1',
                       '-I', ROOT / 'src', '-I', ROOT / 'src/win']
            for definition in definitions:
                command.append('-defsym=' + definition + '=1')
            checked([*command, path, '-o', obj])
        else:
            command = ['as', '--64', '-I', ROOT / 'src']
            for definition in definitions:
                command.extend(('--defsym', definition + '=1'))
            checked([*command, '-o', obj, path])
        objects.append(obj)
    objects.extend(runtime_objects(platform))
    exe = folder / ('task-core-fault.exe' if platform == 'windows' else 'task-core-fault')
    if platform == 'macos':
        command = ['clang', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', exe, *objects]
        for framework in ('AppKit', 'QuartzCore', 'IOSurface', 'CoreServices', 'Carbon'):
            command.extend(('-framework', framework))
    elif platform == 'windows':
        libraries = [ROOT / 'build/windows' / (source.stem + '.lib') for source in sorted((ROOT / 'src/win').glob('*.def'))]
        command = [linker, '/nodefaultlib', '/entry:win_start', '/subsystem:console,6.02',
                   '/stack:33554432,33554432', '/dynamicbase', '/nxcompat', '/largeaddressaware',
                   '/out:' + str(exe), *objects, ROOT / 'build/windows/rhun.res', *libraries]
    else:
        command = ['ld', '-static', '-nostdlib', '--no-dynamic-linker', '-z', 'noexecstack', '-o', exe, *objects]
    checked(command)
    return exe


def run_test(exe, wine, label):
    if not exe.is_file():
        raise AssertionError(f'build the native test target first: missing {exe}')
    command = [str(exe)]
    if wine:
        path = exe.resolve().as_posix()
        command = [wine, path if os.name == 'nt' else 'Z:' + path]
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
    expected = (ROOT / 'tests/data/task-core.expected').read_bytes()
    if result.returncode or result.stdout != expected:
        raise AssertionError(f'{label}: exit {result.returncode}, output {result.stdout!r}')
    print('ok   ' + label, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--wine')
    parser.add_argument('--faults', action='store_true')
    args = parser.parse_args()
    platform = 'windows' if args.wine or os.name == 'nt' else 'macos' if sys.platform == 'darwin' else 'linux'
    exe = (args.exe or ROOT / ('build/windows/task_core_test.exe' if platform == 'windows' else 'build/task_core_test')).resolve()
    run_test(exe, args.wine, 'task-core')
    if args.faults:
        with tempfile.TemporaryDirectory(prefix='rhun-task-core-') as temporary:
            run_test(build_fault(platform, Path(temporary)), args.wine, 'task-core-allocation-faults')


if __name__ == '__main__':
    main()
