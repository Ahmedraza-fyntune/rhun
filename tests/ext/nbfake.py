#!/usr/bin/env python3
"""A fake notebook extension for the host tests (docs/extensions/v1.1.md, "Feature: notebooks"),
standard library only. It reads and writes .nbt files, a line-based toy format:

    %% notebook META          the notebook's metadata (optional, first line)
    %% code LANG COUNT        a code cell (COUNT - for none); its source is the lines up to the next %%
    %% markup                 a markup cell
    %% out KIND TYPE OUTID    an output of the cell before (TYPE text, ansi or png; png is base64)

and runs cells by what their source says: "sleep" waits until interrupted, "error" fails with a
traceback, "png" shows an image, "many" prints 1000 lines, "progress" draws over its line with
carriage returns, "clearwait" replaces its output, "replace" updates a display by its id, "stale"
answers for an old run, "toobig" streams past the cap; anything else is echoed. NBFAKE_LOG names a
file that receives every line rhun sends and every answer to the fake's requests. NBFAKE_MODE:
openerror, badbody, slowopen, nofeature, saveerror, noread.
"""
import base64
import os
import queue
import struct
import sys
import threading
import time
import zlib

MODE = os.environ.get('NBFAKE_MODE', '')
LOG = os.environ.get('NBFAKE_LOG')
out = sys.stdout.buffer
inp = sys.stdin.buffer
lock = threading.Lock()
next_id = [1]
counter = [0]
interrupted = threading.Event()
runs = queue.Queue()
latest = {}                     # (nb, cell) -> latest run id
choosing = {}                   # choose request id -> notebook


def log(line):
    if LOG:
        with open(LOG, 'ab') as f:
            f.write(line + b'\n')


def send(line, body=b''):
    with lock:
        out.write(line.encode() + b'\n' + body)
        out.flush()


def request(verb_and_args, body=b''):
    with lock:
        rid = next_id[0]
        next_id[0] += 1
    send(f'{rid} {verb_and_args}', body)
    return rid


def png(w, h, rgba):
    raw = b''.join(b'\x00' + bytes(rgba) * w for _ in range(h))

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


# ---------- the toy format <-> notebook bodies ----------

def parse_nbt(data):
    meta = b''
    cells = []
    for block in data.split(b'%% ')[1:]:
        head, _, rest = block.partition(b'\n')
        if rest.endswith(b'\n'):
            rest = rest[:-1]
        f = head.split(b' ')
        if f[0] == b'notebook':
            meta = head[len(b'notebook '):]
        elif f[0] in (b'code', b'markup'):
            lang = f[1] if f[0] == b'code' and len(f) > 1 else b'-'
            count = f[2] if f[0] == b'code' and len(f) > 2 else b'-'
            cells.append({'kind': f[0], 'lang': lang, 'count': count, 'source': rest, 'meta': b'', 'outs': []})
        elif f[0] == b'out':
            kind, typ, oid = f[1], f[2], f[3] if len(f) > 3 else b'-'
            if typ == b'png':
                item = (b'png', base64.b64decode(rest))
            else:
                item = (typ, rest + b'\n' if rest else b'')
            cells[-1]['outs'].append({'kind': kind, 'id': oid, 'keep': b'%% ' + head + b'\n' + rest + b'\n',
                                      'items': [item]})
    return meta, cells


def body_of(meta, cells):
    b = b'%d %d\n%s' % (len(cells), len(meta), meta)
    for c in cells:
        b += b'%s %s %s %d %d %d\n%s%s' % (c['kind'], c['lang'], c['count'], len(c['source']), len(c['meta']),
                                            len(c['outs']), c['source'], c['meta'])
        for o in c['outs']:
            b += output_body(o)
    return b


def output_body(o):
    b = b'%s %s %d %d\n%s' % (o['kind'], o['id'], len(o['keep']), len(o['items']), o['keep'])
    for typ, data in o['items']:
        b += b'%s 0 0 %d\n%s' % (typ, len(data), data)
    return b


