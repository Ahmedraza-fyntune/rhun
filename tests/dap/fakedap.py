#!/usr/bin/env python3
"""A fake debug adapter for rhun's host tests (tests/debug-*.py). It "runs" a scenario: the launch
argument `program` names a JSON file {"steps": [...], "exitCode": N}, each step
{"file", "line", "function", "locals": {...}, "depth": N, "output": "...", "raise": "Name"}.
Running moves through the steps and stops at a step whose line has an enabled breakpoint whose
condition (NAME == VALUE over the step's locals) and hit count hold; logpoints print instead.
Variables come from locals, with references allocated per stop. FAKEDAP_MODE (comma-separated)
picks behaviours: orderings (init-early, init-after-launch, launch-after-config, seq0), bad
framing (split, coalesce, junk-stdout, no-length, bad-json, big=N, flood=N), failures (slow=MS,
crash-at=STEP, ignore-terminate, ignore-disconnect, launch-fail, no-init-response, fail-step,
orphan, partial-pause,
no-terminate-cap, no-cond-caps, preserve-focus), lifetimes (strict-refs), features (exceptions, stderr). Every message is logged
to FAKEDAP_LOG. With `--listen HOST:PORT` it speaks DAP over one TCP connection instead of its
standard input and output, as Delve does; tcp-late=MS listens late, tcp-exit exits before listening,
tcp-never never listens. Threads: with `threads` a step's "thread" (default 1) is the thread it
runs on: entering a step on a new thread sends a thread started event, "threadExit": N an exited
one, a stop names the step's thread, other threads show one waiting frame, and continue, the steps
and pause fail for a thread that is not alive. lldb-threads leaves a worker thread out of the
threads answer at its first stop (as lldb-dap does); single-continue answers continue with
allThreadsContinued false; a stopped step's "threadStarted": N and "continuedOther": N send those
events while paused. Standard library only; run with -I."""
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
launch_args = {}
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
        self.unblocked = set()
        self.running = False
        self.threads = {1: 'main'}  # alive threads (mode threads)
        self.listed = set()     # worker threads already in a threads answer (lldb-threads)

    def thread_of(self, i):
        if 0 <= i < len(self.steps):
            return self.steps[i].get('thread', 1)
        return 1

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
        if 'threads' in MODE:
            tid = step.get('thread', 1)
            if tid not in self.threads:
                self.threads[tid] = 'worker%d' % tid
                event('thread', {'reason': 'started', 'threadId': tid})
            if step.get('threadExit') in self.threads:
                del self.threads[step['threadExit']]
                event('thread', {'reason': 'exited', 'threadId': step['threadExit']})
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
            step = self.steps[i]
            if step.get('block') and kind == 'continue' and i not in self.unblocked:
                # the program runs here until Pause
                self.unblocked.add(i)
                self.pc = i
                self.running = True
                return
            self.enter(i)
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
        self.running = False
        body = {'reason': reason, 'threadId': self.thread_of(i) if 'threads' in MODE else 1,
                'allThreadsStopped': True}
        if 'preserve-focus' in MODE:
            body['preserveFocusHint'] = True
        if bp:
            body['hitBreakpointIds'] = [bp['id']]
        if text:
            body['text'] = text
            body['description'] = 'Exception: ' + text
        event('stopped', body)
        step = self.steps[i] if 0 <= i < len(self.steps) else {}
        if 'threads' in MODE and step.get('threadStarted'):
            self.threads[step['threadStarted']] = 'worker%d' % step['threadStarted']
            event('thread', {'reason': 'started', 'threadId': step['threadStarted']})
        if step.get('continuedOther'):
            event('continued', {'threadId': step['continuedOther'], 'allThreadsContinued': False})

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
        caps = {'supportsConfigurationDoneRequest': True}
        if 'no-cond-caps' not in MODE:
            caps.update({'supportsConditionalBreakpoints': True, 'supportsHitConditionalBreakpoints': True,
                         'supportsLogPoints': True})
        caps.update({
                'supportsFunctionBreakpoints': True, 'supportsSetVariable': True,
                'supportsEvaluateForHovers': True, 'supportsExceptionInfoRequest': True})
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
        launch_args.clear()
        launch_args.update(args)
        log('ARGS ' + json.dumps(args, sort_keys=True))
        if 'launch-fail' in MODE:
            respond(req, {'error': {'id': 1, 'format': 'could not launch: no such program'}},
                    success=False, message='launch failed')
            return
        if args.get('console') == 'integratedTerminal':
            # the program runs in rhun's terminal: the answer (its pid) is logged when it comes
            env = {'FAKEDAP_TERM': 'yes', 'FAKEDAP_GONE': None}
            env.update(args.get('termEnv') or {})
            send({'type': 'request', 'command': 'runInTerminal',
                  'arguments': {'kind': 'integrated', 'title': args.get('termTitle', 'Fake program'),
                                'cwd': args.get('cwd') or os.getcwd(),
                                'args': [1, 2] if args.get('termArgs') == 'numbers' else args.get('termArgs') or
                                [sys.executable, '-c', 'import os,sys; print("in the terminal", '
                                 'os.environ.get("FAKEDAP_TERM"), os.environ.get("FAKEDAP_GONE")); '
                                 'print("typed", sys.stdin.readline().strip())'],
                                'env': env}})
        if 'big' in MODE:
            event('output', {'category': 'stdout', 'output': 'B' * int(MODE['big']) + '\n'})
        if 'flood' in MODE:
            for k in range(int(MODE['flood'])):
                event('output', {'category': 'stdout', 'output': 'flood %d\n' % k})
        if 'bad-json' in MODE:
            write_raw(b'Content-Length: 5\r\n\r\n{bad}')
        if 'partial-pause' in MODE:
            body = json.dumps({'seq': 999, 'type': 'event', 'event': 'output',
                               'body': {'category': 'stdout', 'output': 'after the pause\n'}}).encode()
            write_raw(b'Content-Length: %d\r\n\r\n' % len(body) + body[:10])
            time.sleep(2)
            write_raw(body[10:])
        if 'no-length' in MODE:
            write_raw(b'Content-Length: none\r\n\r\n')
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
        if 'child' in MODE and launch_args.get('name') != 'Child':
            # a child session of the same debugger (startDebugging), its answer logged
            send({'type': 'request', 'command': 'startDebugging',
                  'arguments': {'request': 'launch',
                                'configuration': {'type': launch_args.get('type'), 'name': 'Child',
                                                  'program': launch_args.get('program'),
                                                  'stopOnEntry': True}}})
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
        if 'threads' not in MODE:
            respond(req, {'threads': [{'id': 1, 'name': 'main'}]})
            return
        listed = []
        for tid, name in sorted(prog.threads.items()):
            if 'lldb-threads' in MODE and tid != 1 and tid not in prog.listed:
                prog.listed.add(tid)        # left out this once
                continue
            listed.append({'id': tid, 'name': 'Thread 1' if 'lldb-threads' in MODE and tid == 1 else name})
        respond(req, {'threads': listed})
        return
    if cmd in ('continue', 'next', 'stepIn', 'stepOut', 'pause') and 'threads' in MODE \
            and args.get('threadId') not in prog.threads:
        respond(req, success=False, message='unknown thread %s' % args.get('threadId'))
        return
    if cmd == 'stackTrace' and 'threads' in MODE and args.get('threadId') != prog.thread_of(prog.pc):
        fid = prog.epoch * 100 + 90
        prog.frames[fid] = (prog.pc, -1)
        respond(req, {'stackFrames': [{'id': fid, 'name': 'wait%s' % args.get('threadId'), 'line': 0,
                                       'column': 1}], 'totalFrames': 1})
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
        pc, k = prog.frames[fid]
        step = prog.steps[pc]
        locals_ = step.get('locals', {})
        stack = step.get('stack')
        if stack and k > 0:
            locals_ = stack[k].get('locals', {})
        if k < 0:
            locals_ = {'waiting': True}     # another thread's frame
        scopes = [{'name': 'Locals', 'variablesReference': prog.ref(locals_), 'expensive': False},
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
            # paging: filter indexed with start and count, filter named (a list has none)
            log('VARIABLES filter=%s start=%s count=%s' % (args.get('filter'), args.get('start'), args.get('count')))
            if args.get('filter') == 'named':
                items = []
            elif args.get('filter') == 'indexed':
                start = args.get('start', 0)
                items = items[start:start + args.get('count', len(items))]
        respond(req, {'variables': [prog.var(n, v) for n, v in items]})
        return
    if cmd == 'evaluate':
        expr = args.get('expression', '')
        step = prog.steps[prog.pc] if 0 <= prog.pc < len(prog.steps) else {}
        value = step.get('locals', {})
        for part in expr.replace('->', '.').split('.'):
            if isinstance(value, dict) and part in value:
                value = value[part]
            else:
                respond(req, success=False, message="name '%s' is not defined" % expr)
                return
        v = prog.var(expr, value)
        respond(req, {'result': v['value'], 'type': v.get('type'), 'variablesReference': v['variablesReference']})
        return
    if cmd == 'setVariable':
        log('SETVARIABLE %s %s %s' % (args.get('variablesReference'), args.get('name'), args.get('value')))
        if args.get('value') == 'bad':
            respond(req, success=False, message='cannot set %s to bad' % args.get('name'))
            return
        respond(req, {'value': args.get('value'), 'type': 'int'})
        return
    if cmd in ('next', 'stepIn', 'stepOut') and 'fail-step' in MODE:
        respond(req, success=False, message='cannot step here')
        return
    if cmd in ('continue', 'next', 'stepIn', 'stepOut'):
        respond(req, {'allThreadsContinued': 'single-continue' not in MODE} if cmd == 'continue' else {})
        prog.run(cmd)
        return
    if cmd == 'pause':
        respond(req)
        if prog.running:
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


def orphan():
    """a child in the adapter's process group that ignores SIGTERM and outlives the adapter"""
    import signal
    pid = os.fork()
    if pid == 0:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        os.close(0)
        os.close(1)
        time.sleep(60)
        os._exit(0)
    log('orphan %d' % pid)


def listen(where):
    """--listen HOST:PORT: one connection replaces standard input and output"""
    global out, inp
    import socket
    if 'tcp-exit' in MODE:
        sys.stderr.write('could not listen: address already in use\n')
        sys.stderr.flush()
        log('tcp-exit')
        sys.exit(3)
    if 'tcp-never' in MODE:
        time.sleep(60)
        sys.exit(0)
    if 'tcp-late' in MODE:
        time.sleep(int(MODE['tcp-late']) / 1000)
    host, _, port = where.rpartition(':')
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind((host, int(port)))
    server.listen(1)
    sys.stdout.write('DAP server listening at: %s\n' % where)
    sys.stdout.flush()
    log('listening %s' % where)
    conn, _ = server.accept()
    server.close()
    log('accepted')
    inp = conn.makefile('rb')
    out = conn.makefile('wb')


def main():
    log('pid %d' % os.getpid())
    log('session %s cwd %s' % (os.environ.get('RHUN_DEBUG_SESSION'), os.getcwd()))
    log('argv ' + ' '.join(sys.argv[1:]))
    if '--listen' in sys.argv:
        listen(sys.argv[sys.argv.index('--listen') + 1])
    if 'orphan' in MODE:
        orphan()
    if 'junk-stdout' in MODE:
        write_raw(b'hello from the program\nmore junk\n')
    while True:
        msg = read_message()
        if msg is None:
            log('EOF')
            break
        if msg.get('type') == 'request':
            handle(msg)
        elif msg.get('type') == 'response':
            log('RESPONSE %s %s %s %s' % (msg.get('command'), msg.get('success'),
                                          json.dumps(msg.get('body'), sort_keys=True), msg.get('message')))
        flush_coalesced()


if __name__ == '__main__':
    main()
