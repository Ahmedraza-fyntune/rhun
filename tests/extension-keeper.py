#!/usr/bin/env python3
"""Run real captured-plan/lease ownership and supervised extension lifecycle fixtures."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, help='native captured-plan and lease fixture')
    parser.add_argument('--lifecycle-exe', type=Path, help='native editor lifecycle fixture')
    parser.add_argument('--wine', help='Wine executable or wrapper for PE fixtures')
    parser.add_argument('--drive', type=Path, help='host directory mounted as Wine C:')
    args = parser.parse_args()
    windows = bool(args.wine) or os.name == 'nt'
    build = ROOT / ('build/windows' if windows else 'build')
    suffix = '.exe' if windows else ''
    fixtures = [(args.exe or build / ('task_extension_keeper_test' + suffix),
                 b'ok independent extension keeper\n'),
                (args.lifecycle_exe or build / ('extension_lifecycle_test' + suffix),
                 b'ok supervised extension lifecycle\n')]
    drive = args.drive.resolve() if args.drive else None
    if drive and not args.wine:
        parser.error('--drive requires --wine')

    def argument(path):
        path = path.resolve()
        if args.wine:
            if drive:
                try:
                    return 'C:/' + path.relative_to(drive).as_posix()
                except ValueError:
                    pass
            return 'Z:' + path.as_posix()
        return path.as_posix()

    for executable, expected in fixtures:
        executable = executable.resolve()
        if not executable.is_file():
            parser.error(f'build the native fixture first: {executable}')
        with tempfile.TemporaryDirectory(prefix='rhun-extension-keeper-', dir=drive) as temporary:
            base = Path(temporary).resolve()
            root = base / 'store'
            payload = root / 'owner/name'
            payload.mkdir(parents=True)
            (root / '.change.lock').touch()
            lease = root / '.leases/legacy' / b'owner'.hex() / (b'name'.hex() + '.lock')
            lease.parent.mkdir(parents=True)
            lease.touch()
            state = base / 'state'
            state.mkdir()
            home = base / 'home'
            home.mkdir()
            (home / 'approved').write_bytes(b'keeper')
            command = ([args.wine] if args.wine else [])
            command += [argument(path) for path in (executable, root, payload, state, home)]
            result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=120)
            if result.returncode or result.stdout + result.stderr != expected:
                raise AssertionError(f'{executable.name}: exit {result.returncode}, '
                                     f'{(result.stdout + result.stderr)[:4000]!r}')
            print('ok   ' + executable.stem, flush=True)


if __name__ == '__main__':
    main()
