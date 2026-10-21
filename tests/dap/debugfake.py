#!/usr/bin/env python3
"""The fake debugger extension's own program (tests/dap/exts/rhun-tests/debugfake). What it does
comes from $RHUN_STATE/mode.json, which the test writes: {"features": "debug", "start": [requests],
"resolve": answer}. A request is {"name": N, "leaves": [[KIND, PATH, VALUE], ...]} or {"raw": BODY}.
Running its `start` command sends the next debug-start (all of them with "burst": true); every line
rhun sends is logged to $RHUN_STATE/debugfake.log."""
import json
import os
import sys

STATE = os.environ.get('RHUN_STATE', '.')
try:
    with open(os.path.join(STATE, 'mode.json'), encoding='utf-8') as f:
        MODE = json.load(f)
except OSError:
    MODE = {}
LOG = os.path.join(STATE, 'debugfake.log')
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = [1]
starts = list(MODE.get('start', []))


def log(text):
    with open(LOG, 'a', encoding='utf-8') as f:
        f.write(text + '\n')


def body_of(leaves):
    parts = [b'%d\n' % len(leaves)]
    for kind, path, value in leaves:
        p = path.encode()
        v = str(value).encode()
        parts.append(b'%s %d %d\n' % (kind.encode(), len(p), len(v)) + p + v)
    return b''.join(parts)


def debug_start(req):
    name = req.get('name', 'From the extension').encode()
    body = req['raw'].encode() if 'raw' in req else body_of(req.get('leaves', []))
    rid = next_id[0]
    next_id[0] += 1
    out.write(b'%d debug-start %d %d\n' % (rid, len(name), len(name) + len(body)) + name + body)
    out.flush()
    log('sent debug-start %d' % rid)


def parse_body(body):
    lines = body.split(b'\n', 1)
    n, rest = int(lines[0]), lines[1]
    leaves = []
    for _ in range(n):
        head, rest = rest.split(b'\n', 1)
        kind, pl, vl = head.split(b' ')
        pl, vl = int(pl), int(vl)
        leaves.append([kind.decode(), rest[:pl].decode(), rest[pl:pl + vl].decode()])
        rest = rest[pl + vl:]
    return leaves, rest


def resolve(rid, body):
    how = MODE.get('resolve', 'unchanged')
    if how == 'unchanged':
        out.write(b'ok %d 0\n' % rid)
    elif how == 'cancel':
        out.write(b'error %d cancelled the user dismissed it\n' % rid)
    elif how == 'refuse':
        out.write(b'error %d refused no Go package in this folder\n' % rid)
    elif how == 'silent':
        return
    elif how == 'crash':
        sys.exit(1)
    elif how == 'garbage':
        out.write(b'ok %d 5\nnope!' % rid)
    else:
        leaves, _ = parse_body(body)
        for path in how.get('remove', []):
            leaves = [l for l in leaves if l[1] != path and not l[1].startswith(path + '.')]
        for kind, path, value in how.get('set', []):
            leaves = [l for l in leaves if l[1] != path] + [[kind, path, value]]
        b = body_of(leaves)
        out.write(b'ok %d %d\n' % (rid, len(b)) + b)
    out.flush()


def main():
    features = MODE.get('features', 'debug')
    out.write(('hello 1 %s\n' % features).strip().encode() + b'\n')
    out.flush()
    while True:
        line = inp.readline()
        if not line:
            break
        text = line.decode('utf-8', 'replace').rstrip('\n')
        log(text)
        fields = text.split(' ')
        if text.startswith('0 bye'):
            break
        if len(fields) == 6 and fields[1] == 'debug-resolve':
            body = inp.read(int(fields[5]))
            log('BODY ' + json.dumps(body.decode('utf-8', 'replace')))
            resolve(int(fields[0]), body)
            continue
        if fields[:2] == ['0', 'run'] and len(fields) > 2 and fields[2].split('.')[-1] == 'start':
            if MODE.get('burst'):
                while starts:
                    debug_start(starts.pop(0))
            elif starts:
                debug_start(starts.pop(0))


if __name__ == '__main__':
    main()