class Reader:
    def __init__(self, data):
        self.d, self.p = data, 0

    def line(self):
        e = self.d.index(b'\n', self.p)
        f = self.d[self.p:e].split(b' ')
        self.p = e + 1
        return f

    def take(self, n):
        b = self.d[self.p:self.p + n]
        if len(b) != n:
            raise ValueError('short')
        self.p += n
        return b


def read_body(data):
    r = Reader(data)
    n, ml = map(int, r.line())
    meta = r.take(ml)
    cells = []
    for _ in range(n):
        kind, lang, count, sl, mlen, nout = r.line()
        c = {'kind': kind, 'lang': lang, 'count': count, 'source': r.take(int(sl)), 'meta': r.take(int(mlen)), 'outs': []}
        for _ in range(int(nout)):
            okind, oid, kl, ni = r.line()
            o = {'kind': okind, 'id': oid, 'keep': r.take(int(kl)), 'items': []}
            for _ in range(int(ni)):
                typ, w, h, ln = r.line()
                o['items'].append((typ, r.take(int(ln))))
            c['outs'].append(o)
        cells.append(c)
    return meta, cells


def nbt_of(meta, cells):
    out_ = b''
    if meta:
        out_ += b'%% notebook ' + meta + b'\n'
    for c in cells:
        if c['kind'] == b'code':
            out_ += b'%% code ' + c['lang'] + b' ' + c['count'] + b'\n' + c['source'] + b'\n'
        else:
            out_ += b'%% markup\n' + c['source'] + b'\n'
        for o in c['outs']:
            if o['keep']:
                out_ += o['keep']
            else:
                typ, data = o['items'][0]
                if data.endswith(b'\n'):
                    data = data[:-1]
                out_ += b'%% out ' + o['kind'] + b' ' + typ + b' ' + o['id'] + b'\n' + data + b'\n'
    return out_


# ---------- runs ----------

def state(nb, cell, run, st, count='-'):
    request(f'nb-state {nb} {cell} {run} {st} {count}')


def stream(nb, cell, run, name, data):
    request(f'nb-stream {nb} {cell} {run} {name} {len(data)}', data)


def output(nb, cell, run, op, target, body):
    request(f'nb-output {nb} {cell} {run} {op} {target} {len(body)}', body)


def worker():
    while True:
        nb, cell, run, source = runs.get()
        if latest.get((nb, cell)) != run:
            continue
        interrupted.clear()
        state(nb, cell, run, 'running')
        counter[0] += 1
        n = counter[0]
        if b'sleep' in source:
            stream(nb, cell, run, 'stdout', b'started\n')
            interrupted.wait(30)
            stream(nb, cell, run, 'stderr', b'KeyboardInterrupt\n')
            state(nb, cell, run, 'failed', n)
            continue
        if b'error' in source:
            tb = b'\x1b[0;31mValueError\x1b[0m: bad value\nTraceback line\n'
            output(nb, cell, run, 'append', '-', output_body({'kind': b'error', 'id': b'-', 'keep': b'',
                                                              'items': [(b'ansi', tb)]}))
            state(nb, cell, run, 'failed', n)
            continue
        if b'png' in source:
            image = png(40, 20, (0, 200, 0, 255))
            output(nb, cell, run, 'append', '-', output_body({'kind': b'display', 'id': b'-', 'keep': b'',
                                                              'items': [(b'png', image), (b'text', b'<Figure>\n')]}))
        elif b'many' in source:
            stream(nb, cell, run, 'stdout', b''.join(b'line %d\n' % i for i in range(1000)))
        elif b'progress' in source:
            stream(nb, cell, run, 'stdout', b'10%')
            stream(nb, cell, run, 'stdout', b'\r20%')
            stream(nb, cell, run, 'stdout', b'\r30%\ndone\n')
        elif b'clearwait' in source:
            stream(nb, cell, run, 'stdout', b'first\n')
            output(nb, cell, run, 'clear-wait', '-', b'')
            stream(nb, cell, run, 'stdout', b'second\n')
        elif b'replace' in source:
            output(nb, cell, run, 'append', '-', output_body({'kind': b'display', 'id': b'd1', 'keep': b'',
                                                              'items': [(b'text', b'old\n')]}))
            output(nb, cell, run, 'replace', 'd1', output_body({'kind': b'display', 'id': b'd1', 'keep': b'',
                                                                'items': [(b'text', b'new\n')]}))
        elif b'colors' in source:
            stream(nb, cell, run, 'stdout', b'\x1b[1;32mgreen\x1b[0m plain \x1b[38;5;196mred\x1b[0m\n')
        elif b'toobig' in source:
            chunk = b'x' * 65536
            for _ in range(300):
                stream(nb, cell, run, 'stdout', chunk)
        else:
            stream(nb, cell, run, 'stdout', b'echo: ' + source + b'\n')
        state(nb, cell, run, 'done', n)
        if b'stale' in source:
            state(nb, cell, run - 1 if run > 1 else 999999, 'done', n)


