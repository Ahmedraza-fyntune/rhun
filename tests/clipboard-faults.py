#!/usr/bin/env python3
"""Exercise recoverable clipboard allocation failures with a temporary allocator shim."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    if sys.platform != 'linux' or not all(shutil.which(x) for x in ('as', 'ld')):
        print('skip clipboard allocation failures (Linux binutils required)')
        return
    with tempfile.TemporaryDirectory(prefix='rhun-clipboard-faults-') as tmp:
        temporary = Path(tmp)
        source = (ROOT / 'src/mem.s').read_text()
        assert source.count('FN mem_alloc_try\n') == 1
        (temporary / 'mem.s').write_text(source.replace('FN mem_alloc_try\n',
                                                       'FN fault_real_mem_alloc_try\n', 1))
        for name, path in [('mem', temporary / 'mem.s'),
                           ('fixture', ROOT / 'tests/faults/clipboard_metadata.s')]:
            subprocess.run(['as', '--64', '-I', str(ROOT / 'src'), '-I', str(ROOT / 'build'),
                            '-o', str(temporary / (name + '.o')), str(path)], check=True)
        sources = [p for p in (ROOT / 'src').rglob('*.s')
                   if p.relative_to(ROOT).as_posix() not in ('src/main.s', 'src/mem.s')
                   and not any(part in ('mac', 'win') for part in p.relative_to(ROOT).parts)]
        objects = sorted(ROOT / 'build/obj' /
                         (p.relative_to(ROOT).as_posix().replace('/', '_')[:-2] + '.o')
                         for p in sources)
        assert objects and (ROOT / 'build/obj/src_mem.o').exists(), 'run build.sh test first'
        assert all(p.exists() for p in objects), 'run build.sh test first'
        executable = temporary / 'clipboard-faults'
        subprocess.run(['ld', '-static', '-nostdlib', '--no-dynamic-linker', '-z', 'noexecstack',
                        '-o', str(executable), str(temporary / 'fixture.o'),
                        str(temporary / 'mem.o'), *(str(p) for p in objects),
                        str(ROOT / 'build/obj/build_assets.o')], check=True)
        result = subprocess.run([str(executable)], capture_output=True, timeout=60)
        assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
        assert result.stdout == b'ok clipboard allocation failures\n', result.stdout
        assert not result.stderr, result.stderr
        print(result.stdout.decode(), end='')


if __name__ == '__main__':
    main()
