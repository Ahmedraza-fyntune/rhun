#!/usr/bin/env python3
"""Bounded snapshot reads, descriptor cleanup and allocation order."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def check_reads(executable, folder, runner=()):
    folder.mkdir(parents=True)
    data = folder / 'data'
    data.write_bytes(b'a\0z')
    empty = folder / 'empty'
    empty.write_bytes(b'')
    cases = [(empty, 'empty')]
    cases += [(data, mode) for mode in ('exact', 'larger', 'over', 'zero', 'legacy', 'extra')]
    cases += [(folder / 'missing', mode) for mode in ('negative', 'max', 'missing')]
    cases.append((folder, 'directory'))
    if sys.platform == 'linux' and not runner:
        fifo = folder / 'fifo'
        os.mkfifo(fifo)
        cases.append((fifo, 'fifo'))
    expected = (ROOT / 'tests/data/file-read-limited.expected').read_bytes()
    kwargs = {}
    if os.name == 'posix' and not runner:
        import resource

        def low_descriptors():
            resource.setrlimit(resource.RLIMIT_NOFILE, (32, 32))
        kwargs['preexec_fn'] = low_descriptors
    for path, mode in cases:
        argument = ('Z:' + path.resolve().as_posix()) if runner else str(path.resolve())
        result = subprocess.run([*runner, str(executable), argument, mode],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=15, **kwargs)
        assert result.returncode == 0 and result.stdout == expected, (mode, result.returncode, result.stdout)
        print('ok file-read-limited/' + mode, flush=True)


def allocation_probe(folder):
    source = (ROOT / 'src/mem.s').read_text()
    assert source.count('FN mem_alloc\n') == 1
    (folder / 'mem.s').write_text(source.replace('FN mem_alloc\n', 'FN frt_real_mem_alloc\n', 1))
    for name, path, extra in [('mem', folder / 'mem.s', []),
                              ('fixture', ROOT / 'tests/file_read_limited_test.s',
                               ['--defsym', 'TEST_FILE_READ_LIMITED_ALLOC=1'])]:
        subprocess.run(['as', '--64', '-I', str(ROOT / 'src'), '-I', str(ROOT / 'build'),
                        *extra, '-o', str(folder / (name + '.o')), str(path)], check=True)
    sources = [p for p in (ROOT / 'src').rglob('*.s')
               if p.relative_to(ROOT).as_posix() not in ('src/main.s', 'src/mem.s')
               and not any(part in ('mac', 'win') for part in p.relative_to(ROOT).parts)]
    objects = sorted(ROOT / 'build/obj' /
                     (p.relative_to(ROOT).as_posix().replace('/', '_')[:-2] + '.o')
                     for p in sources)
    executable = folder / 'allocation-probe'
    subprocess.run(['ld', '-static', '-nostdlib', '--no-dynamic-linker', '-z', 'noexecstack',
                    '-o', str(executable), str(folder / 'fixture.o'), str(folder / 'mem.o'),
                    *map(str, objects), str(ROOT / 'build/obj/build_assets.o')], check=True)
    data = folder / 'probe-data'
    data.write_bytes(b'a\0z')
    for mode in ('over', 'zero', 'negative', 'max', 'missing', 'directory'):
        path = folder if mode == 'directory' else folder / 'absent' if mode == 'missing' else data
        result = subprocess.run([str(executable), str(path), mode], capture_output=True, timeout=15)
        assert result.returncode == 0, (mode, result.returncode, result.stdout, result.stderr)
    print('ok file-read-limited/rejected-before-allocation', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--wine')
    args = parser.parse_args()
    executable = args.exe or ROOT / ('build/windows/file_read_limited_test.exe'
                                    if os.name == 'nt' else 'build/file_read_limited_test')
    with tempfile.TemporaryDirectory(prefix='rhun-file-read-') as temporary:
        folder = Path(temporary)
        check_reads(executable.resolve(), folder / 'cases', [args.wine] if args.wine else [])
        if sys.platform == 'linux' and not args.wine and all(shutil.which(x) for x in ('as', 'ld')):
            allocation_probe(folder)


if __name__ == '__main__':
    main()
