#!/usr/bin/env python3
"""The echo extension: a fake extension for the host tests, standard library only.

It speaks protocol v1 as docs/extensions/v1.md says and does small, testable things when its
commands run. ECHO_LOG names a file that receives every line rhun sends, one per line, so a
test can assert catch-up and events. ECHO_MODE makes it misbehave:

  normal     answer hello, log events, act on commands
  nohello    never say hello
  slowhello  hello after 7 s (past the 5 s deadline)
  badhello   "hello 2"
  crash      exit 3 right after hello
  sleep      hello, then stop reading and writing
  flood      hello, then write toast requests forever as fast as it can (reading the replies)
  floodnoread the same without ever reading its input
  garbage    hello, then 100 KB of bytes with no newline
  fragment   normal, but every write goes out one byte at a time with flushes
  eof        hello, then close stdout and sleep
  syntax     hello, then three unparsable lines
  badargs    hello, then three requests with ids whose arguments cannot be parsed
  noisy      normal, but writes 2 MB to its error output after hello

Commands (from tests/ext/exts/rhun-tests/echo/extension.ini): echo.shout upper-cases the active document,
echo.hi inserts "hi" at the cursor, echo.toast shows a toast, echo.stale sends a replace with a
version one behind, echo.status sets the status text, echo.open opens ECHO_OPEN at line 2,
echo.mb asks for a range inside a character, echo.sel selects then reads the first word, echo.relopen
opens b.go by a relative path, echo.bad asks for a range outside the document.
"""
import os
import sys
import threading
import time

MODE = os.environ.get('ECHO_MODE', 'normal')
LOG = os.environ.get('ECHO_LOG')
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = 1
pending = {}            # id -> (verb, what to do with the reply)


def log(line):
    if LOG:
        with open(LOG, 'ab') as f:
            f.write(line + b'\n')


def send(line, body=b''):
    data = line.encode() + b'\n' + body
    if MODE == 'fragment':
        for i in range(len(data)):
            out.write(data[i:i + 1])
            out.flush()
    else:
        out.write(data)
        out.flush()


def request(verb_and_args, body=b'', then=None):
    global next_id
    rid = next_id
    next_id += 1
    pending[rid] = (verb_and_args.split(' ', 1)[0], then)
    send(f'{rid} {verb_and_args}', body)
    return rid


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
    log(f'pid {os.getpid()}'.encode())
    if MODE == 'nohello':
        time.sleep(30)
        return
    if MODE == 'slowhello':
        time.sleep(7)
    if MODE == 'badhello':
        send('hello 2')
    else:
        send('hello 1')
    if MODE == 'crash':
        sys.exit(3)
    if MODE == 'sleep':
        time.sleep(600)
        return
    if MODE in ('flood', 'floodnoread'):
        if MODE == 'flood':
            threading.Thread(target=lambda: inp.read(), daemon=True).start()
        while True:
            # a hundred requests per write: a flooder is not held back by its own flushes
            out.write(b''.join(f'{next_id + i} toast 5\nflood'.encode() for i in range(100)))
            out.flush()
            next_id += 100
    if MODE == 'garbage':
        out.write(b'x' * 100000)
        out.flush()
        time.sleep(600)
        return
    if MODE == 'eof':
        os.close(1)             # the stream objects keep fd 1 open when closed; the fd itself must go
        time.sleep(600)
        return
    if MODE == 'syntax':
        for _ in range(3):
            send('this is not a message')
        time.sleep(600)
        return
    if MODE == 'badargs':
        for i in range(1, 4):
            send(f'{i} insert blah')
        time.sleep(600)
        return
    if MODE == 'noisy':
        sys.stderr.write('x' * (2 * 1024 * 1024))
        sys.stderr.flush()

    active = 0
    versions = {}
    while True:
        line = read_line()
        if line is None:
            return
        log(line)
        fields = line.decode(errors='replace').split(' ')
        if fields[0] == 'ok' or fields[0] == 'error':
            rid = int(fields[1])
            verb, then = pending.pop(rid, (None, None))
            body = b''
            if fields[0] == 'ok' and verb in ('text', 'range') and len(fields) >= 4:
                body = read_body(int(fields[-1]))
                log(body)
            if then and fields[0] == 'ok':
                then(fields, body)
            continue
        if fields[0] != '0':
            continue
        event = fields[1]
        if event == 'opened':
            versions[int(fields[2])] = int(fields[3])
        elif event in ('changed', 'saved'):
            versions[int(fields[2])] = int(fields[3])
        elif event == 'active':
            active = int(fields[2])
        elif event == 'bye':
            return
        elif event == 'run':
            command, doc = fields[2], int(fields[3])
            on_run(command, doc, versions)


def on_run(command, doc, versions):
    name = command.split('.', 1)[1]
    if name == 'toast':
        request('toast 11', b'hello there')
    elif name == 'status':
        request('status 7', b'echo ok')
    elif name == 'hi':
        request(f'insert {doc} {versions.get(doc, 0)} 2', b'hi')
    elif name == 'shout':
        def got_text(fields, body):
            version = int(fields[2])
            lines = body.count(b'\n') + 1
            last_len = len(body) - (body.rfind(b'\n') + 1)
            upper = body.upper()
            request(f'replace {doc} {version} 1 1 {lines} {last_len + 1} {len(upper)}', upper)
        request(f'text {doc}', then=got_text)
    elif name == 'stale':
        request(f'replace {doc} {max(versions.get(doc, 1) - 1, 0)} 1 1 1 1 5', b'stale')
    elif name == 'open':
        path = os.environ.get('ECHO_OPEN', '')
        request(f'open 2 1 {path}')
    elif name == 'bad':
        request(f'range {doc} 999 1 999 2')
    elif name == 'mb':
        request(f'range {doc} 1 1 1 3')       # col 3 of "héllo" is inside the é
    elif name == 'sel':
        def selected(fields, body):
            request(f'range {doc} 1 1 1 6')
        request(f'select {doc} 1 1 1 6', then=selected)
    elif name == 'relopen':
        request('open 1 1 b.go')


if __name__ == '__main__':
    try:
        main()
    except BrokenPipeError:
        pass