# ---------- the protocol ----------

def read_exact(n):
    data = b''
    while len(data) < n:
        chunk = inp.read(n - len(data))
        if not chunk:
            break
        data += chunk
    return data


def main():
    if MODE == 'nofeature':
        send('hello 1')
    else:
        send('hello 1 notebooks')
    threading.Thread(target=worker, daemon=True).start()
    while True:
        line = inp.readline()
        if not line:
            return
        line = line.rstrip(b'\n')
        log(line)
        f = line.split(b' ')
        body = b''
        if len(f) >= 2 and f[1] in (b'nb-open', b'nb-save', b'nb-run'):
            try:
                n = int(f[-1])
                body = read_exact(n)
            except ValueError:
                pass
        if f[0] == b'ok' and len(f) >= 3 and int(f[1]) in choosing:
            nb = choosing.pop(int(f[1]))
            label = [b'Fake Kernel', b'Other Kernel'][int(f[2]) - 1]
            request(f'nb-kernel-label {nb} idle {len(label)}', label)
            continue
        if f[0] in (b'ok', b'error'):
            continue
        if f[0] != b'0':
            rid = f[0].decode()
            verb = f[1]
            if verb == b'nb-open':
                if MODE == 'slowopen':
                    time.sleep(2)
                if MODE == 'openerror':
                    send(f'error {rid} syntax this is not a toy notebook')
                    continue
                pl, dl = map(int, body.split(b'\n', 1)[0].split(b' '))
                rest = body.split(b'\n', 1)[1]
                data = rest[pl:pl + dl]
                if MODE == 'noread':
                    log(b'open path=' + rest[:pl] + b' bytes=%d' % dl)
                meta, cells = parse_nbt(data)
                nbb = b'garbage\n' if MODE == 'badbody' else body_of(meta, cells)
                send(f'ok {rid} {len(nbb)}', nbb)
                request(f'nb-kernel-label {f[2].decode()} idle 11', b'Fake Kernel')
            elif verb == b'nb-save':
                if MODE == 'saveerror':
                    send(f'error {rid} refused the disk is full')
                    continue
                pl = int(body.split(b'\n', 1)[0])
                rest = body.split(b'\n', 1)[1]
                meta, cells = read_body(rest[pl:])
                data = nbt_of(meta, cells)
                send(f'ok {rid} {len(data)}', data)
            else:
                send(f'error {rid} unknown')
            continue
        ev = f[1]
        if ev == b'nb-run':
            nb, cell, run = f[2].decode(), f[3].decode(), int(f[4])
            latest[(nb, cell)] = run
            state(nb, cell, run, 'queued')
            runs.put((nb, cell, run, body))
        elif ev == b'nb-interrupt':
            interrupted.set()
        elif ev == b'nb-restart':
            counter[0] = 0
            request(f'nb-kernel-label {f[2].decode()} starting 11', b'Fake Kernel')
            request(f'nb-kernel-label {f[2].decode()} idle 11', b'Fake Kernel')
        elif ev == b'nb-kernel':
            items = b'Pick a kernel\nFake Kernel\nOther Kernel'
            choosing[request(f'choose {len(items)}', items)] = f[2].decode()
        elif ev == b'bye':
            return


main()
