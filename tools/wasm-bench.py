#!/usr/bin/env python3
"""How a WebAssembly extension compares with a native build of the same extension: the test
extensions of tests/wasm (Rust, Go, C), each built for this machine and for wasm32-wasip1 (run in
`rhun --wasm-host`), driven over their pipes as rhun drives them.

  tools/wasm-bench.py [--rhun build/rhun] [--rounds 2000] [--text-kb 1024]

Measured: startup (spawn to the hello line), a message round trip (an event, the toast request it
causes, rhun's answer), and upper-casing a document of --text-kb KB (the text request, the work,
the replace request with the whole text back). Needs the toolchains tests/wasm-host.py uses."""
import argparse
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tests'))
import importlib.util
spec = importlib.util.spec_from_file_location('wasm_host', ROOT / 'tests/wasm-host.py')
wh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wh)


def native_rust():
    work = wh.OUT / 'rust'
    wh.build_rust()
    subprocess.run(['cargo', 'build', '-q', '--release'], cwd=work, check=True)
    return [str(work / 'target/release/wasmtest')]


def native_go():
    work = wh.OUT / 'go'
    wh.build_go()
    env = dict(os.environ, GOFLAGS='-mod=mod')
    env.pop('GOOS', None)
    env.pop('GOARCH', None)
    subprocess.run(['go', 'build', '-o', 'wasmtest-go-native', '.'], cwd=work, env=env, check=True,
                   capture_output=True)
    return [str(work / 'wasmtest-go-native')]


def native_c():
    work = wh.OUT / 'c'
    work.mkdir(parents=True, exist_ok=True)
    out = work / 'wasmtest-c-native'
    subprocess.run(['cc', '-O2', '-I', str(wh.SDK / 'c'), str(wh.SRC / 'c/main.c'), '-o', str(out)], check=True,
                   capture_output=True)
    return [str(out)]


class Session:
    def __init__(self, argv, name, env):
        self.name = name
        t0 = time.perf_counter()
        self.p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env, bufsize=0)
        self.hello = self.line()
        self.startup = time.perf_counter() - t0
        self.send(b'0 ready -\n')

    def line(self):
        out = bytearray()
        while not out.endswith(b'\n'):
            c = self.p.stdout.read(1)
            if not c:
                raise EOFError('the extension ended')
            out += c
        return out.decode()

    def read(self, n):
        out = bytearray()
        while len(out) < n:
            c = self.p.stdout.read(n - len(out))
            if not c:
                raise EOFError
            out += c
        return bytes(out)

    def send(self, data):
        self.p.stdin.write(data)
        self.p.stdin.flush()

    def request(self):
        """the next request line: (id, verb, fields)"""
        f = self.line().split()
        return f[0], f[1], f[2:]

    def toast_round(self):
        self.send(('0 run %s.hello 0\n' % self.name).encode())
        rid, verb, fields = self.request()
        self.read(int(fields[-1]))
        self.send(('ok %s\n' % rid).encode())

    def upper(self, text):
        self.send(('0 run %s.upper 7\n' % self.name).encode())
        rid, verb, fields = self.request()             # text 7
        self.send(('ok %s 1 %d\n' % (rid, len(text))).encode() + text)
        rid, verb, fields = self.request()             # replace 7 1 1 1 L C LEN
        body = self.read(int(fields[-1]))
        self.send(('ok %s 2\n' % rid).encode())
        rid, verb, fields = self.request()             # the toast
        self.read(int(fields[-1]))
        self.send(('ok %s\n' % rid).encode())
        return body

    def close(self):
        self.send(b'0 bye\n')
        self.p.stdin.close()
        self.p.wait(timeout=10)


def measure(label, argv, name, rounds, text, env):
    starts = []
    for _ in range(5):
        s = Session(argv, name, env)
        starts.append(s.startup)
        s.close()
    s = Session(argv, name, env)
    for _ in range(50):
        s.toast_round()
    t0 = time.perf_counter()
    for _ in range(rounds):
        s.toast_round()
    rt = (time.perf_counter() - t0) / rounds
    t0 = time.perf_counter()
    body = s.upper(text)
    up = time.perf_counter() - t0
    assert body == text.upper(), 'upper went wrong'
    s.close()
    return statistics.median(starts), rt, up


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rhun', default=str(ROOT / 'build/rhun'))
    ap.add_argument('--rounds', type=int, default=2000)
    ap.add_argument('--text-kb', type=int, default=1024)
    args = ap.parse_args()
    text = (b'the quick brown fox jumps over the lazy dog\n' * (args.text_kb * 1024 // 44 + 1))[:args.text_kb * 1024]
    env = dict(os.environ, RHUN_EXTENSION='rhun-tests/bench')
    rows = []
    for lang, name, native, builder in (('Rust', 'wasmtest', native_rust, wh.build_rust),
                                        ('Go', 'wasmtest-go', native_go, wh.build_go),
                                        ('C', 'wasmtest-c', native_c, wh.build_c)):
        try:
            nat = native()
            wasm = builder()
        except (OSError, subprocess.CalledProcessError) as e:
            print('%s: cannot build: %s' % (lang, e))
            continue
        for kind, argv in (('native', nat), ('wasm', [args.rhun, '--wasm-host', str(wasm)])):
            st, rt, up = measure(lang, argv, name, args.rounds, text, env)
            rows.append((lang, kind, st, rt, up))
    print('| Extension | Build | Startup to hello | Round trip | Upper-case %d KB |' % args.text_kb)
    print('| --- | --- | --- | --- | --- |')
    for lang, kind, st, rt, up in rows:
        print('| %s | %s | %.1f ms | %.1f us | %.1f ms |' % (lang, kind, st * 1000, rt * 1e6, up * 1000))


if __name__ == '__main__':
    main()
