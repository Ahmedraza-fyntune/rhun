#!/usr/bin/env python3
"""Exercise bounded output with deterministic native write and mode failures."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wine')
    parser.add_argument('--exe', type=Path, help='prebuilt fixture, or output with --build-only')
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    if args.build_only and not args.exe:
        parser.error('--build-only requires --exe output path')
    spec = importlib.util.spec_from_file_location('rhun_transport_fixture', ROOT / 'tests/ext-enqueue.py')
    transport = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(transport)
    windows = bool(args.wine) or os.name == 'nt' or args.build_only and args.exe.suffix.lower() == '.exe'
    platform = 'windows' if windows else 'macos' if sys.platform == 'darwin' else 'linux'
    with tempfile.TemporaryDirectory(prefix='rhun-flush-fault-') as temporary:
        executable = (args.exe.resolve() if args.exe and not args.build_only
                      else transport.fault_fixture(platform, Path(temporary), 'flush'))
        if args.build_only:
            destination = args.exe.resolve()
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(executable, destination)
            print('built bounded flush fixture: ' + str(destination), flush=True)
            return
        command = [args.wine, 'Z:' + executable.as_posix()] if args.wine else [executable]
        result = transport.run(command)
        expected = (ROOT / 'tests/data/ext-flush.expected').read_bytes()
        if result.stdout + result.stderr != expected:
            raise AssertionError('flush fixture output: ' + repr((result.stdout + result.stderr)[:4000]))
    print('ok   bounded flush interruptions, quotas, backpressure and native failures', flush=True)


if __name__ == '__main__':
    main()
