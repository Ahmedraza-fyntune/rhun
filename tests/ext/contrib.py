# A fake extension for the contributions and commands tests (tests/contribhost.py writes it into an
# extension folder after a header that defines HELLO, the hello line, ACTIONS, a dict from a
# local command name to the requests it sends when run ("{args}" in a request is replaced by the
# invocation's body; a (text, payload) pair sends a body, its LEN filled in where the text ends
# with " #"), and CALL, how it answers "ID call" requests: reverse (ok + the ARGS reversed), error,
# silent, big (a 1 MiB + 1 result) or echo-doc). Every line rhun sends, every body and every
# run-command result goes to contrib.log in the state folder.
import os
import sys
from pathlib import Path

log = Path(os.environ['RHUN_STATE']) / 'contrib.log'
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = 1
asked = set()                   # ids of run-command requests: their ok carries a body


def note(text):
    with log.open('a', encoding='utf-8') as f:
        f.write(text + '\n')


def request(text, body=b''):
    global next_id
    if text.endswith(' #'):
        text = text[:-1] + str(len(body))
    if text.startswith('run-command'):
        asked.add(str(next_id))
    out.write(str(next_id).encode() + b' ' + text.encode() + b'\n' + body)
    out.flush()
    next_id += 1


out.write(HELLO.encode() + b'\n')
out.flush()
while True:
    raw = inp.readline()
    if not raw:
        break
    line = raw.decode('utf-8', 'replace').rstrip('\n')
    note(line)
    fields = line.split(' ')
    body = b''
    # bodies: "0 run NAME DOC FROM LEN", "ok ID LEN" answers, "ID call ... LEN"
    if fields[:2] == ['0', 'run'] and len(fields) == 6:
        body = inp.read(int(fields[5]))
        note('body=' + body.decode('utf-8', 'replace'))
    elif len(fields) >= 3 and fields[1] == 'call':
        body = inp.read(int(fields[-1]))
        note('body=' + body.decode('utf-8', 'replace'))
    elif fields[0] == 'ok' and len(fields) == 3 and fields[1] in asked:
        body = inp.read(int(fields[2]))
        note('result=' + body.decode('utf-8', 'replace'))
    if line.startswith('0 bye'):
        break
    if len(fields) >= 6 and fields[1] == 'call':
        if CALL == 'reverse':
            result = body[::-1]
            out.write(b'ok ' + fields[0].encode() + b' ' + str(len(result)).encode() + b'\n' + result)
        elif CALL == 'error':
            out.write(b'error ' + fields[0].encode() + b' refused nope\n')
        elif CALL == 'big':
            out.write(b'ok ' + fields[0].encode() + b' 1048577\n' + b'x' * 1048577)
        elif CALL == 'echo-doc':
            result = (fields[3] + ' ' + fields[4]).encode()
            out.write(b'ok ' + fields[0].encode() + b' ' + str(len(result)).encode() + b'\n' + result)
        out.flush()
    if fields[:2] == ['0', 'run']:
        name = fields[2].split('.', 1)[1]
        for text in ACTIONS.get(name, []):
            if isinstance(text, tuple):
                text, payload = text
                request(text, payload.replace('{args}', body.decode('utf-8', 'replace')).encode())
            else:
                request(text.replace('{args}', body.decode('utf-8', 'replace')))
