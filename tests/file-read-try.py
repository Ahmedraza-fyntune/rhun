#!/usr/bin/env python3
"""Fallible snapshots, path boundaries, native handles and private fault tests."""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def build_faults(folder, windows=False):
    paths = []
    names = ['src/filetry.s'] + (['src/win/pathtry.s'] if windows else [])
    for name in names:
        source = (ROOT / name).read_text().replace('call mem_alloc_try', 'call ftr_alloc')
        if name == 'src/filetry.s':
            source = source.replace('SYS SYS_fstat', 'call ftr_stat').replace('SYS SYS_read', 'call ftr_read')
        else:
            for api, stub in [('GetFileType', 'ftr_file_type'),
                              ('GetFileInformationByHandle', 'ftr_file_info'),
                              ('CreateFileW', 'ftr_create_file')]:
                source = source.replace('API ' + api, 'call ' + stub)
        path = folder / Path(name).name
        path.write_text(source)
        paths.append(path)
    fixture = folder / 'fixture.s'
    fixture.write_text('.equ TEST_FILE_TRY_FAULT, 1\n' +
                       (ROOT / 'tests/file_read_try_test.s').read_text())
    paths.append(fixture)
    objects = []
    if windows:
        spec = importlib.util.spec_from_file_location('windows_build', ROOT / 'tools/build-windows.py')
        build = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(build)
        mc, link = build.tool('llvm-mc'), build.tool('lld-link')
        out = ROOT / 'build/windows'
        for path in paths:
            path.write_text(re.sub(r'(?m)^(\s*\.section) \.rodata[^\n]*', r'\1 .rdata,"dr"', path.read_text()))
            obj = path.with_suffix('.obj')
            subprocess.run([mc, '-triple=x86_64-pc-windows-msvc', '-filetype=obj',
                            '-I', str(ROOT / 'src'), '-I', str(ROOT / 'src/win'),
                            '-I', str(out), '-defsym=WINDOWS=1', '-o', str(obj), str(path)], check=True)
            objects.append(obj)
        excluded = set(names) | {'src/main.s', 'src/start.s', 'src/plat/wayland.s',
                                 'src/plat/x11.s', 'src/plat/appearance.s'}
        for path in sorted((ROOT / 'src').rglob('*.s')):
            rel = path.relative_to(ROOT).as_posix()
            if rel not in excluded and 'mac' not in path.relative_to(ROOT).parts:
                objects.append(out / (rel.replace('/', '_') + '.obj'))
        objects.append(out / 'build_windows_assets.s.obj')
        executable = folder / 'file_read_try_fault_test.exe'
        libs = [out / (p.stem + '.lib') for p in sorted((ROOT / 'src/win').glob('*.def'))]
        subprocess.run([link, '/nodefaultlib', '/entry:win_start', '/subsystem:console,6.02',
                        '/stack:33554432,33554432', '/dynamicbase', '/nxcompat', '/largeaddressaware',
                        '/out:' + str(executable), *map(str, objects), str(out / 'rhun.res'),
                        *map(str, libs)], cwd=ROOT, check=True)
    else:
        mac = sys.platform == 'darwin'
        for path in paths:
            obj = path.with_suffix('.o')
            if mac:
                translated = path.with_suffix('.a64.s')
                subprocess.run([sys.executable, str(ROOT / 'tools/arm64.py'), '-I', str(ROOT / 'src'),
                                '-D', 'MACOS', str(path), str(translated)], cwd=ROOT, check=True)
                subprocess.run(['as', '-arch', 'arm64', '-mmacosx-version-min=12.0',
                                '-o', str(obj), str(translated)], check=True)
            else:
                subprocess.run(['as', '--64', '-I', str(ROOT / 'src'), '-I', str(ROOT / 'build'),
                                '-o', str(obj), str(path)], check=True)
            objects.append(obj)
        excluded = set(names) | {'src/main.s'}
        if mac:
            excluded |= {'src/start.s', 'src/plat/wayland.s', 'src/plat/x11.s', 'src/plat/appearance.s'}
        for path in sorted((ROOT / 'src').rglob('*.s')):
            rel = path.relative_to(ROOT).as_posix()
            if rel in excluded or 'win' in path.relative_to(ROOT).parts:
                continue
            if 'mac' in path.relative_to(ROOT).parts and not mac:
                continue
            objects.append(ROOT / 'build/obj' / (rel.replace('/', '_')[:-2] + '.o'))
        objects.append(ROOT / 'build/obj/build_assets.o')
        executable = folder / 'file-read-try-faults'
        if mac:
            command = ['clang', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', str(executable),
                       *map(str, objects)]
            for framework in ('AppKit', 'QuartzCore', 'IOSurface', 'CoreServices', 'Carbon'):
                command += ['-framework', framework]
        else:
            command = ['ld', '-static', '-nostdlib', '--no-dynamic-linker', '-z', 'noexecstack',
                       '-o', str(executable), *map(str, objects)]
        subprocess.run(command, check=True)
    return executable


