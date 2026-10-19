# A fake extension for the contributions and commands tests (tests/contrib.py writes it into an
# extension folder after a header that defines HELLO, the hello line, and ACTIONS, a dict from a
# local command name to the requests it sends when run; "{args}" in a request is replaced by the
# invocation's body, and a request "LEN" field is filled in when it ends with " #"). Every line
# rhun sends, and every body, goes to contrib.log in the state folder.
import os
import sys
from pathlib import Path

log = Path(os.environ['RHUN_STATE']) / 'contrib.log'
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = 1


def note(text):
    with log.open('a', encoding='utf-8') as f:
        f.write(text + '\n')


def request(text, body=b''):
    global next_id
    if text.endswith(' #'):
        text = text[:-1] + str(len(body))
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
    if line.startswith('0 bye'):
        break
    if fields[:2] == ['0', 'run']:
        name = fields[2].split('.', 1)[1]
        for text in ACTIONS.get(name, []):
            if isinstance(text, tuple):
                text, payload = text
                request(text, payload.replace('{args}', body.decode('utf-8', 'replace')).encode())
            else:
                request(text.replace('{args}', body.decode('utf-8', 'replace')))
