#!/usr/bin/env python3
"""A fake debug adapter for rhun's host tests (tests/debug-*.py). It "runs" a scenario: the launch
argument `program` names a JSON file {"steps": [...], "exitCode": N}, each step
{"file", "line", "function", "locals": {...}, "depth": N, "output": "...", "raise": "Name"}.
Running moves through the steps and stops at a step whose line has an enabled breakpoint whose
condition (NAME == VALUE over the step's locals) and hit count hold; logpoints print instead.
Variables come from locals, with references allocated per stop. FAKEDAP_MODE (comma-separated)
picks behaviours: orderings (init-early, init-after-launch, launch-after-config, seq0), bad
framing (split, coalesce, junk-stdout, no-length, bad-json, big=N, flood=N), failures (slow=MS,
crash-at=STEP, ignore-terminate, ignore-disconnect, launch-fail, no-init-response,
no-terminate-cap), lifetimes (strict-refs), features (exceptions, stderr). Every message is logged
to FAKEDAP_LOG. Standard library only; run with -I."""
import json
import os
import sys
import time

MODE = {}
for part in os.environ.get('FAKEDAP_MODE', '').split(','):
    part = part.strip()
    if not part:
        continue
    key, _, value = part.partition('=')
    MODE[key] = value or True
LOG = os.environ.get('FAKEDAP_LOG')


def log(text):
    if LOG:
        with open(LOG, 'a', encoding='utf-8') as f:
            f.write(text + '\n')


out = sys.stdout.buffer
inp = sys.stdin.buffer
seq = [1]
pending_writes = []


def write_raw(data):
    if 'split' in MODE:
        for i in range(len(data)):
            out.write(data[i:i + 1])
            out.flush()
        return
    if 'coalesce' in MODE:
        pending_writes.append(data)
        return
    out.write(data)
    out.flush()


def flush_coalesced():
    if pending_writes:
        out.write(b''.join(pending_writes))
        out.flush()
        pending_writes.clear()


def send(msg):
    if 'seq0' in MODE:
        msg['seq'] = 0
    else:
        msg['seq'] = seq[0]
        seq[0] += 1
    body = json.dumps(msg).encode('utf-8')
    log('> ' + (msg.get('command') or msg.get('event') or msg['type']))
    write_raw(b'Content-Length: %d\r\n\r\n' % len(body) + body)


def respond(req, body=None, success=True, message=None):
    if 'slow' in MODE:
        time.sleep(int(MODE['slow']) / 1000)
    msg = {'type': 'response', 'request_seq': req['seq'], 'command': req['command'], 'success': success}
    if body is not None:
        msg['body'] = body
    if message is not None:
        msg['message'] = message
    send(msg)


def event(name, body=None):
    msg = {'type': 'event', 'event': name}
    if body is not None:
        msg['body'] = body
    send(msg)


def read_message():
    headers = b''
    while not headers.endswith(b'\r\n\r\n'):
        c = inp.read(1)
        if not c:
            return None
        headers += c
    length = 0
    for line in headers.split(b'\r\n'):
        if line.lower().startswith(b'content-length:'):
            length = int(line.split(b':', 1)[1])
    body = inp.read(length)
    return json.loads(body)


