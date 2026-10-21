#!/usr/bin/env python3
"""A fake language provider for notebook cells (docs/extensions/v1.1.md, "Cells for language
providers"), standard library only. It agrees notebooks, logs every line rhun sends to the file
CELLFAKE_LOG names (in its state folder), and answers completion with one item, "cell_item", plus the
text of the line it was asked in, which it reads with a text request."""
import os
import sys

LOG = os.environ.get('CELLFAKE_LOG')
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = [1]
waiting = {}


def log(line):
    if LOG:
        with open(LOG, 'ab') as f:
            f.write(line + b'\n')


def send(line, body=b''):
    out.write(line.encode() + b'\n' + body)
    out.flush()


def read_exact(n):
    data = b''
    while len(data) < n:
        chunk = inp.read(n - len(data))
        if not chunk:
            break
        data += chunk
    return data


def main():
    send('hello 1 notebooks complete')
    while True:
        line = inp.readline()
        if not line:
            return
        line = line.rstrip(b'\n')
        log(line)
        f = line.split(b' ')
        body = b''
        if f[0] == b'0' and len(f) >= 2 and f[1] == b'edits':
            body = read_exact(int(f[-1]))
        if f[0] == b'ok' and len(f) >= 3 and int(f[1]) in waiting:
            text = read_exact(int(f[3]))
            log(b'text ' + text.replace(b'\n', b'|'))
            rid, ln, col = waiting.pop(int(f[1]))
            label = b'cell_item'
            item = b'%d %d %d %d function %d %d 0 0\n' % (ln, col, ln, col, len(label), len(label)) + label + label
            reply = b'1 0\n' + item
            send(f'ok {rid} {len(reply)}', reply)
            continue
        if f[0] in (b'ok', b'error'):
            continue
        if f[0] != b'0' and len(f) >= 2 and f[1] == b'complete':
            rid, doc, ln, col = f[0].decode(), int(f[2]), int(f[4]), int(f[5])
            tid = next_id[0]
            next_id[0] += 1
            waiting[tid] = (rid, ln, col)
            send(f'{tid} text {doc}')
            continue
        if f[0] != b'0':
            send(f'error {f[0].decode()} unknown')
            continue
        if f[1] == b'bye':
            return


main()
