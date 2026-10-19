#!/usr/bin/env python3
# Source patterns GNU as (Linux, Intel syntax) reads differently from tools/arm64.py (macOS), so a
# macOS build passes while Linux fails or jumps elsewhere:
#  - a local label with a leading zero (`01:`, `jns 01f`): GNU as rejects it; the translator reads
#    it as `1:`, so the jump lands on the next `1:` instead;
#  - a symbol named like an operand size keyword (`word`, `byte`, `dword`, ...): `call word` is a
#    call to address 2 on Linux.
# usage: tests/asm-pitfalls.py [--negative-control]
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KEYWORDS = {'byte', 'word', 'dword', 'qword', 'tbyte', 'oword', 'xword', 'xmmword', 'ymmword',
            'zmmword', 'fword', 'ptr', 'offset', 'flat'}
LABEL0 = re.compile(r'^\s*0[0-9]+:')
REF0 = re.compile(r'(?<![0-9A-Za-z_.$])0[0-9]+[fb]\b')
DEF = re.compile(r'^\s*(?:FN\s+([A-Za-z_][A-Za-z0-9_]*)|([A-Za-z_][A-Za-z0-9_]*):)')
CALL = re.compile(r'^\s*(?:call|jmp|j[a-z]{1,3})\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:#.*)?$')

def files():
    for f in sorted(ROOT.glob('src/**/*.s')) + sorted(ROOT.glob('src/**/*.inc')):
        if 'src/mac/' in f.as_posix():
            continue        # native arm64, assembled by clang
        yield f

def check(extra=None):
    bad = []
    sources = [(f.relative_to(ROOT), f.read_text(errors='replace')) for f in files()]
    if extra:
        sources.append(extra)
    for name, text in sources:
        for n, line in enumerate(text.splitlines(), 1):
            code = line.split('#', 1)[0]
            if re.match(r'^\s*\.(byte|word|long|quad|ascii|asciz|int|short|octa)\b', code):
                continue
            if LABEL0.match(code) or (REF0.search(code) and not re.search(r'0x', code)):
                bad.append(f'{name}:{n}: a local label with a leading zero: {line.strip()}')
            m = DEF.match(code)
            if m and (m.group(1) or m.group(2)).lower() in KEYWORDS:
                bad.append(f'{name}:{n}: a symbol named like a size keyword: {line.strip()}')
            m = CALL.match(code)
            if m and m.group(1).lower() in KEYWORDS:
                bad.append(f'{name}:{n}: a jump to a size keyword: {line.strip()}')
    return bad

if __name__ == '__main__':
    if '--negative-control' in sys.argv:
        planted = check(('negative-control', '    jns 01f\n01: ret\nword:\n    call word\n'))
        if len(planted) < 4:
            print('FAIL negative control: planted pitfalls went unnoticed', planted)
            sys.exit(1)
    bad = check()
    for b in bad:
        print('FAIL ' + b)
    if bad:
        sys.exit(1)
    print('ok   no leading-zero local labels or size-keyword symbols')
