#!/usr/bin/env python3
"""A fake extension for the resources group's host tests (lifecycle and cost, secrets, URLs and
links, URIs and virtual documents, files and search, scoped settings, workspace folders).
Standard library only.

RES_FEATURES  the features named after "hello 1" (space separated)
RES_LOG       a file that receives every line rhun sends and every reply, one per line
RES_ARGS      a file whose lines are arguments for the next commands (one line per command that
              takes arguments, consumed in order)

A command NAME run from rhun ("0 run OWNER.NAME DOC") does what CMDS says; the extension's
manifest lists the commands a test uses.
"""
import os
import subprocess
import sys
import time

LOG = os.environ.get('RES_LOG')
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = 1
pending = {}
keep = []               # memory and children kept alive on purpose
contents = {}           # uri -> (lang, title, text) for content requests


def log(line):
    if LOG:
        with open(LOG, 'ab') as f:
            f.write(line + b'\n')


def send(line, body=b''):
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
    path = os.environ.get('RES_ARGS')
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
    elif name == 'request':
        # any request with its arguments from RES_ARGS: "verb args" or "verb args|body"
        line = arg()
        verb, _, body = line.partition('|')
        body = body.encode().replace(b'\\n', b'\n')
        if '{LEN}' in verb:
            verb = verb.replace('{LEN}', str(len(body)))
        request(verb, body)
    elif name == 'quiet':
        pass


def main():
    features = os.environ.get('RES_FEATURES', '').strip()
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
            uri = parts[2].decode()
            lang, title, text = contents.get(uri, ('', '', 'content of ' + uri + '\n'))
            data = f'{len(lang.encode())} {len(title.encode())} {len(text.encode())}\n'.encode() \
                + lang.encode() + title.encode() + text.encode()
            send(f'ok {parts[0].decode()} {len(data)}', data)


if __name__ == '__main__':
    main()
