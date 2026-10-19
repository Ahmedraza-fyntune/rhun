#!/usr/bin/env python3
"""The WebAssembly core specification tests (release 2.0: the MVP with sign extension,
non-trapping float-to-int, multi-value, bulk memory and reference types; SIMD is not supported)
run against rhun's interpreter, `rhun --wasm-spec`.

The .wast files come from https://github.com/WebAssembly/spec at tag wg-2.0 (fetched into
build/wasm-spec, or --spec-dir); wabt's wast2json turns them into binary modules and commands,
which this script writes as rhun's line-based scripts (src/wasm/wasmspec.s) and checks the answers
of. Text-format modules of assert_malformed are skipped: rhun reads binaries only.

  tests/wasm-spec.py [--rhun build/rhun] [--spec-dir DIR] [--only NAME...] [--prepare DIR] [--check DIR]

--prepare writes the scripts and modules to DIR without running them (for a run elsewhere: Linux
in Docker, Windows under Wine, each SCRIPT answered into SCRIPT.out); --check compares those
answers."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
TAG = 'wg-2.0'
SKIP = ('simd_',)


def fetch(spec_dir):
    core = spec_dir / 'test' / 'core'
    if core.is_dir():
        return core
    spec_dir.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['git', 'clone', '-q', '--depth', '1', '--branch', TAG, '--filter=blob:none',
                    '--sparse', 'https://github.com/WebAssembly/spec', str(spec_dir)], check=True)
    subprocess.run(['git', '-C', str(spec_dir), 'sparse-checkout', 'set', 'test/core'], check=True)
    return core


def hexname(s):
    return 'x' + s.encode('utf-8').hex()


def value_arg(v):
    t, val = v['type'], v.get('value')
    if t in ('funcref', 'externref'):
        if val == 'null':
            return t + ':null'
        return '%s:%x' % (t, int(val))
    return '%s:%x' % (t, int(val))


class Check:
    def __init__(self, line, kind, expected=None, text=None):
        self.line, self.kind, self.expected, self.text = line, kind, expected, text


def convert(wast, out):
    """wast -> (script path, checks)"""
    name = wast.stem
    d = out / name
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    subprocess.run(['wast2json', str(wast), '-o', str(d / (name + '.json'))],
                   check=True, stdout=subprocess.DEVNULL)
    data = json.loads((d / (name + '.json')).read_text(encoding='utf-8'))
    lines, checks = [], []

    def mod(c):
        return c.get('name', '-') if 'name' in c else '-'

    def action(a):
        m = a.get('module', '-')
        if a['type'] == 'invoke':
            return 'invoke %s %s %s' % (m, hexname(a['field']), ' '.join(value_arg(x) for x in a.get('args', [])))
        return 'get %s %s' % (m, hexname(a['field']))

    for c in data['commands']:
        t, line = c['type'], c['line']
        if t == 'module':
            lines.append('module %s %s' % (mod(c), c['filename']))
            checks.append(Check(line, 'ok'))
        elif t == 'register':
            lines.append('register %s %s' % (hexname(c['as']), c.get('name', '-')))
            checks.append(Check(line, 'ok'))
        elif t == 'action':
            lines.append(action(c['action']))
            checks.append(Check(line, 'ok-any'))
        elif t == 'assert_return':
            lines.append(action(c['action']))
            checks.append(Check(line, 'return', c['expected']))
        elif t in ('assert_trap', 'assert_exhaustion'):
            if 'action' not in c:
                lines.append('module - %s' % c['filename'])
                checks.append(Check(line, 'trap', text=c.get('text')))
                continue
            lines.append(action(c['action']))
            checks.append(Check(line, 'trap', text=c.get('text')))
        elif t in ('assert_invalid', 'assert_malformed', 'assert_unlinkable'):
            if c.get('module_type') == 'text':
                continue
            lines.append('module - %s' % c['filename'])
            checks.append(Check(line, 'error', text=c.get('text')))
        elif t == 'assert_uninstantiable':
            lines.append('module - %s' % c['filename'])
            checks.append(Check(line, 'trap', text=c.get('text')))
        else:
            raise SystemExit('%s:%d: unknown command %s' % (wast, line, t))
    script = d / (name + '.script')
    script.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return script, checks


def nan_ok(t, bits, kind):
    if t == 'f32':
        if kind == 'nan:canonical':
            return bits & 0x7fffffff == 0x7fc00000
        return bits & 0x7fc00000 == 0x7fc00000
    if kind == 'nan:canonical':
        return bits & 0x7fffffffffffffff == 0x7ff8000000000000
    return bits & 0x7ff8000000000000 == 0x7ff8000000000000


def value_ok(exp, got):
    t = exp['type']
    if ':' not in got:
        return False
    gt, gv = got.split(':', 1)
    if gt != t:
        return False
    v = exp.get('value')
    if t in ('funcref', 'externref'):
        if v == 'null':
            return gv == 'null'
        if t == 'funcref':
            return gv != 'null'
        return gv != 'null' and int(gv, 16) == int(v)
    if t in ('f32', 'f64') and isinstance(v, str) and v.startswith('nan:'):
        return nan_ok(t, int(gv, 16), v)
    return int(gv, 16) == int(v)


def compare(name, checks, out_lines):
    failures = []
    for i, c in enumerate(checks):
        got = out_lines[i] if i < len(out_lines) else '(no answer: the run ended)'
        ok = False
        if c.kind == 'ok':
            ok = got == 'ok'
        elif c.kind == 'ok-any':
            ok = got.startswith('ok')
        elif c.kind == 'return':
            parts = got.split()
            ok = parts[:1] == ['ok'] and len(parts) - 1 == len(c.expected) and \
                all(value_ok(e, g) for e, g in zip(c.expected, parts[1:]))
        elif c.kind == 'trap':
            # the spec's message (the reference interpreter adds details, like an index, after it)
            ok = got.startswith('trap') and (not c.text or got[5:].startswith(c.text) or
                                             c.text.startswith(got[5:]))
        elif c.kind == 'error':
            ok = got.startswith('error') or got.startswith('trap')
        if not ok:
            want = c.kind
            if c.expected is not None:
                want += ' ' + json.dumps(c.expected)
            if c.text:
                want += ' (%s)' % c.text
            failures.append('%s.wast:%d: want %s, got %s' % (name, c.line, want, got))
    return failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rhun', default=str(ROOT / 'build' / 'rhun'))
    ap.add_argument('--spec-dir', default=str(ROOT / 'build' / 'wasm-spec' / 'spec'))
    ap.add_argument('--work', default=str(ROOT / 'build' / 'wasm-spec' / 'work'))
    ap.add_argument('--only', nargs='*')
    ap.add_argument('--prepare')
    ap.add_argument('--check')
    ap.add_argument('--verbose', '-v', action='store_true')
    args = ap.parse_args()
    if shutil.which('wast2json') is None and not args.check:
        raise SystemExit('wast2json (wabt) is needed: brew install wabt, apt install wabt')
    core = fetch(Path(args.spec_dir))
    work = Path(args.prepare or args.check or args.work)
    wasts = sorted(p for p in core.glob('*.wast') if not p.name.startswith(SKIP))
    if args.only:
        wasts = [p for p in wasts if p.stem in args.only]
    total = passed = 0
    all_failures = []
    for wast in wasts:
        if args.check:
            script = work / wast.stem / (wast.stem + '.script')
            _, checks = convert_checks_only(wast, work)
        else:
            script, checks = convert(wast, work)
        if args.prepare:
            continue
        if args.check:
            outp = Path(str(script) + '.out')
            out = outp.read_text(encoding='utf-8', errors='replace') if outp.exists() else ''
        else:
            try:
                r = subprocess.run([args.rhun, '--wasm-spec', script.name], capture_output=True, timeout=600,
                                   cwd=script.parent)
                out = r.stdout.decode('utf-8', 'replace')
                if r.returncode != 0:
                    out += '\n(exit %d: %s)' % (r.returncode, r.stderr.decode('utf-8', 'replace')[-500:])
            except subprocess.TimeoutExpired as e:
                out = (e.stdout or b'').decode('utf-8', 'replace') + '\n(timed out)'
        fails = compare(wast.stem, checks, out.splitlines())
        total += len(checks)
        passed += len(checks) - len(fails)
        all_failures += fails
        if args.verbose or fails:
            print('%-28s %5d/%d' % (wast.stem, len(checks) - len(fails), len(checks)))
    if args.prepare:
        print('prepared', len(wasts), 'scripts in', work)
        return 0
    for f in all_failures[:200]:
        print(f)
    print('wasm spec: %d/%d passed in %d files' % (passed, total, len(wasts)))
    return 0 if passed == total else 1


def convert_checks_only(wast, work):
    # the checks of a prepared directory, read again from its JSON (the modules are already there)
    d = work / wast.stem
    data = json.loads((d / (wast.stem + '.json')).read_text(encoding='utf-8'))
    checks = []
    for c in data['commands']:
        t, line = c['type'], c['line']
        if t == 'module' or t == 'register':
            checks.append(Check(line, 'ok'))
        elif t == 'action':
            checks.append(Check(line, 'ok-any'))
        elif t == 'assert_return':
            checks.append(Check(line, 'return', c['expected']))
        elif t in ('assert_trap', 'assert_exhaustion', 'assert_uninstantiable'):
            checks.append(Check(line, 'trap', text=c.get('text')))
        elif t in ('assert_invalid', 'assert_malformed', 'assert_unlinkable'):
            if c.get('module_type') == 'text':
                continue
            checks.append(Check(line, 'error', text=c.get('text')))
    return None, checks


if __name__ == '__main__':
    sys.exit(main())
