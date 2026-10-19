#!/usr/bin/env python3
"""Native coordination locks, no-replace publication and deterministic crashes."""
import argparse
import importlib.util
import os
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def build_faults(folder):
    spec = importlib.util.spec_from_file_location('windows_build', ROOT / 'tools/build-windows.py')
    build = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(build)
    mc, link = build.tool('llvm-mc'), build.tool('lld-link')
    out = ROOT / 'build/windows'
    source = (ROOT / 'src/win/fileops.s').read_text()
    assert source.count('call win_file_path_try') == 2
    assert source.count('API MoveFileExW') == 1
    source = source.replace('call win_file_path_try', 'call fop_path').replace('API MoveFileExW', 'call fop_move')
    paths = [folder / 'fileops.s', folder / 'fixture.s']
    paths[0].write_text(source)
    paths[1].write_text('.equ TEST_FILE_OPS_FAULT, 1\n' +
                        (ROOT / 'tests/file_ops_test.s').read_text().replace(
                            '.section .rodata', '.section .rdata,"dr"'))
    objects = []
    for path in paths:
        obj = path.with_suffix('.obj')
        subprocess.run([mc, '-triple=x86_64-pc-windows-msvc', '-filetype=obj',
                        '-I', str(ROOT / 'src'), '-I', str(ROOT / 'src/win'),
                        '-I', str(out), '-defsym=WINDOWS=1', '-o', str(obj), str(path)], check=True)
        objects.append(obj)
    excluded = {'src/main.s', 'src/win/fileops.s', 'src/start.s', 'src/plat/wayland.s',
                'src/plat/x11.s', 'src/plat/appearance.s'}
    for path in sorted((ROOT / 'src').rglob('*.s')):
        rel = path.relative_to(ROOT).as_posix()
        if rel not in excluded and 'mac' not in path.relative_to(ROOT).parts:
            objects.append(out / (rel.replace('/', '_') + '.obj'))
    objects.append(out / 'build_windows_assets.s.obj')
    executable = folder / 'file_ops_fault_test.exe'
    libs = [out / (p.stem + '.lib') for p in sorted((ROOT / 'src/win').glob('*.def'))]
    subprocess.run([link, '/nodefaultlib', '/entry:win_start', '/subsystem:console,6.02',
                    '/stack:33554432,33554432', '/dynamicbase', '/nxcompat', '/largeaddressaware',
                    '/out:' + str(executable), *map(str, objects), str(out / 'rhun.res'),
                    *map(str, libs)], cwd=ROOT, check=True)
    return executable


