#!/usr/bin/env python3
"""Fuzzing of the WebAssembly decoder, validator and instantiation (src/wasm): valid modules are
mutated (bits flipped, bytes changed, inserted, removed, numbers rewritten, the end cut off) and
loaded by `rhun --wasm-spec`, which must answer every one (ok, error or trap) and exit cleanly.
With wabt's wasm-validate on PATH, every module rhun accepts must be valid to it too, and every
module rhun calls malformed or invalid must be invalid to it.

The corpus: a few modules written here, plus the spec suite's (build/wasm-spec/work, written by
tests/wasm-spec.py) and the test extensions' (build/wasm-ext) when they are there.
usage: tests/wasm-fuzz.py [FIRST_SEED] [LAST_SEED] [--count N]"""
import argparse
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()

# small modules (wat2wasm of tests/wasm/fuzz/h1.wat and h2.wat): imports, memory, table, a mutable
# global, loops and branches, call_indirect, element and data segments, a start function;
# multi-value blocks, externref, a passive data segment with memory.init and data.drop
HAND = [
    bytes.fromhex('0061736d01000000010d0360017f017f60017f00600000021601087370656374657374097072696e74'
                  '5f693332000103030200020404017000020504010101020606017f0141070b0705010166000108010209'
                  '08010041000b0201010a35023002017e017c027f034020004541030d01200041016b2100230041002d0008'
                  '6a24000c000b41090b41011100001a23000b02000b0b08010041080b026869'),
    bytes.fromhex('0061736d01000000010f0360027c7e027c7e6000016f6000000304030001020404016f00010503010001'
                  '070501016700000c01010a26030f0020009f2001420581410104000b0b0400d06f0b0f00410041004101'
                  'fc080000fc09000b0b0a01010770617373697665'),
]
# messages of loads that failed for reasons other than the module itself
LINK = ('unknown import', 'incompatible import type', 'memory too large', 'table too large')


def corpus():
    mods = [m for m in HAND]
    for d in (ROOT / 'build/wasm-spec/work', ROOT / 'build/wasm-ext'):
        if d.is_dir():
            for p in sorted(d.rglob('*.wasm')):
                if p.stat().st_size < 300000:
                    mods.append(p.read_bytes())
    return mods


def leb(v):
    out = bytearray()
    while True:
        b = v & 0x7f
        v >>= 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def mutate(rng, data):
    b = bytearray(data)
    for _ in range(rng.choice((1, 1, 1, 2, 3, 5))):
        if not b:
            break
        k = rng.randrange(7)
        i = rng.randrange(len(b))
        if k == 0:
            b[i] ^= 1 << rng.randrange(8)
        elif k == 1:
            b[i] = rng.choice((0, 0x7f, 0x80, 0xff, 0x40, 0x0b, 0x41, 0x6f, 0x70, 0x7b, rng.randrange(256)))
        elif k == 2:
            b.insert(i, rng.randrange(256))
        elif k == 3:
            del b[i]
        elif k == 4:
            b[i:i + 1] = leb(rng.choice((0, 1, 127, 128, 0xffffffff, 1 << 31, rng.randrange(1 << 20))))
        elif k == 5 and len(b) > 9:
            del b[rng.randrange(8, len(b)):]
        else:
            j = rng.randrange(len(b))
            b[i:i] = b[j:j + rng.randrange(1, 16)]
    return bytes(b)


def run(seed, count, mods, work, validate):
    rng = random.Random(seed)
    lines, files = [], []
    for k in range(count):
        m = mutate(rng, rng.choice(mods))
        f = work / ('m%d.wasm' % k)
        f.write_bytes(m)
        files.append(f)
        lines.append('module - %s' % f.name)
    script = work / 'fuzz.script'
    script.write_text('\n'.join(lines) + '\n')
    try:
        r = subprocess.run([str(EXE), '--wasm-spec', script.name], cwd=work, capture_output=True, timeout=120)
    except subprocess.TimeoutExpired:
        return ['seed %d: timed out' % seed]
    out = r.stdout.decode(errors='replace').splitlines()
    problems = []
    if r.returncode != 0 or len(out) != count:
        keep = work.parent / ('crash-%d' % seed)
        shutil.copytree(work, keep, dirs_exist_ok=True)
        problems.append('seed %d: exit %d after %d of %d answers (kept in %s)' % (seed, r.returncode, len(out), count, keep))
        return problems
    for f, answer in zip(files, out):
        if not (answer == 'ok' or answer.startswith('error ') or answer.startswith('trap ')):
            problems.append('seed %d %s: %s' % (seed, f.name, answer))
            continue
        if validate is None or answer.startswith('trap ') or any(x in answer for x in LINK):
            continue
        v = subprocess.run([validate, '--disable-simd', str(f)], capture_output=True)
        theirs = v.returncode == 0
        if theirs != (answer == 'ok'):
            keep = work.parent / ('diff-%d-%s' % (seed, f.name))
            shutil.copy(f, keep)
            problems.append('seed %d %s: rhun %s, wasm-validate %s (kept as %s)' % (
                seed, f.name, answer, 'valid' if theirs else v.stderr.decode(errors='replace').strip()[:120], keep))
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('first', nargs='?', type=int, default=1)
    ap.add_argument('last', nargs='?', type=int, default=8)
    ap.add_argument('--count', type=int, default=200)
    args = ap.parse_args()
    validate = shutil.which('wasm-validate')
    mods = corpus()
    problems = []
    with tempfile.TemporaryDirectory(prefix='rhun-wasm-fuzz-') as tmp:
        for seed in range(args.first, args.last + 1):
            work = Path(tmp) / ('s%d' % seed)
            work.mkdir()
            problems += run(seed, args.count, mods, work, validate)
            shutil.rmtree(work)
        for p in problems[:50]:
            print(p)
        if problems:
            # what was kept goes with the report
            keep = ROOT / 'build/wasm-fuzz'
            keep.mkdir(parents=True, exist_ok=True)
            for p in Path(tmp).iterdir():
                dest = keep / p.name
                if p.is_dir():
                    shutil.copytree(p, dest, dirs_exist_ok=True)
                else:
                    shutil.copy(p, dest)
    n = (args.last - args.first + 1) * args.count
    print('wasm fuzz: %d modules from %d, %d problems%s' % (n, len(mods), len(problems),
                                                           '' if validate else ' (no wasm-validate: no differential check)'))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
