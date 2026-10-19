#!/usr/bin/env python3
"""Private managed parser parity, resource limits, malformed spans and cleanup."""
import argparse
import itertools
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--exe', type=Path)
parser.add_argument('--grammar-exe', type=Path, required=True)
parser.add_argument('--theme-exe', type=Path, required=True)
parser.add_argument('--wine')
parser.add_argument('--wine-drive-root', type=Path)
args = parser.parse_args()
runner = [args.wine] if args.wine else []
grammar = args.grammar_exe.resolve()
theme = args.theme_exe.resolve()


def native(path):
    if args.wine:
        return 'C:/' + str(path.relative_to(args.wine_drive_root)).replace(os.sep, '/')
    return str(path)


def execute(binary, *arguments, size=None, timeout=20):
    result = subprocess.run([*runner, str(binary), *map(str, arguments)], capture_output=True, timeout=timeout)
    assert result.returncode == 0, (binary, arguments, result.returncode, result.stdout, result.stderr)
    if size is not None:
        assert len(result.stdout) == size and not result.stderr, (result.stdout, result.stderr)
    return result.stdout


def colliding_words(count):
    """Meet in the middle, independently inverting FNV modulo the largest table size."""
    alphabet = b'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    mask = (1 << 17) - 1
    prime = 16777619
    inverse = pow(prime, -1, 1 << 17)
    prefixes = {}
    for triple in itertools.product(alphabet, repeat=3):
        value = 2166136261 & mask
        for byte in triple:
            value = ((value ^ byte) * prime) & mask
        prefixes.setdefault(value, []).append(bytes(triple))
    words = []
    for triple in itertools.product(alphabet, repeat=3):
        value = 0
        for byte in reversed(triple):
            value = ((value * inverse) & mask) ^ byte
        for prefix in prefixes.get(value, ()):
            words.append(prefix + bytes(triple))
            if len(words) == count:
                assert len(set(words)) == count
                return words
    raise AssertionError('insufficient independent FNV collision corpus')


execute(grammar, '--all')
execute(grammar, '--guard')
execute(theme, '--all')
owner = grammar.with_name('ext_prepare_owner_test' + ('.exe' if grammar.suffix == '.exe' else ''))
if owner.exists():
    execute(owner)
print('ok all built-in grammar semantics, theme palettes, guard-page span and owner lifetime', flush=True)

with tempfile.TemporaryDirectory(prefix='rhun-ext-prepare-', dir=args.wine_drive_root) as temporary:
    folder = Path(temporary).resolve()
    source = folder / 'case.syn'

    def check_grammar(body, expected=0, words=None, regions=None, lines=None, timeout=20):
        source.write_bytes(body.encode() if isinstance(body, str) else body)
        values = struct.unpack('<8q', execute(grammar, native(source), size=64, timeout=timeout))
        assert values[0] == expected, (expected, values, source.read_bytes()[:200])
        assert values[4:] == (64, 0, 0, 0), values  # EO only, no leak/warning/registry publication
        if expected == 0:
            for actual, want in zip(values[1:4], (words, regions, lines)):
                if want is not None:
                    assert actual == want, (actual, want)

    check_grammar('name = Test\nkeywords = a b c\n', words=3)
    check_grammar('name = Test\ncase = insensitive\nkeywords = Word word WORD\n', words=1)
    check_grammar('name = Test\nkeywords = Word word WORD\n', words=3)
    check_grammar('name = ' + 'n' * 128 + '\n')
    for body in ['name = ' + 'n' * 129 + '\n', 'keywords = a\n', 'name = Test\nunknown = bad\n',
                 'name = Test\nregion = a b not-a-class\n', b'name = Good\0\xff\n',
                 b'name = Good\nkeywords = word\0hidden\n', b'name = Good\n#bad \xff\n',
                 'name = Test\n#control\u0085\n']:
        check_grammar(body, -1011)
    words = ' '.join(f'word{index:06d}' for index in range(65536))
    check_grammar('name = Words\nkeywords = ' + words + '\n', words=65536)
    check_grammar('name = Words\nkeywords = ' + words + ' word000000\n', words=65536)
    check_grammar('name = Words\nkeywords = ' + words + ' another\n', -1007)
    check_grammar('name = Rules\n' + 'region = a b string\n' * 4096, regions=4096)
    check_grammar('name = Rules\n' + 'region = a b string\n' * 4096 + 'line = c comment\n', -1007)
    check_grammar('name = Rules\n' + 'line = a string\n' * 4096, lines=4096)
    check_grammar('name = Rules\n' + 'line = a string\n' * 4097, -1007)
    prefix = b'name = Bytes\n#'
    body = prefix + b'x' * (2 * 1024 * 1024 - len(prefix))
    check_grammar(body)
    check_grammar(body + b'x', -1007)
    collision = b'name = Collision\nkeywords = ' + b' '.join(colliding_words(65536)) + b'\n'
    started = time.monotonic()
    check_grammar(collision, -1007, timeout=10)
    assert time.monotonic() - started < 5, 'managed collision budget did not bound parser work'
    print('ok grammar counted names, distinct words, combined rules, byte and collision work bounds', flush=True)

    def check_theme(body, expected=0, kind=None):
        source.write_bytes(body.encode() if isinstance(body, str) else body)
        values = struct.unpack('<3q', execute(theme, native(source), size=24))
        assert values[:2] == (expected, 1), (values, source.read_bytes()[:200])
        if expected == 0 and kind is not None:
            assert values[2] == kind, values

    check_theme('name = Quiet\nkind = dark\nbg = #010203\n', kind=1)
    check_theme('kind = light\nfg = #abcdef\n', kind=0)
    check_theme('future = ignored\n', kind=1)
    for body in ['kind = mystery\n', 'bg = nope\n', 'bg = #12345\n', 'bg = #12zzzz\n', 'bg = #1234567\n',
                 'bg = #12ggggff\n', 'bg = #123456ffjunk\n', b'bg = #000000\0bad\n',
                 b'#invalid \xff\n', '#control\u0085\n']:
        check_theme(body, -1012)
    check_theme(b'#' + b'x' * 65535)
    check_theme(b'#' + b'x' * 65536, -1007)
    print('ok strict private theme kind/color/text/byte checks preserve active palette and registry', flush=True)
