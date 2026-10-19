#!/usr/bin/env python3
"""A scriptable language provider for the language-feature tests (tests/langfeat-*.py), standard
library only. spec.json next to the running program says what it does:

  hello      the hello line ("hello 1 definition query-stream ...")
  ready      requests to send after "0 ready": [[verb_and_args, body], ...]
  answers    per request verb: {"body": str, "delay": s, "parts": [[body, delay], ...],
             "progress": [[percent or "-", text, delay], ...], "error": "code text",
             "silent": true (never answer), "twice": true (answer twice), "text": true (ask for
             the document's text first and fill {line1} with its first line)}
  run        per command name: requests to send when it runs: [[verb_and_args, body], ...]

Bodies may hold {path} (the asked document's path), {project}, {doc}, {version}, {line1}.
Every line rhun sends, and every reply to this program's own requests, is logged to
RHUN_STATE/lang.log; bodies are logged as "body <bytes with \\n escaped>".
"""
import json
import os
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = json.load(open(os.path.join(HERE, 'spec.json')))
LOG = os.path.join(os.environ.get('RHUN_STATE', HERE), 'lang.log')
out = sys.stdout.buffer
inp = sys.stdin.buffer
lock = threading.Lock()
next_id = [1]
pending = {}
PATHS = {}
VERSIONS = {}
PROJECT = ['-']


def log(text):
    with lock:
        with open(LOG, 'ab') as f:
            f.write(text + b'\n')


def send(line, body=b''):
    with lock:
        out.write(line.encode() + b'\n' + body)
        out.flush()


def request(verb_and_args, body=b'', then=None):
    with lock:
        rid = next_id[0]
        next_id[0] += 1
        pending[rid] = then
    send(f'{rid} {verb_and_args}', body)
    return rid


def fill(text, ctx):
    for k, v in ctx.items():
        text = text.replace('{' + k + '}', str(v))
    return text.encode()


def blen(text, ctx):
    return len(fill(text, ctx))


def expand(text, ctx):
    """{len:...} is the byte length of what is inside, so bodies can carry paths of any length."""
    while '{len:' in text:
        i = text.index('{len:')
        depth, j = 0, i
        while j < len(text):
            if text[j] == '{':
                depth += 1
            elif text[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        inner = text[i + 5:j]
        text = text[:i] + str(len(fill(inner, ctx))) + text[j + 1:]
    return fill(text, ctx)


def answer(rid, verb, fields):
    spec = SPEC.get('answers', {}).get(verb)
    if spec is None:
        send(f'error {rid} unknown no such request')
        return
    doc = fields[2] if len(fields) > 2 else '0'
    ctx = {'path': PATHS.get(doc, '#' + doc), 'project': PROJECT[0], 'doc': doc,
           'version': VERSIONS.get(doc, 0), 'line1': '', 'id': rid}

    def go(text=None):
        if text is not None:
            ctx['line1'] = text.split(b'\n')[0].decode(errors='replace')
        for pct, msg, delay in spec.get('progress', []):
            time.sleep(delay)
            m = msg.encode()
            request(f'query-progress {rid} {pct} {len(m)}', m)
        for body, delay in spec.get('parts', []):
            time.sleep(delay)
            b = expand(body, ctx)
            request(f'query-part {rid} {len(b)}', b)
        time.sleep(spec.get('delay', 0))
        if spec.get('silent'):
            return
        for _ in range(2 if spec.get('twice') else 1):
            if 'error' in spec:
                send(f'error {rid} {spec["error"]}')
            else:
                b = expand(spec.get('body', ''), ctx)
                send(f'ok {rid} {len(b)}', b)

    if spec.get('text') and doc.isdigit():
        request(f'text {doc}', then=lambda f, body: threading.Thread(target=go, args=(body,), daemon=True).start())
    else:
        threading.Thread(target=go, daemon=True).start()


def read_body(n):
    data = b''
    while len(data) < n:
        chunk = inp.read(n - len(data))
        if not chunk:
            break
        data += chunk
    return data


BODY_EVENTS = ('edits', 'action')
BODY_REPLIES = ('text', 'range', 'ask')


def main():
    send(SPEC.get('hello', 'hello 1'))
    while True:
        line = inp.readline()
        if not line:
            return
        line = line.rstrip(b'\r\n')
        log(line)
        text = line.decode(errors='replace')
        fields = text.split(' ')
        if fields[0] in ('ok', 'error'):
            rid = int(fields[1])
            then = pending.pop(rid, None)
            body = b''
            if fields[0] == 'ok' and len(fields) >= 3 and fields[-1].isdigit() and then is not None:
                body = read_body(int(fields[-1]))
                log(b'body ' + body.replace(b'\n', b'\\n'))
            if then and fields[0] == 'ok':
                then(fields, body)
            continue
        if fields[0] != '0':
            # a request from rhun: ID VERB ...; some carry a body (the last field is its length)
            rid, verb = int(fields[0]), fields[1]
            if verb in SPEC.get('bodied', []) and fields[-1].isdigit():
                body = read_body(int(fields[-1]))
                log(b'body ' + body.replace(b'\n', b'\\n'))
            answer(rid, verb, fields)
            continue
        event = fields[1]
        if event in BODY_EVENTS:
            body = read_body(int(fields[-1]))
            log(b'body ' + body.replace(b'\n', b'\\n'))
            if event == 'edits':
                VERSIONS[fields[2]] = int(fields[3])
        elif event == 'ready':
            PROJECT[0] = text.split(' ', 2)[2]
            for verb_and_args, body in SPEC.get('ready', []):
                request(verb_and_args, body.encode())
        elif event == 'opened':
            parts = text.split(' ', 5)
            PATHS[parts[2]] = parts[5]
            VERSIONS[parts[2]] = int(parts[3])
        elif event in ('changed', 'saved'):
            VERSIONS[fields[2]] = int(fields[3])
        elif event == 'run':
            name = fields[2].split('.', 1)[1]
            for verb_and_args, body in SPEC.get('run', {}).get(name, []):
                request(verb_and_args, body.encode())
        elif event == 'bye':
            return


if __name__ == '__main__':
    try:
        main()
    except BrokenPipeError:
        pass