class Program:
    def __init__(self):
        self.steps = []
        self.exit_code = 0
        self.pc = -1
        self.bps = {}           # path -> [{line, condition, hitCondition, logMessage, id, hits}]
        self.fbps = []
        self.filters = set()
        self.next_bp = 1
        self.refs = {}          # ref -> (value, epoch)
        self.next_ref = 1000
        self.epoch = 0
        self.frames = {}        # frame id -> step index
        self.done = False
        self.stop_on_entry = False

    def load(self, path):
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        self.steps = data.get('steps', [])
        self.exit_code = data.get('exitCode', 0)

    def bp_for(self, step):
        for bp in self.bps.get(step.get('file'), []):
            if bp['line'] == step.get('line'):
                return bp
        return None

    def cond_holds(self, cond, step):
        if not cond:
            return True
        name, _, value = cond.partition('==')
        return str(step.get('locals', {}).get(name.strip())) == value.strip()

    def hits_hold(self, hit, count):
        if not hit:
            return True
        hit = hit.strip()
        for op in ('>=', '<=', '==', '>', '<', '%'):
            if hit.startswith(op):
                n = int(hit[len(op):])
                return {'>=': count >= n, '<=': count <= n, '==': count == n, '>': count > n,
                        '<': count < n, '%': count % n == 0}[op]
        return count == int(hit)

    def interpolate(self, text, step):
        res, i = '', 0
        while i < len(text):
            if text[i] == '{':
                j = text.find('}', i)
                if j > 0:
                    res += str(step.get('locals', {}).get(text[i + 1:j], ''))
                    i = j + 1
                    continue
            res += text[i]
            i += 1
        return res

    def enter(self, i):
        """Arrive at step i: its output, a crash. True when the program goes on."""
        step = self.steps[i]
        if 'crash-at' in MODE and int(MODE['crash-at']) == i:
            log('CRASH')
            sys.stderr.write('fakedap: crashing at step %d\n' % i)
            sys.stderr.flush()
            os._exit(7)
        if step.get('output'):
            event('output', {'category': 'stdout', 'output': step['output']})
        return True

    def run(self, kind):
        """continue, next, stepIn, stepOut from the current step"""
        start_depth = self.depth(self.pc) if self.pc >= 0 else 0
        i = self.pc + 1
        while i < len(self.steps):
            self.enter(i)
            step = self.steps[i]
            if kind in ('next', 'stepIn'):
                return self.stop(i, 'step')
            if kind == 'stepOut' and self.depth(i) < start_depth:
                return self.stop(i, 'step')
            if step.get('raise'):
                if 'uncaught' in self.filters or 'raised' in self.filters:
                    return self.stop(i, 'exception', step['raise'])
            for fbp in self.fbps:
                if fbp['name'] == step.get('function') and self.depth(i) > self.depth(i - 1 if i else 0) - 1 \
                        and (i == 0 or self.steps[i - 1].get('function') != step.get('function')):
                    return self.stop(i, 'function breakpoint', bp=fbp)
            bp = self.bp_for(step)
            if bp and self.cond_holds(bp.get('condition'), step):
                bp['hits'] += 1
                if self.hits_hold(bp.get('hitCondition'), bp['hits']):
                    if bp.get('logMessage'):
                        event('output', {'category': 'console',
                                         'output': self.interpolate(bp['logMessage'], step) + '\n'})
                    else:
                        return self.stop(i, 'breakpoint', bp=bp)
            i += 1
        self.pc = len(self.steps)
        self.finish()

    def depth(self, i):
        if i < 0 or i >= len(self.steps):
            return 0
        return self.steps[i].get('depth', 1)

    def stop(self, i, reason, text=None, bp=None):
        self.pc = i
        self.epoch += 1
        body = {'reason': reason, 'threadId': 1, 'allThreadsStopped': True}
        if bp:
            body['hitBreakpointIds'] = [bp['id']]
        if text:
            body['text'] = text
            body['description'] = 'Exception: ' + text
        event('stopped', body)

    def finish(self):
        if self.done:
            return
        self.done = True
        event('exited', {'exitCode': self.exit_code})
        event('terminated')

    def ref(self, value):
        self.next_ref += 1
        self.refs[self.next_ref] = (value, self.epoch)
        return self.next_ref

    def var(self, name, value):
        v = {'name': name, 'evaluateName': name}
        if isinstance(value, dict):
            v['value'] = '{...}'
            v['type'] = 'dict'
            v['variablesReference'] = self.ref(value)
            v['namedVariables'] = len(value)
        elif isinstance(value, list):
            v['value'] = '[%d]' % len(value)
            v['type'] = 'list'
            v['variablesReference'] = self.ref(value)
            v['indexedVariables'] = len(value)
        else:
            v['value'] = json.dumps(value) if isinstance(value, str) else str(value).lower() \
                if isinstance(value, bool) else str(value)
            v['type'] = type(value).__name__
            v['variablesReference'] = 0
        return v

    def check_ref(self, ref):
        if ref not in self.refs:
            return None
        value, epoch = self.refs[ref]
        if 'strict-refs' in MODE and epoch != self.epoch:
            log('STALE %d' % ref)
            return None
        return value


