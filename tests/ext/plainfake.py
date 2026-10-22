#!/usr/bin/env python3
"""A busy extension without features for the host tests: after hello it sends "ID status 1" + a
character every 10 ms, and reads (and drops) what rhun sends until bye or the end of its input."""
import sys
import threading
import time

out = sys.stdout.buffer
lock = threading.Lock()


def chatter():
    n = 1
    while True:
        with lock:
            out.write(b'%d status 1\n%c' % (n, b'abcdefgh'[n % 8]))
            out.flush()
        n += 1
        time.sleep(0.01)


def main():
    with lock:
        out.write(b'hello 1\n')
        out.flush()
    threading.Thread(target=chatter, daemon=True).start()
    for line in sys.stdin.buffer:
        if line.startswith(b'0 bye'):
            return


try:
    main()
except (BrokenPipeError, OSError):
    pass
