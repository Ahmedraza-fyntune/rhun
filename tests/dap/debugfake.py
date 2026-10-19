#!/usr/bin/env python3
"""The fake debugger extension's own program (tests/dap/exts/rhun-tests/debugfake): it says hello
and waits; debug-resolve modes come with the debug feature's tests."""
import sys

print('hello 1', flush=True)
for line in sys.stdin:
    if line.startswith('0 bye'):
        break
