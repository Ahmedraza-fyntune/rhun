#!/usr/bin/env python3
"""Native metadata persists between processes on isolated macOS pasteboards."""
from pathlib import Path
import subprocess
import sys
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / 'build/mac_clipboard_metadata_test'


@unittest.skipUnless(sys.platform == 'darwin' and BINARY.exists(), 'macOS native fixture required')
class ClipboardMetadata(unittest.TestCase):
    def command(self, *arguments):
        result = subprocess.run([str(BINARY), *arguments], capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, (arguments, result.stdout, result.stderr))
        self.assertEqual(result.stdout, b'', (arguments, result.stdout))
        self.assertEqual(result.stderr, b'', (arguments, result.stderr))

    def test_writer_exit_then_fresh_reader(self):
        for kind in ('multi', 'line', 'unicode', 'empty', 'raw', 'malformed', 'version',
                     'native-only', 'native-first', 'native-second', 'plain'):
            with self.subTest(kind=kind):
                name = 'com.r13.rhun.clipboard-test.' + str(uuid.uuid4())
                try:
                    self.command('--write', name, kind)
                    self.command('--read', name, kind)
                finally:
                    self.command('--clear', name)


if __name__ == '__main__':
    unittest.main(verbosity=2)
