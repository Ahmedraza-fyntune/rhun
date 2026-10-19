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
        if fields[:2] == ['0', 'run'] and len(fields) > 2 and fields[2].split('.')[-1] == 'start':
            if MODE.get('burst'):
                while starts:
                    debug_start(starts.pop(0))
            elif starts:
                debug_start(starts.pop(0))


if __name__ == '__main__':
    main()
