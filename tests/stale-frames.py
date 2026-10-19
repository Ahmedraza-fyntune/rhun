#!/usr/bin/env python3
"""Runs headless tests with rhun's frame probes on (src/plat/headless.s) and reports what they log.

RHUN_STALE: after a frame that asked for no other, rhun draws the frame again and compares; a
difference means some state changed during the frame without g_dirty, so the screen would stay
wrong until an unrelated event. RHUN_UNDERPAINT: the buffer is filled with magenta before each
frame; pixels a frame leaves magenta were never painted.

usage: tests/stale-frames.py [--all] [--keep DIR] [TEST.py ...]
With no tests: the presentation tests. --all: every tests/*.py that runs rhun headless. A stale
frame whose app_timeout() is short (below 100 ms) is an animation, counted but not a failure;
"never" or a longer one (the caret's blink) is a missing frame and fails, as does any underpaint.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ['presentation.py']


def main():
    args = sys.argv[1:]
    keep = None
    if '--keep' in args:
        i = args.index('--keep')
        keep = Path(args[i + 1])
        del args[i:i + 2]
    tests = args
    if '--all' in tests:
        tests = sorted(p.name for p in (ROOT / 'tests').glob('*.py')
                       if '--headless' in p.read_text(errors='replace') and p.name != 'stale-frames.py')
    if not tests:
        tests = DEFAULT
    logs = keep or Path(tempfile.mkdtemp(prefix='rhun-stale-'))
    logs.mkdir(parents=True, exist_ok=True)
    bad = 0
    for name in tests:
        stem = Path(name).stem
        stale, under = logs / (stem + '.stale'), logs / (stem + '.under')
        for p in (stale, under):
            if p.exists():
                p.unlink()
        env = dict(os.environ, RHUN_STALE=str(stale), RHUN_UNDERPAINT=str(under))
        try:
            r = subprocess.run([sys.executable, str(ROOT / 'tests' / name)], env=env, cwd=ROOT,
                               capture_output=True, timeout=3600)
            status = 'ok' if r.returncode == 0 else 'test failed'
        except subprocess.TimeoutExpired:
            status = 'timed out'
        missing, anim = [], 0
        for line in (stale.read_text(errors='replace').splitlines() if stale.exists() else []):
            t = line.rsplit('timeout ', 1)[-1].strip()
            if t != 'never' and t.isdigit() and int(t) < 100:
                anim += 1
            else:
                missing.append(line)
        unpainted = under.read_text(errors='replace').splitlines() if under.exists() else []
        print(f'{name}: {status}, {len(missing)} missing frames, {anim} animation frames, '
              f'{len(unpainted)} underpainted')
        for line in missing[:20] + unpainted[:20]:
            print('   ', line)
        bad += len(missing) + len(unpainted)
    print(f'logs in {logs}')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
