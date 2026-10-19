#!/usr/bin/env python3
"""A scripted fake extension for the source control tests (tests/ext-scm.py), standard library only.

script.json in its folder says what it does:
  hello     the hello line ("hello 1 git-data")
  commands  {"name": [request, ...]}: on "0 run X.name DOC" it sends each request, "ID " before it;
            a request is [line, body] (body text, or null for none); "$DOC" in the line is the run's
            document; a request waits for the reply to the one before it
  answers   {"verb": {"body": text, "error": text, "delay": seconds, "lines": [line, ...]}}: how it
            answers rhun's requests of that verb (commit-message, quickdiff); "lines" are requests it
            sends first; "never": true leaves it unanswered
  events    {"prefix": [request, ...]}: requests sent when an event line starts with prefix
Everything it receives is logged to log.txt in its state folder: "< LINE", then "| BODY" (repr) for a
body. Replies to its requests carry a body when the reply's last field is a length and the request's
verb is one whose answer has one.
"""
import json
import os
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = json.loads((HERE / 'script.json').read_text())
LOG = Path(os.environ['RHUN_STATE']) / 'log.txt'
out = sys.stdout.buffer
inp = sys.stdin.buffer
lock = threading.Lock()
next_id = 1
pending = {}            # id -> verb
queue = []              # requests waiting for the one before to be answered
BODY_VERBS = {'git-repo', 'git-status', 'git-blame', 'git-log', 'git-show', 'scm-input'}


def log(text):
    with LOG.open('a', encoding='utf-8') as f:
        f.write(text + '\n')


def send(data):
    with lock:
        out.write(data)
        out.flush()


def request(line, body):
    global next_id
    rid = next_id
    next_id += 1
    pending[rid] = line.split()[0]
    data = (str(rid) + ' ' + line + '\n').encode()
    if body is not None:
        data += body.encode() if isinstance(body, str) else body
    send(data)


def pump():
    if queue and not pending:
        line, body = queue.pop(0)
        request(line, body)


def run_list(items, doc):
    for line, body in items:
        queue.append((line.replace('$DOC', doc), body))
    pump()


def read_exact(n):
    data = b''
    while len(data) < n:
        chunk = inp.read(n - len(data))
        if not chunk:
            sys.exit(0)
        data += chunk
    return data


def answer(rid, verb, spec, fields):
    if spec.get('delay'):
        time.sleep(spec['delay'])
    if spec.get('never'):
        return
    for line in spec.get('lines', []):
        request(line, None)
    if 'error' in spec:
        send(f'error {rid} {spec["error"]}\n'.encode())
        return
    body = spec.get('body', '').encode()
    send(f'ok {rid} {len(body)}\n'.encode() + body)


send((SCRIPT.get('hello', 'hello 1') + '\n').encode())
while True:
    raw = inp.readline()
    if not raw:
        break
    line = raw.rstrip(b'\n').decode('utf-8', 'replace')
    log('< ' + line)
    fields = line.split(' ')
    body = None
    if fields[0] == 'ok' and len(fields) == 3:
        rid = int(fields[1])
        if pending.get(rid) in BODY_VERBS:
            body = read_exact(int(fields[2]))
    elif fields[0] not in ('ok', 'error', '0') and len(fields) >= 3 and fields[1] == 'commit-message':
        body = read_exact(int(fields[-1]))
    if body is not None:
        log('| ' + repr(body.decode('utf-8', 'replace')))
    if fields[0] in ('ok', 'error'):
        pending.pop(int(fields[1]), None)
        pump()
        continue
    if fields[0] == '0':
        if len(fields) >= 3 and fields[1] == 'run':
            name = fields[2].split('.', 1)[1]
            doc = fields[3] if len(fields) > 3 else '0'
            run_list(SCRIPT.get('commands', {}).get(name, []), doc)
        elif fields[1] == 'bye':
            break
        for prefix, items in SCRIPT.get('events', {}).items():
            if line.startswith(prefix):
                run_list(items, '0')
        continue
    # a request from rhun
    verb = fields[1]
    spec = SCRIPT.get('answers', {}).get(verb)
    if spec is None:
        send(f'error {fields[0]} unknown\n'.encode())
        continue
    threading.Thread(target=answer, args=(fields[0], verb, spec, fields), daemon=True).start()
