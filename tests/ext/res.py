#!/usr/bin/env python3
"""A fake extension for the resources group's host tests (lifecycle and cost, secrets, URLs and
links, URIs and virtual documents, files and search, scoped settings, workspace folders).
Standard library only.

RES_FEATURES  the features named after "hello 1" (space separated); RES_FEATURES_NAME for the
              extension NAME alone
RES_LOG       a file that receives every line rhun sends and every reply, one per line
RES_ARGS      a file whose lines are arguments for the next commands (one line per command that
              takes arguments, consumed in order)
In both, {state} stands for the extension's state folder (RHUN_STATE): with several extensions
each keeps its own.

A command NAME run from rhun ("0 run OWNER.NAME DOC") does what CMDS says; the extension's
manifest lists the commands a test uses.
"""
import os
import subprocess
import sys
import time

STATE = os.environ.get('RHUN_STATE', '')
LOG = os.environ.get('RES_LOG', '').replace('{state}', STATE) or None
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = 1
pending = {}
keep = []               # memory and children kept alive on purpose
served = {}             # uri -> how many content requests it answered


def log(line):
    if LOG:
        with open(LOG, 'ab') as f:
            f.write(line + b'\n')


held = None             # batch: messages kept for one write


def send(line, body=b''):
    if held is not None:
        held.append(line.encode() + b'\n' + body)
        return
    out.write(line.encode() + b'\n' + body)
    out.flush()


def request(verb_and_args, body=b''):
    global next_id
    rid = next_id
    next_id += 1
    pending[rid] = verb_and_args.split(' ', 1)[0]
    send(f'{rid} {verb_and_args}', body)
    return rid


def arg():
    path = os.environ.get('RES_ARGS', '').replace('{state}', STATE)
    if not path or not os.path.exists(path):
        return ''
    with open(path, encoding='utf-8') as f:
        lines = f.read().split('\n')
    first, rest = lines[0], lines[1:]
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(rest))
    return first


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


def command(name):
    if name == 'ping':
        request('toast 4', b'pong')
    elif name == 'burn':
        end = time.process_time() + 0.6
        while time.process_time() < end:
            pass
        request('toast 6', b'burned')
    elif name == 'alloc':
        block = bytearray(60 << 20)
        for i in range(0, len(block), 4096):
            block[i] = 1
        keep.append(block)
        request('toast 9', b'allocated')
    elif name == 'child':
        keep.append(subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']))
        request('toast 5', b'child')
    elif name == 'busy':
        request('busy yes')
    elif name == 'unbusy':
        request('busy no')
    elif name == 'badbusy':
        request('busy maybe')
    elif name == 'status':
        request('status 2', b'on')
    elif name == 'unstatus':
        request('status 0')
    elif name == 'batch':
        # every line of RES_ARGS as a request, in one write
        global held
        held = []
        while True:
            line = arg()
            if not line:
                break
            send_line(line)
        data, held = b''.join(held), None
        out.write(data)
        out.flush()
    elif name == 'request':
        # any request with its arguments from RES_ARGS: "verb args" or "verb args|body"
        send_line(arg())
    elif name == 'raw':
        # RES_RAW: requests as they go on the wire without their ids ("verb args LEN" LF and LEN
        # bytes), for bodies that are not text
        path = os.environ.get('RES_RAW', '').replace('{state}', STATE)
        data = open(path, 'rb').read() if path else b''
        i = 0
        while i < len(data):
            j = data.index(b'\n', i)
            line = data[i:j].decode()
            n = int(line.rsplit(' ', 1)[1])
            request(line, data[j + 1:j + 1 + n])
            i = j + 1 + n
    elif name == 'quiet':
        pass


def send_line(line):
    if True:
        verb, _, body = line.partition('|')
        body = body.encode().replace(b'\\n', b'\n')
        if '{LEN}' in verb:
            verb = verb.replace('{LEN}', str(len(body)))
        request(verb, body)


def main():
    name = os.environ.get('RHUN_EXTENSION', '').rsplit('/', 1)[-1]
    features = os.environ.get('RES_FEATURES_' + name, os.environ.get('RES_FEATURES', '')).strip()
    send('hello 1' + (' ' + features if features else ''))
    while True:
        line = read_line()
        if line is None:
            break
        log(line)
        parts = line.split(b' ')
        if line.startswith(b'0 bye'):
            break
        if line.startswith(b'0 run '):
            name = parts[2].decode().rsplit('.', 1)[-1]
            command(name)
        elif line.startswith(b'0 ') and len(parts) >= 3 and parts[-1].isdigit() and parts[1] in (
                b'link', b'found', b'folders', b'content-closed'):
            body = read_body(int(parts[-1]))
            log(b'body ' + body)
        elif parts[0] == b'ok' and len(parts) >= 3 and parts[-1].isdigit() and int(parts[-1]) > 0 \
                and pending.get(int(parts[1])) in ('secret-get', 'secret-keys', 'external-uri',
                                                   'link', 'setting-get'):
            body = read_body(int(parts[-1]))
            log(b'body ' + body)
        elif parts[0].isdigit() and len(parts) >= 3 and parts[1] == b'content':
            # RES_VDOC: "LANG|TITLE" for the answer; RES_VDOC_MODE: slow (no answer), error,
            # bad (a broken answer)
            uri = parts[2].decode()
            served[uri] = served.get(uri, 0) + 1
            mode = os.environ.get('RES_VDOC_MODE', '')
            if mode == 'slow':
                continue
            if mode == 'error':
                send(f'error {parts[0].decode()} nofile no such revision')
                continue
            lang, _, title = os.environ.get('RES_VDOC', '|').partition('|')
            text = f'content {served[uri]} of {uri}\nsecond line\n'
            if mode == 'big':           # the most text a document takes: 4 MiB
                text = text + 'x' * (4194304 - len(text.encode()))
            data = f'{len(lang.encode())} {len(title.encode())} {len(text.encode())}\n'.encode() \
                + lang.encode() + title.encode() + text.encode()
            if mode == 'bad':
                data = b'1 2 99999\nxx'
            send(f'ok {parts[0].decode()} {len(data)}', data)


if __name__ == '__main__':
    main()
