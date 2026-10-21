#!/usr/bin/env python3
"""rhun-tests/present: a fake extension for the editor presentation tests, standard library only.

It says PRESENT_HELLO (default "hello 1 decorations"), logs every line rhun sends to PRESENT_LOG,
and keeps the documents' versions from the opened and changed events. PRESENT_STEPS names a JSON
file {"STEP": [[LINE, BODY], ...]}: the command present.STEP (a..h) sends each LINE with a fresh
request id in front and BODY after it. In LINE and BODY, {DOC} is the active document, {VER} its
version, {VER-N} N versions before, and in LINE {LEN} is BODY's length in bytes. A step named
"ready" runs once after the ready event, one named "opened" after every opened event. Requests
from rhun get "error ID unknown" unless PRESENT_ANSWERS (JSON {"VERB": [LINE, BODY]}) answers
them, with {ID} for the request's id; a list of such pairs answers in turn (the last repeated).
"""
import json
import os
import sys

out = sys.stdout.buffer
inp = sys.stdin.buffer
LOG = os.environ.get('PRESENT_LOG')
HELLO = os.environ.get('PRESENT_HELLO', 'hello 1 decorations')
STEPS = json.load(open(os.environ['PRESENT_STEPS'])) if os.environ.get('PRESENT_STEPS') else {}
ANSWERS = json.load(open(os.environ['PRESENT_ANSWERS'])) if os.environ.get('PRESENT_ANSWERS') else {}
versions = {}
asked = {}
active = 0
next_id = 1


def log(line):
    if LOG:
        with open(LOG, 'ab') as f:
            f.write(line + b'\n')


def fill(text, doc):
    ver = versions.get(doc, 0)
    text = text.replace('{DOC}', str(doc)).replace('{VER}', str(ver))
    for n in range(1, 300):
        key = '{VER-%d}' % n
        if key in text:
            text = text.replace(key, str(max(ver - n, 0)))
    return text


def step(name, doc):
    global next_id
    for line, body in STEPS.get(name, []):
        body = fill(body, doc).encode()
        line = fill(line, doc).replace('{LEN}', str(len(body)))
        out.write(f'{next_id} {line}\n'.encode() + body)
        next_id += 1
    out.flush()


def read_body(n):
    data = b''
    while len(data) < n:
        chunk = inp.read(n - len(data))
        if not chunk:
            break
        data += chunk
    return data


out.write((HELLO + '\n').encode())
out.flush()
while True:
    raw = inp.readline()
    if not raw:
        break
    line = raw.rstrip(b'\r\n')
    log(line)
    words = line.decode('utf-8', 'replace').split(' ')
    if words[0] == 'ok' and len(words) == 3 and words[2].isdigit():
        log(read_body(int(words[2])))
        continue
    if words[0] != '0' and words[0].isdigit() and len(words) > 1:
        # a request from rhun
        rid, verb = words[0], words[1]
        if words[-1].isdigit() and verb in ('color-edit',):
            read_body(int(words[-1]))
        if verb in ANSWERS:
            answer = ANSWERS[verb]
            if isinstance(answer[0], list):         # answers in turn, the last one repeated
                n = asked.get(verb, 0)
                asked[verb] = n + 1
                answer = answer[min(n, len(answer) - 1)]
            reply, body = answer
            doc = int(words[2]) if len(words) > 2 and words[2].isdigit() else active
            body = fill(body, doc).encode()
            reply = fill(reply, doc).replace('{ID}', rid).replace('{LEN}', str(len(body)))
            out.write(reply.encode() + b'\n' + body)
        else:
            out.write(f'error {rid} unknown\n'.encode())
        out.flush()
        continue
    if len(words) < 2:
        continue
    ev = words[1]
    if ev == 'ready':
        step('ready', active)
    elif ev == 'opened' and len(words) > 3:
        versions[int(words[2])] = int(words[3])
        active = active or int(words[2])
        step('opened', int(words[2]))
    elif ev == 'changed' and len(words) > 3:
        versions[int(words[2])] = int(words[3])
    elif ev == 'active' and len(words) > 2:
        active = int(words[2])
    elif ev == 'edits' and len(words) > 3:
        versions[int(words[2])] = int(words[3])
        if words[-1].isdigit():
            read_body(int(words[-1]))
    elif ev == 'run' and len(words) > 2:
        doc = int(words[3]) if len(words) > 3 and words[3].isdigit() else active
        step(words[2].split('.')[-1], doc or active)
    elif ev == 'bye':
        break
