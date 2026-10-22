#!/usr/bin/env python3
"""Native broker reference ownership, aliases and released adapter slot reuse."""
import os
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_WATCH_NATIVE_EXE', ROOT / ('build/windows/ext_watch_test.exe' if os.name == 'nt' else 'build/ext_watch_test')))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--wine')
    args = parser.parse_args()
    runner = [args.wine] if args.wine else []
    def native(path):
        return ('Z:' + str(path)) if args.wine else str(path)
    with tempfile.TemporaryDirectory(prefix='rhun-watch-native-') as tmp:
        folder = Path(tmp).resolve()
        watched = folder / 'watched'
        watched.mkdir()
        alias = folder / 'alias'
        try:
            alias.symlink_to(watched, target_is_directory=True)
        except OSError:
            alias = watched
        broken = folder / 'overfull'
        broken.mkdir()
        for index in range(4097):
            (broken / str(index)).touch()
        env = dict(os.environ, XDG_CONFIG_HOME=str(folder / 'config'))
        result = subprocess.run([*runner, native(EXE), native(watched), native(alias), native(broken), native(folder / 'original')], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
        assert result.stdout == b'ok shared native watchers\n', result.stdout
        print(result.stdout.decode(), end='')


if __name__ == '__main__':
    main()
