#!/usr/bin/env python3
"""wsx: a fake extension for the workspace-edit tests (tests/wsedit.py), standard library only.

It says `hello 1` with the features in the file `features` next to it (one line, may be empty),
logs every line rhun sends to $RHUN_STATE/wsx.log (bodies as `body N` lines with their bytes
escaped), and acts on its commands: `0 run wsx.NAME DOC` sends the request in the file `plans/NAME`
next to it. A plan's first line is the request after its id; the rest is its body. Placeholders
anywhere in a plan (a first line "!write PATH" makes it write the body to PATH instead, "!chmod MODE
PATH" changes a path's mode): {doc:NAME} the id and {ver:NAME} the version of the open document whose path
ends in /NAME (from the opened/edits/changed events), {fnv:PATH} the FNV-1a hash of that file's
bytes on disk now; the word LEN in the first line becomes the body's length.
As a linked-editing provider it answers `ID linked ...` with the body of plans/linked the same way.
As a rename provider it answers `ID rename ...` with `ok ID LEN` and the body of plans/rename (its
first line is not sent).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.environ.get('RHUN_STATE', '')
LOG = os.path.join(STATE, 'wsx.log') if STATE else None
PLANS = os.path.join(HERE, 'plans')
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = 1
docs = {}               # doc id -> [path, version]


def log(line):
    if LOG:
        with open(LOG, 'ab') as f:
            f.write(line + b'\n')


def send(data):
    out.write(data)
    out.flush()


def fnv(path):
    h = 0xcbf29ce484222325
    with open(path, 'rb') as f:
        for b in f.read():
            h = ((h ^ b) * 0x100000001b3) & 0xffffffffffffffff
    return '%016x' % h


def expand(text):
    def doc_of(name):
        for d, (path, ver) in docs.items():
            if path.endswith('/' + name) or path == name:
                return d, ver
        return 0, 0

    def rep(m):
        kind, arg = m.group(1), m.group(2)
        if kind == 'doc':
            return str(doc_of(arg)[0])
        if kind == 'ver':
            return str(doc_of(arg)[1])
        return fnv(arg)
    return re.sub(r'\{(doc|ver|fnv):([^}]*)\}', rep, text)


def plan(name):
    path = os.path.join(PLANS, name)
    if not os.path.exists(path):
        return None, b''
    text = expand(open(path, 'rb').read().decode('utf-8', 'surrogateescape'))
    head, _, body = text.partition('\n')
    body = body.encode('utf-8', 'surrogateescape')
    words = head.split(' ')
    words = [str(len(body)) if w == 'LEN' else w for w in words]
    return ' '.join(words), body


def read_line():
    line = inp.readline()
    if not line:
        return None
    return line.rstrip(b'\r\n')


def read_body(n):
    data = b''
    while len(data) < n:
        chunk = inp.read(n - len(data))
        if not chunk:
            break
        data += chunk
    return data


def main():
    global next_id
    feats = ''
    fpath = os.path.join(HERE, 'features')
    if os.path.exists(fpath):
        feats = open(fpath).read().strip()
    send(('hello 1' + (' ' + feats if feats else '') + '\n').encode())
    while True:
        line = read_line()
        if line is None:
            return
        log(line)
        fields = line.split(b' ')
        # bodies: events and replies with a trailing length
        body = b''
        if fields[0] == b'0' and len(fields) > 1 and fields[1] in (b'edits', b'action'):
            body = read_body(int(fields[-1]))
        elif fields[0] == b'ok' and len(fields) == 3 and fields[2].isdigit() and False:
            pass
        elif fields[0] not in (b'0', b'ok', b'error') and len(fields) > 1:
            pass
        if body:
            log(b'body ' + str(len(body)).encode() + b' ' + body.replace(b'\n', b'\\n'))
        if fields[0] == b'0':
            ev = fields[1]
            if ev == b'opened':
                docs[int(fields[2])] = [b' '.join(fields[5:]).decode('utf-8', 'replace'), int(fields[3])]
            elif ev in (b'changed', b'saved') and int(fields[2]) in docs:
                docs[int(fields[2])][1] = int(fields[3])
            elif ev == b'edits' and int(fields[2]) in docs:
                docs[int(fields[2])][1] = int(fields[3])
            elif ev == b'closed':
                docs.pop(int(fields[2]), None)
            elif ev == b'run':
                name = fields[2].decode().split('.', 1)[1]
                head, body = plan(name)
                if head is not None and head.startswith('!write '):
                    # not a request: the extension writes a file itself (a change on disk)
                    with open(head[7:], 'wb') as f:
                        f.write(body)
                    log(('wrote ' + head[7:]).encode())
                elif head is not None and head.startswith('!chmod '):
                    # "!chmod MODE PATH": a folder made read-only (or writable) on disk
                    mode, path = head[7:].split(' ', 1)
                    os.chmod(path, int(mode, 8))
                    log(('chmod %s %s' % (mode, path)).encode())
                elif head is not None:
                    rid = next_id
                    next_id += 1
                    log(('sent %d %s' % (rid, head)).encode())
                    send(('%d %s\n' % (rid, head)).encode() + body)
            elif ev == b'bye':
                return
        elif fields[0] not in (b'ok', b'error') and fields[0].isdigit():
            # a request from rhun
            rid = fields[0].decode()
            verb = fields[1]
            if verb == b'linked':
                head, body = plan('linked')
                if head is None:
                    send(('error %s refused nothing here\n' % rid).encode())
                else:
                    send(('ok %s %d\n' % (rid, len(body))).encode() + body)
                continue
            if verb == b'rename':
                docs.setdefault(int(fields[2]), ['', 0])[1] = int(fields[3])
                head, body = plan('rename')
                if head is None:
                    send(('error %s refused nothing here\n' % rid).encode())
                else:
                    send(('ok %s %d\n' % (rid, len(body))).encode() + body)
            else:
                send(('error %s unknown\n' % rid).encode())


if __name__ == '__main__':
    main()