def run(executable, path, mode, runner):
    expected = (ROOT / 'tests/data/file-read-try.expected').read_bytes()
    kwargs = {}
    if os.name == 'posix' and not runner:
        import resource

        def low_descriptors():
            resource.setrlimit(resource.RLIMIT_NOFILE, (32, 32))
        kwargs['preexec_fn'] = low_descriptors
    # Keep the final component intact so link tests reach the no-follow open.
    argument = ('Z:' + path.absolute().as_posix()) if runner else str(path.absolute())
    result = subprocess.run([*runner, str(executable), argument, mode],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45, **kwargs)
    assert result.returncode == 0 and result.stdout == expected, (
        executable, path, mode, result.returncode, result.stdout)
    print('ok file-read-try/' + mode, flush=True)


def check(executable, folder, runner, faults=False):
    folder.mkdir(parents=True)
    data = folder / 'data'
    data.write_bytes(b'a\0z')
    empty = folder / 'empty'
    empty.write_bytes(b'')
    cases = [(empty, 'empty')]
    cases += [(data, mode) for mode in ('exact', 'larger', 'over', 'zero', 'negative', 'max', 'null')]
    cases += [(folder / 'missing', 'missing'), (folder, 'directory')]
    if not runner and os.name == 'posix':
        fifo = folder / 'fifo'
        os.mkfifo(fifo)
        link = folder / 'link'
        link.symlink_to(data)
        cases += [(fifo, 'fifo'), (link, 'link')]
    if runner or os.name == 'nt':
        cases += [(data, mode) for mode in ('invalid-utf8', 'long-input')]
    special = folder / "spaces é 水 😀 & '$ `"
    special.write_bytes(b'a\0z')
    cases.append((special, 'exact'))
    deep = folder
    for index in range(6):
        deep /= str(index) + 'x'*49
        deep.mkdir()
    long_data = deep / 'data'
    long_data.write_bytes(b'a\0z')
    cases.append((long_data, 'exact'))
    if faults:
        cases += [(data, mode) for mode in ('oom1', 'stat-error', 'read-error', 'interrupt',
                                          'short', 'eof', 'snapshot', 'partial-error')]
        if runner or os.name == 'nt':
            cases += [(data, mode) for mode in ('oom2', 'type-error', 'info-error', 'wrong-type',
                                              'reparse', 'open-error', 'full')]
            cases += [(long_data, mode) for mode in ('oom1', 'oom2', 'oom3')]
    for path, mode in cases:
        run(executable, path, mode, runner)
        if faults and mode.startswith('oom'):
            run(executable, path, 'exact', runner)


def check_windows_paths(executable, runner):
    import ntpath
    cases = [('relative/é 水 😀', 'relative/é 水 😀'),
             ('C:/short path/data', 'C:/short path/data'),
             ('//?/C:/already/extended', '\\\\?\\C:\\already\\extended'),
             ('//./C:/device', '\\\\.\\C:\\device'),
             ('//server/share/short', '//server/share/short')]
    tail = '/'.join('component' + str(i) + 'x'*40 for i in range(7))
    cases += [('C:/' + tail, '\\\\?\\C:\\' + tail.replace('/', '\\')),
              ('//server/share/' + tail, '\\\\?\\UNC\\server\\share\\' + tail.replace('/', '\\'))]
    current = ('Z:' + Path.cwd().as_posix()) if runner else str(Path.cwd())
    cases.append((tail, '\\\\?\\' + ntpath.normpath(ntpath.join(current, tail))))
    for source, expected in cases:
        result = subprocess.run([*runner, str(executable), source, expected],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        assert result.returncode == 0 and result.stdout == b'ok fallible Windows path\n', (
            source, expected, result.returncode, result.stdout)
        print('ok file-read-try/windows-path/' + source[:35], flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--fault-exe', type=Path)
    parser.add_argument('--path-exe', type=Path)
    parser.add_argument('--wine')
    parser.add_argument('--build-windows-only', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='rhun-file-try-') as directory:
        folder = Path(directory)
        if args.build_windows_only:
            executable = build_faults(folder, windows=True)
            shutil.copy2(executable, ROOT / 'build/windows/file_read_try_fault_test.exe')
            return
        runner = [args.wine] if args.wine else []
        windows = bool(runner) or os.name == 'nt'
        executable = args.exe or ROOT / ('build/windows/file_read_try_test.exe'
                                         if windows else 'build/file_read_try_test')
        check(executable.resolve(), folder / 'native', runner)
        faults = args.fault_exe or build_faults(folder, windows=windows)
        check(faults.resolve(), folder / 'faults', runner, faults=True)
        if windows:
            paths = args.path_exe or ROOT / 'build/windows/path_try_test.exe'
            check_windows_paths(paths.resolve(), runner)


if __name__ == '__main__':
    main()