class Fixture:
    def __init__(self, executable, runner):
        self.command = [*runner, str(executable)]
        self.wine = bool(runner)

    def path(self, path):
        return ('Z:' + path.absolute().as_posix()) if self.wine else str(path.absolute())

    def start(self, mode, *paths):
        return subprocess.Popen([*self.command, mode, *map(self.path, paths)],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def run(self, mode, *paths, expected=0, output=b''):
        result = subprocess.run([*self.command, mode, *map(self.path, paths)],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
        assert result.returncode == expected and result.stdout == output, (
            mode, paths, result.returncode, result.stdout)


def line(process, expected):
    result = queue.Queue()
    threading.Thread(target=lambda: result.put(process.stdout.readline()), daemon=True).start()
    try:
        actual = result.get(timeout=15)
        assert actual == expected, (process.poll(), expected, actual)
    except BaseException:
        process.kill()
        process.communicate(timeout=15)
        raise


def stop(process):
    if process.poll() is None:
        process.kill()
    process.communicate(timeout=15)


def check_locks(fixture, folder):
    path = folder / 'stable.lock'
    path.write_bytes(b'')
    fixture.run('locks', path, output=(ROOT / 'tests/data/file-ops.expected').read_bytes())
    print('ok file-ops/independent-descriptors', flush=True)
    for mode in ('sh', 'ex'):
        holder = fixture.start('hold-' + mode, path)
        try:
            line(holder, b'READY\n')
            fixture.run('probe-sh', path, expected=0 if mode == 'sh' else 11)
            fixture.run('probe-ex', path, expected=11)
            holder.stdin.write(b'g')
            holder.stdin.flush()
            line(holder, b'RELEASED\n')
            fixture.run('probe-ex', path)
            holder.stdin.write(b'g')
            holder.stdin.flush()
            output = holder.communicate(timeout=15)[0]
            assert holder.returncode == 0 and output == b'', (holder.returncode, output)
        finally:
            stop(holder)
        print('ok file-ops/multiprocess-' + mode + '-unlock-keeps-fd', flush=True)
        holder = fixture.start('hold-' + mode, path)
        try:
            line(holder, b'READY\n')
            holder.kill()
            holder.communicate(timeout=15)
            deadline = time.monotonic() + 5
            while True:
                result = subprocess.run([*fixture.command, 'probe-ex', fixture.path(path)],
                                        capture_output=True, timeout=15)
                if result.returncode == 0:
                    assert result.stdout == b'' and result.stderr == b'', result
                    break
                assert result.returncode == 11 and time.monotonic() < deadline, result
                time.sleep(.01)
        finally:
            stop(holder)
        print('ok file-ops/process-death-' + mode, flush=True)


def publish_case(fixture, folder, payload, name):
    source, final = folder / (name + '.pending'), folder / (name + '.idx')
    source.write_bytes(payload)
    fixture.run('publish', source, final)
    assert not source.exists() and final.read_bytes() == payload


def check_publication(fixture, folder):
    for index, payload in enumerate((b'', bytes(range(160)), b'a\0z'*65536)):
        publish_case(fixture, folder, payload, str(index))
    publish_case(fixture, folder, b'Unicode\0data', "é 水 😀 & '$ `")
    deep = folder
    for index in range(6):
        deep /= str(index) + 'x'*49
        deep.mkdir()
    publish_case(fixture, deep, bytes(range(160)), 'long')
    source, final = folder / 'dir.pending', folder / 'dir.final'
    source.mkdir()
    (source / 'nested').mkdir()
    (source / 'nested/data').write_bytes(b'tree\0data')
    fixture.run('publish', source, final)
    assert not source.exists() and (final / 'nested/data').read_bytes() == b'tree\0data'
    print('ok file-ops/publish-binary-directory-paths', flush=True)
    for kind in ('file', 'directory', 'link'):
        source, final = folder / (kind + '.pending'), folder / (kind + '.existing')
        source.write_bytes(b'new\0bytes')
        if kind == 'file':
            final.write_bytes(b'keep\0old')
        elif kind == 'directory':
            final.mkdir()
            (final / 'keep').write_bytes(b'keep\0old')
        elif os.name == 'posix' and not fixture.wine:
            final.symlink_to(folder / '0.idx')
        else:
            continue
        # Every existing destination is a collision, regardless of its type.
        fixture.run('publish', source, final, expected=17)
        assert source.read_bytes() == b'new\0bytes'
        if kind == 'file':
            assert final.read_bytes() == b'keep\0old'
        elif kind == 'directory':
            assert (final / 'keep').read_bytes() == b'keep\0old'
        else:
            assert final.is_symlink() and os.readlink(final) == str(folder / '0.idx')
    source, final = folder / 'null.pending', folder / 'null.idx'
    source.write_bytes(b'preserve')
    fixture.run('null-source', source, final, expected=22)
    fixture.run('null-dest', source, final, expected=22)
    if fixture.wine or os.name == 'nt':
        fixture.run('invalid-source', source, final, expected=22)
        fixture.run('invalid-dest', source, final, expected=22)
    assert source.read_bytes() == b'preserve' and not final.exists()
    fixture.run('publish', folder / 'missing', final, expected=2)
    assert not final.exists()
    print('ok file-ops/collision-and-invalid-preserve-files', flush=True)


def check_race_and_crash(fixture, folder):
    for iteration in range(8):
        first, second, final = [folder / ('race-' + str(iteration) + suffix)
                                for suffix in ('.a', '.b', '.idx')]
        payloads = [bytes([i])*160 for i in (65, 66)]
        for path, payload in zip((first, second), payloads):
            path.write_bytes(payload)
        publishers = [fixture.start('before', path, final) for path in (first, second)]
        failures = []
        done = threading.Event()

        def reader():
            while not done.is_set():
                try:
                    observed = final.read_bytes()
                except FileNotFoundError:
                    continue
                if observed not in payloads:
                    failures.append(observed)
                    return
        observer = threading.Thread(target=reader, daemon=True)
        try:
            for process in publishers:
                line(process, b'READY\n')
            observer.start()
            for process in publishers:
                process.stdin.write(b'g')
                process.stdin.flush()
            results = [process.communicate(timeout=15)[0] for process in publishers]
            statuses = [p.returncode for p in publishers]
            assert results == [b'', b''] and sorted(statuses) == [0, 17], (results, statuses)
            selected = final.read_bytes()
            assert selected in payloads and not failures
            for path, payload in zip((first, second), payloads):
                assert path.exists() == (payload != selected)
                if path.exists():
                    assert path.read_bytes() == payload
        finally:
            done.set()
            if observer.is_alive():
                observer.join(timeout=5)
            for process in publishers:
                stop(process)
        assert not failures, failures
    print('ok file-ops/concurrent-publish-and-read', flush=True)
    for mode in ('before', 'after'):
        source, final = folder / (mode + '.pending'), folder / (mode + '.idx')
        payload = bytes(range(160))
        source.write_bytes(payload)
        process = fixture.start(mode, source, final)
        try:
            line(process, b'READY\n')
            process.kill()
            process.communicate(timeout=15)
            assert source.exists() == (mode == 'before')
            assert final.exists() == (mode == 'after')
            assert (source if mode == 'before' else final).read_bytes() == payload
        finally:
            stop(process)
    print('ok file-ops/deterministic-process-crash', flush=True)


def check_faults(fixture, folder):
    for mode in ('oom1', 'oom2', 'api-before', 'api-after'):
        source, final = folder / (mode + '.pending'), folder / (mode + '.idx')
        payload = bytes(range(160))
        source.write_bytes(payload)
        fixture.run(mode, source, final, expected=12 if mode.startswith('oom') else 13)
        published = mode != 'api-before'
        assert source.exists() != published and final.exists() == published
        assert (final if published else source).read_bytes() == payload
        print('ok file-ops/' + mode + '-ownership-and-state', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--fault-exe', type=Path)
    parser.add_argument('--wine')
    parser.add_argument('--build-windows-only', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='rhun-file-ops-') as directory:
        folder = Path(directory)
        if args.build_windows_only:
            shutil.copy2(build_faults(folder), ROOT / 'build/windows/file_ops_fault_test.exe')
            return
        windows = bool(args.wine) or os.name == 'nt'
        executable = args.exe or ROOT / ('build/windows/file_ops_test.exe' if windows else 'build/file_ops_test')
        runner = [args.wine] if args.wine else []
        fixture = Fixture(executable.resolve(), runner)
        check_locks(fixture, folder)
        check_publication(fixture, folder)
        check_race_and_crash(fixture, folder)
        if windows:
            faults = args.fault_exe or build_faults(folder)
            check_faults(Fixture(faults.resolve(), runner), folder)


if __name__ == '__main__':
    main()
