#!/usr/bin/env python3
"""Fake custom editors for the host tests (docs/extensions/v1.1.md, "Feature: custom-editors"),
standard library only. "owned" (argv[1]) keeps the file's bytes: it reads them with editor-read in
pages of 4 bytes and more, flips the first byte on a click (undo and redo step through its flips), tells
editor-dirty, and answers editor-save in parts of 3 bytes (1 MB for files of 64 bytes or more). "text" lets rhun keep the document and
upper-cases the first line on a click with replace. Both draw "N bytes: XX XX ..." in their view.
EDFAKE_LOG names a file (in the state folder) that receives every line rhun sends. EDFAKE_MODE:
refuse (editor-open fails), badpart (a save part without its MORE line), crashclick (the second
click ends the program)."""
import os
import queue
import sys
import threading

MODEL = sys.argv[1] if len(sys.argv) > 1 else 'owned'
MODE = os.environ.get('EDFAKE_MODE', '')
LOG = os.environ.get('EDFAKE_LOG')
if LOG and not os.path.isabs(LOG):
    LOG = os.path.join(os.environ.get('RHUN_STATE', '.'), LOG)
out = sys.stdout.buffer
inp = sys.stdin.buffer
lock = threading.Lock()
next_id = [1]
answers = {}
work = queue.Queue()
clicks = [0]
eds = {}                        # cdoc -> {'view', 'path', 'data', 'saved', 'undo', 'redo', 'snap'}


def log(line):
    if LOG:
        with open(LOG, 'ab') as f:
            f.write(line + b'\n')


def send(line, body=b''):
    with lock:
        out.write(line.encode() + b'\n' + body)
        out.flush()


def ask(verb_and_args, body=None):
    """A request from the worker thread: the answer's line and body."""
    q = queue.Queue()
    with lock:
        rid = next_id[0]
        next_id[0] += 1
        answers[rid] = (q, verb_and_args.split(' ')[0])
    if body is None:
        send(f'{rid} {verb_and_args}')
    else:
        send(f'{rid} {verb_and_args} {len(body)}', body)
    return q.get(timeout=30)


def draw(cdoc):
    e = eds[cdoc]
    data = e['data'] if MODEL == 'owned' else e.get('text', b'')
    hexes = ' '.join('%02X' % b for b in data[:16])
    pic = f'rect 0 0 400 40 panel\ntext 8 8 normal left fg {len(data)} bytes: {hexes}\n'.encode()
    ask(f'draw {e["view"]}', pic)


def read_all(cdoc):
    data, off, page = b'', 0, 4      # pages of 4 bytes, then twice as many each time
    while True:
        line, body = ask(f'editor-read {cdoc} {off} {page}')
        if not line.startswith(b'ok') or not body:
            break
        data += body
        off += len(body)
        page = min(page * 2, 4 << 20)
    return data


def set_dirty(cdoc):
    e = eds[cdoc]
    ask(f'editor-dirty {cdoc} {1 if e["data"] != e["saved"] else 0}')


def worker():
    while True:
        job = work.get()
        kind = job[0]
        if kind == 'open':
            _, rid, cdoc, view, path = job
            eds[cdoc] = {'view': view, 'path': path, 'data': b'', 'saved': b'', 'undo': [], 'redo': [], 'snap': b''}
            if MODEL == 'owned':
                eds[cdoc]['data'] = eds[cdoc]['saved'] = read_all(cdoc)
            else:
                line, body = ask(f'text {cdoc}')
                eds[cdoc]['text'] = body
            send(f'ok {rid} 0')
            draw(cdoc)
        elif kind == 'click':
            clicks[0] += 1
            if MODE == 'crashclick' and clicks[0] == 2:
                os._exit(1)             # a crash, with unsaved changes
            cdoc = next((c for c, e in eds.items() if e['view'] == job[1]), None)
            if cdoc is None:
                continue
            e = eds[cdoc]
            if MODEL == 'owned':
                if e['data']:
                    e['undo'].append(e['data'])
                    e['redo'] = []
                    e['data'] = bytes([e['data'][0] ^ 0xFF]) + e['data'][1:]
                    set_dirty(cdoc)
            else:
                line, body = ask(f'text {cdoc}')
                version = int(line.split(b' ')[2])
                first = body.split(b'\n', 1)[0]
                ask(f'replace {cdoc} {version} 1 1 1 {len(first) + 1}', first.upper())
                line, body = ask(f'text {cdoc}')
                e['text'] = body
            draw(cdoc)
        elif kind in ('editor-undo', 'editor-redo', 'editor-revert'):
            _, rid, cdoc = job
            e = eds[cdoc]
            if kind == 'editor-undo' and e['undo']:
                e['redo'].append(e['data'])
                e['data'] = e['undo'].pop()
            elif kind == 'editor-redo' and e['redo']:
                e['undo'].append(e['data'])
                e['data'] = e['redo'].pop()
            elif kind == 'editor-revert':
                e['data'] = e['saved'] = read_all(cdoc)
                e['undo'], e['redo'] = [], []
            send(f'ok {rid} 0')
            set_dirty(cdoc)
            draw(cdoc)
        elif kind == 'changed':
            cdoc = job[1]
            e = eds.get(cdoc)
            if e and e['data'] == e['saved']:
                e['data'] = e['saved'] = read_all(cdoc)
                draw(cdoc)


def read_exact(n):
    data = b''
    while len(data) < n:
        chunk = inp.read(n - len(data))
        if not chunk:
            break
        data += chunk
    return data


def main():
    send('hello 1 views custom-editors')
    threading.Thread(target=worker, daemon=True).start()
    while True:
        line = inp.readline()
        if not line:
            return
        line = line.rstrip(b'\n')
        log(line)
        f = line.split(b' ')
        body = b''
        if f[0] in (b'ok', b'error'):
            rid = int(f[1]) if len(f) > 1 and f[1].isdigit() else 0
            q, verb = answers.pop(rid, (None, ''))
            if f[0] == b'ok' and verb in ('text', 'editor-read'):     # ok ID [VERSION] LEN + bytes
                body = read_exact(int(f[-1]))
            if q is not None:
                q.put((line, body))
            continue
        if f[0] == b'0':
            ev = f[1]
            if ev == b'view' and len(f) >= 4 and f[3] == b'click':
                work.put(('click', int(f[2])))
            elif ev == b'editor-changed':
                work.put(('changed', int(f[2])))
            elif ev == b'editor-path':
                path = read_exact(int(f[3]))
                log(b'path ' + path)
                eds.get(int(f[2]), {})['path'] = path
            elif ev == b'bye':
                return
            continue
        rid, verb = f[0].decode(), f[1].decode()
        if verb == 'editor-open':
            path = read_exact(int(f[-1]))
            if MODE == 'refuse':
                send(f'error {rid} refused this file is not for me')
                continue
            work.put(('open', rid, int(f[2]), int(f[3]), path))
        elif verb == 'editor-save':
            cdoc, part = int(f[2]), int(f[4])
            e = eds[cdoc]
            if part == 0:
                e['snap'] = e['data']
            size = 3 if len(e['snap']) < 64 else 1 << 20      # parts of 3 bytes for small files
            chunk = e['snap'][part * size:part * size + size]
            more = 1 if len(e['snap']) > part * size + size else 0
            reply = chunk if MODE == 'badpart' else b'%d\n' % more + chunk
            if not more:
                e['saved'] = e['snap']
            send(f'ok {rid} {len(reply)}', reply)
        elif verb in ('editor-undo', 'editor-redo', 'editor-revert'):
            work.put((verb, rid, int(f[2])))
        else:
            send(f'error {rid} unknown')


main()
