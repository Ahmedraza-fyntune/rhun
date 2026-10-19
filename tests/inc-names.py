#!/usr/bin/env python3
"""A constant or struct field defined twice in src/rhun.inc silently takes the later value in every
file (GNU as and clang let .equ be redefined): GL_SIZE once changed the font cache's entry size.
Fails when src/rhun.inc defines a name twice. A file that redefines one of its names for itself is
listed as a note (that file's later uses get its own value)."""
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEF = re.compile(r'^\s*(?:\.equ|F|ENDSTRUCT|\.set)\s+([A-Za-z_][A-Za-z0-9_]*)', re.M)
inc = (ROOT / 'src/rhun.inc').read_text(errors='replace')
names = [n for n in DEF.findall(inc) if not n.startswith('__')]
bad = [f'src/rhun.inc defines {n} {c} times' for n, c in Counter(names).items() if c > 1]
known = set(names)
for p in sorted(ROOT.glob('src/**/*.s')) + sorted(ROOT.glob('src/**/*.inc')):
    text = p.read_text(errors='replace')
    if p.name == 'rhun.inc' or 'rhun.inc' not in text:
        continue
    for n in DEF.findall(text):
        if n in known:
            print(f'note: {p.relative_to(ROOT)} redefines {n} from src/rhun.inc for itself')
for line in bad:
    print(line)
print('ok' if not bad else f'{len(bad)} redefinitions')
sys.exit(1 if bad else 0)