prog = Program()
configured = [False]
held_launch = [None]


def handle(req):
    cmd = req['command']
    args = req.get('arguments') or {}
    log('< ' + cmd + ' ' + json.dumps(args, sort_keys=True))
    if cmd == 'initialize':
        if 'no-init-response' in MODE:
            return
        caps = {'supportsConfigurationDoneRequest': True, 'supportsConditionalBreakpoints': True,
                'supportsHitConditionalBreakpoints': True, 'supportsLogPoints': True,
                'supportsFunctionBreakpoints': True, 'supportsSetVariable': True,
                'supportsEvaluateForHovers': True, 'supportsExceptionInfoRequest': True}
        if 'no-terminate-cap' not in MODE:
            caps['supportsTerminateRequest'] = True
        if 'exceptions' in MODE:
            caps['exceptionBreakpointFilters'] = [
                {'filter': 'raised', 'label': 'Raised Exceptions', 'default': False},
                {'filter': 'uncaught', 'label': 'Uncaught Exceptions', 'default': True}]
        respond(req, caps)
        if 'init-early' in MODE:
            event('initialized')
        if 'stderr' in MODE:
            sys.stderr.write('fakedap: started\nfakedap: second line\n')
            sys.stderr.flush()
        return
    if cmd in ('launch', 'attach'):
        program = args.get('program')
        if program:
            try:
                prog.load(program)
            except OSError as e:
                respond(req, success=False, message='cannot read ' + program)
                return
        prog.stop_on_entry = bool(args.get('stopOnEntry'))
        log('ARGS ' + json.dumps(args, sort_keys=True))
        if 'launch-fail' in MODE:
            respond(req, {'error': {'id': 1, 'format': 'could not launch: no such program'}},
                    success=False, message='launch failed')
            return
        if 'big' in MODE:
            event('output', {'category': 'stdout', 'output': 'B' * int(MODE['big']) + '\n'})
        if 'flood' in MODE:
            for k in range(int(MODE['flood'])):
                event('output', {'category': 'stdout', 'output': 'flood %d\n' % k})
        if 'bad-json' in MODE:
            write_raw(b'Content-Length: 5\r\n\r\n{bad}')
        if 'no-length' in MODE:
            write_raw(b'Content-Type: x\r\n\r\n')
        if 'launch-after-config' in MODE:
            held_launch[0] = req
            event('initialized')
            return
        respond(req)
        if 'init-early' not in MODE:
            event('initialized')
        return
    if cmd == 'setBreakpoints':
        path = args['source']['path']
        res, kept = [], []
        for b in args.get('breakpoints', []):
            bp = {'line': b['line'], 'condition': b.get('condition'), 'hitCondition': b.get('hitCondition'),
                  'logMessage': b.get('logMessage'), 'id': prog.next_bp, 'hits': 0}
            prog.next_bp += 1
            kept.append(bp)
            verified = any(s.get('file') == path and s.get('line') == b['line'] for s in prog.steps) \
                or not prog.steps
            r = {'id': bp['id'], 'verified': verified, 'line': b['line']}
            if not verified:
                r['message'] = 'no code at this line'
            res.append(r)
        prog.bps[path] = kept
        respond(req, {'breakpoints': res})
        return
    if cmd == 'setFunctionBreakpoints':
        prog.fbps = [{'name': b['name'], 'id': 900 + k} for k, b in enumerate(args.get('breakpoints', []))]
        respond(req, {'breakpoints': [{'id': b['id'], 'verified': True} for b in prog.fbps]})
        return
    if cmd == 'setExceptionBreakpoints':
        prog.filters = set(args.get('filters', []))
        respond(req, {})
        return
    if cmd == 'configurationDone':
        configured[0] = True
        respond(req)
        if held_launch[0]:
            respond(held_launch[0])
            held_launch[0] = None
        if prog.stop_on_entry and prog.steps:
            prog.enter(0)
            prog.stop(0, 'entry')
        else:
            prog.run('continue')
        return
    if cmd == 'threads':
        respond(req, {'threads': [{'id': 1, 'name': 'main'}]})
        return
    if cmd == 'stackTrace':
        frames = []
        if 0 <= prog.pc < len(prog.steps):
            step = prog.steps[prog.pc]
            stack = step.get('stack') or [{'function': step.get('function', 'main'), 'file': step.get('file'),
                                           'line': step.get('line')}]
            for k, fr in enumerate(stack):
                fid = prog.epoch * 100 + k
                prog.frames[fid] = (prog.pc, k)
                f = {'id': fid, 'name': fr.get('function', '?'), 'line': fr.get('line', 0), 'column': 1}
                if fr.get('file'):
                    f['source'] = {'path': fr['file'], 'name': os.path.basename(fr['file'])}
                frames.append(f)
        respond(req, {'stackFrames': frames, 'totalFrames': len(frames)})
        return
    if cmd == 'scopes':
        fid = args.get('frameId')
        if fid not in prog.frames or ('strict-refs' in MODE and fid // 100 != prog.epoch):
            log('STALE frame %s' % fid)
            respond(req, success=False, message='stale frame')
            return
        step = prog.steps[prog.frames[fid][0]]
        scopes = [{'name': 'Locals', 'variablesReference': prog.ref(step.get('locals', {})), 'expensive': False},
                  {'name': 'Globals', 'variablesReference': prog.ref(step.get('globals', {'G': 1})),
                   'expensive': True}]
        respond(req, {'scopes': scopes})
        return
    if cmd == 'variables':
        value = prog.check_ref(args.get('variablesReference'))
        if value is None:
            respond(req, success=False, message='stale reference')
            return
        if isinstance(value, dict):
            items = list(value.items())
        else:
            items = [('[%d]' % k, v) for k, v in enumerate(value)]
        respond(req, {'variables': [prog.var(n, v) for n, v in items]})
        return
    if cmd == 'evaluate':
        expr = args.get('expression', '')
        step = prog.steps[prog.pc] if 0 <= prog.pc < len(prog.steps) else {}
        value = step.get('locals', {})
        for part in expr.split('.'):
            if isinstance(value, dict) and part in value:
                value = value[part]
            else:
                respond(req, success=False, message="name '%s' is not defined" % expr)
                return
        v = prog.var(expr, value)
        respond(req, {'result': v['value'], 'type': v.get('type'), 'variablesReference': v['variablesReference']})
        return
    if cmd == 'setVariable':
        respond(req, {'value': args.get('value')})
        return
    if cmd in ('continue', 'next', 'stepIn', 'stepOut'):
        respond(req, {'allThreadsContinued': True} if cmd == 'continue' else {})
        prog.run(cmd)
        return
    if cmd == 'pause':
        respond(req)
        prog.stop(max(prog.pc, 0), 'pause')
        return
    if cmd == 'exceptionInfo':
        step = prog.steps[prog.pc]
        respond(req, {'exceptionId': step.get('raise', 'Error'), 'description': 'raised at line %d' % step['line'],
                      'breakMode': 'always'})
        return
    if cmd == 'terminate':
        if 'ignore-terminate' in MODE:
            respond(req)
            return
        respond(req)
        prog.exit_code = 143
        prog.finish()
        return
    if cmd == 'disconnect':
        if 'ignore-disconnect' in MODE:
            return
        respond(req, {})
        flush_coalesced()
        log('EXIT')
        sys.exit(0)
    respond(req, success=False, message='unknown request ' + cmd)


def main():
    log('pid %d' % os.getpid())
    if 'junk-stdout' in MODE:
        write_raw(b'hello from the program\nmore junk\n')
    while True:
        msg = read_message()
        if msg is None:
            log('EOF')
            break
        if msg.get('type') == 'request':
            handle(msg)
        flush_coalesced()


if __name__ == '__main__':
    main()
