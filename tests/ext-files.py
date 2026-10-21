#!/usr/bin/env python3
"""Files and search for extensions (resources group, feature files): find-files by glob through git
ls-files (.gitignore, untracked files, no deleted ones) or a walk of the folder (ignored files too,
the exclude setting, hidden names, folders, links), search-text with literals, ignore case, whole
words and RNRX programs, unsaved editor text, skipped binary and big files, previews of long lines,
batches, MAX, cancel, and the errors before a run. The fake extension is tests/ext/res.py."""
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import unittest

lifecycle = __import__('ext-lifecycle')
host = __import__('ext-host')
RES = lifecycle.RES
HAS_GIT = shutil.which('git') is not None


def rnrx(instrs, flags=0, classes=(), ranges=()):
    """an RNRX program: instructions (opcode, X, Y, Z), classes (first range, count), ranges"""
    total = 48 + 16 * len(instrs) + 8 * len(classes) + 8 * len(ranges)
    out = struct.pack('<12I', 0x58524e52, 1, 0x00100000, flags, 0, len(instrs), len(classes),
                      len(ranges), 0, 0, total, 0)
    for i in instrs:
        out += struct.pack('<4I', *i)
    for c in classes:
        out += struct.pack('<2I', *c)
    for r in ranges:
        out += struct.pack('<2I', *r)
    return out


def literal_program(text, flags=0, anchor=False):
    ins = [(4, 1, 0, 0)] if anchor else []
    ins += [(1, ord(c), 0, 0) for c in text] + [(0, 0, 0, 0)]
    return rnrx(ins, flags)


class Files(lifecycle.Base):
    def setUp(self):
        super().setUp()
        (self.work / 'config/rhun/config').write_text(host.CONFIG.replace('enabled = false', 'enabled = true'),
                                                      encoding='utf-8')
        for f in ('a.txt', 'b.go', 'u.txt'):
            (self.proj / f).unlink()
        self.root = self.work / 'exts'
        self.manifest()
        self.state = self.work / 'state/rhun/extensions/rt--files'
        self.state.mkdir(parents=True)
        self.env['RES_ARGS'] = '{state}/args.txt'
        self.env['RES_LOG'] = '{state}/res.log'
        self.env['RES_FEATURES'] = 'files'
        self.env['GIT_CONFIG_NOSYSTEM'] = '1'

    def manifest(self, needs='project = read\n'):
        folder = self.root / 'rt' / 'files'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'extension.ini').write_text(
            'name = files\nowner = rt\ntitle = Files\nversion = 1\nprotocol = 1\n'
            f'runtime = python3\nrun = {RES.as_posix()}\non = command\n'
            '[commands]\nrequest = Request\nbatch = Batch\nraw = Raw\n'
            f'[needs]\nrun = python3\n{needs}', encoding='utf-8')

    def tree(self, git=True):
        p = self.proj
        files = {
            'src/main.rs': 'fn main() {\n    // TODO: write it\n    let todo = 1; // todos are TODOs\n}\n',
            'src/lib.rs': 'pub fn f() {} // TODO(lib)\n',
            'src/deep/x/y.rs': 'TODO deep\n',
            'README.md': '# Title\n\nNothing to do. todo\n',
            'docs/guide.md': 'TODO first\r\nsecond TODO\r\n',
            'build/out.txt': 'TODO built\n',
            'debug.log': 'TODO log\n',
            '.hidden/x.txt': 'TODO hidden\n',
            'node_modules/m/index.js': 'TODO module\n',
            'deleted.txt': 'TODO gone\n',
        }
        for name, text in files.items():
            (p / name).parent.mkdir(parents=True, exist_ok=True)
            (p / name).write_bytes(text.encode())
        (p / '.gitignore').write_text('build/\n*.log\n', encoding='utf-8')
        if git:
            g = ['git', '-C', str(p), '-c', 'user.name=t', '-c', 'user.email=t@t']
            subprocess.run(['git', 'init', '-q', str(p)], check=True, env=self.env)
            subprocess.run(g + ['add', '-A'], check=True, env=self.env)
            subprocess.run(g + ['commit', '-qm', 'one'], check=True, env=self.env)
            (p / 'deleted.txt').unlink()
            (p / 'new.txt').write_text('untracked TODO\n', encoding='utf-8')

    def run_files(self, lines, actions=(), files=(), cmd='batch', wait=1200):
        (self.state / 'args.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
        log = self.state / 'res.log'
        if log.exists():
            log.unlink()
        return self.run_editor([f'cmd rt/files.{cmd}', 'wait-ext files running', f'wait {wait}', *actions],
                               exts=self.root, files=files)

    def run_seq(self, lines, wait=700, files=()):
        """each line as a request of its own, one after the other"""
        (self.state / 'args.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
        log = self.state / 'res.log'
        if log.exists():
            log.unlink()
        actions = []
        for _ in lines:
            actions += ['cmd rt/files.request', 'wait-ext files running', f'wait {wait}']
        return self.run_editor(actions, exts=self.root, files=files)

    def messages(self):
        """the log as (line, body) pairs: a found event's body follows it as "body " + LEN bytes"""
        p = self.state / 'res.log'
        data = p.read_bytes() if p.exists() else b''
        out = []
        i = 0
        while i < len(data):
            j = data.index(b'\n', i)
            line = data[i:j].decode(errors='replace')
            i = j + 1
            body = None
            m = re.match(r'0 found \d+ (\d+)$', line)
            if m and data[i:i + 5] == b'body ':
                n = int(m.group(1))
                body = data[i + 5:i + 5 + n]
                i += 5 + n + 1
            out.append((line, body))
        return out

    def replies(self):
        return [l for l, _ in self.messages() if l.startswith(('ok ', 'error '))]

    def found(self, rid=1):
        """the records of request rid's batches"""
        recs = []
        for line, body in self.messages():
            if body is None or not line.startswith(f'0 found {rid} '):
                continue
            head, _, rest = body.partition(b'\n')
            n = int(head)
            recs.append([])
            for _ in range(n):
                h, _, rest = rest.partition(b'\n')
                f = h.split(b' ')
                if len(f) == 2:                 # find-files: FOLDER PATH_LEN
                    plen = int(f[1])
                    recs[-1].append((int(f[0]), rest[:plen].decode()))
                    rest = rest[plen:]
                else:                           # search-text: FOLDER DOC VERSION PATH_LEN M
                    plen, m = int(f[3]), int(f[4])
                    path = rest[:plen].decode()
                    rest = rest[plen:]
                    matches = []
                    for _ in range(m):
                        mh, _, rest = rest.partition(b'\n')
                        line_no, col, end, pre, tlen = map(int, mh.split(b' '))
                        matches.append((line_no, col, end, pre, rest[:tlen].decode()))
                        rest = rest[tlen:]
                    recs[-1].append((int(f[0]), int(f[1]), int(f[2]), path, matches))
            self.assertEqual(rest, b'', 'a batch holds exactly its records')
        return recs

    def paths(self, rid=1):
        return sorted(p for batch in self.found(rid) for _, p in batch)

    def find(self, flags=0, globs='', max_=1000, folder=1):
        body = globs.replace('\n', '\\n')
        return f'find-files {folder} {max_} {flags} {{LEN}}|{body}'

    def search(self, pattern, flags=0, globs='', max_=1000, folder=0):
        if isinstance(pattern, bytes):
            # a program: written to a file the fake extension cannot read as text; sent through
            # RES_ARGS as hex below
            raise TypeError
        p = pattern.encode()
        g = globs.encode()
        body = f'{len(p)} {len(g)}\n'.encode() + p + g
        return f'search-text {folder} {max_} {flags} {{LEN}}|' + body.decode().replace('\n', '\\n')

    # ---------------- find-files ----------------

    @unittest.skipUnless(HAS_GIT, 'git')
    def test_git_lists_tracked_and_untracked_files(self):
        self.tree()
        self.run_files([self.find()])
        self.assertEqual(self.paths(), ['.gitignore', '.hidden/x.txt', 'README.md', 'docs/guide.md',
                                        'new.txt', 'src/deep/x/y.rs', 'src/lib.rs', 'src/main.rs'],
                         self.messages())
        self.assertEqual(self.replies(), ['ok 1 8 complete'])
        self.assertTrue(all(b[0][0] == 1 for b in self.found()), 'folder id 1, the primary')

    @unittest.skipUnless(HAS_GIT, 'git')
    def test_ignored_files_too_walk_the_folder(self):
        self.tree()
        self.run_files([self.find(1)])
        got = self.paths()
        for p in ('build/out.txt', 'debug.log', 'node_modules/m/index.js'):
            self.assertIn(p, got)               # .gitignore and the exclude setting do not apply
        self.assertNotIn('deleted.txt', got)
        self.assertFalse(any(p.startswith('.git/') for p in got), got)

    def test_without_git_the_walk_leaves_out_excluded_names(self):
        self.tree(git=False)
        self.run_files([self.find()], cmd='request')
        got = self.paths()
        self.assertIn('debug.log', got)         # no git: .gitignore is not read
        self.assertNotIn('build/out.txt', got)  # build and node_modules are in the exclude setting
        self.assertNotIn('node_modules/m/index.js', got)
        self.assertIn('.hidden/x.txt', got)

    def test_hidden_names_and_folders(self):
        self.tree(git=False)
        self.run_files([self.find(2 | 8)], cmd='request')
        got = self.paths()
        self.assertNotIn('.hidden/x.txt', got)
        self.assertNotIn('.hidden/', got)
        self.assertNotIn('.gitignore', got)
        for d in ('src/', 'src/deep/', 'src/deep/x/', 'docs/'):
            self.assertIn(d, got)

    @unittest.skipUnless(HAS_GIT, 'git')
    def test_folders_of_a_git_list(self):
        self.tree()
        self.run_files([self.find(8, '+src/**\n')], cmd='request')
        self.assertEqual(self.paths(), ['src/', 'src/deep/', 'src/deep/x/', 'src/deep/x/y.rs',
                                        'src/lib.rs', 'src/main.rs'])

    @unittest.skipUnless(HAS_GIT, 'git')
    def test_globs(self):
        self.tree()
        self.run_seq([self.find(0, '+*.rs\n'), self.find(0, '+src/**\n-**/lib.rs\n'),
                      self.find(0, '+*.{md,txt}\n'), self.find(0, '-src\n-docs\n'),
                      self.find(0, '+src/*.rs\n'), self.find(0, '+[Rd]*\n'), self.find(0, '+src/m?in.rs\n')])
        self.assertEqual(self.paths(1), ['src/deep/x/y.rs', 'src/lib.rs', 'src/main.rs'])
        self.assertEqual(self.paths(2), ['src/deep/x/y.rs', 'src/main.rs'])
        self.assertEqual(self.paths(3), ['.hidden/x.txt', 'README.md', 'docs/guide.md', 'new.txt'])
        self.assertEqual(self.paths(4), ['.gitignore', '.hidden/x.txt', 'README.md', 'new.txt'])
        self.assertEqual(self.paths(5), ['src/lib.rs', 'src/main.rs'])
        self.assertEqual(self.paths(6), ['README.md'])
        self.assertEqual(self.paths(7), ['src/main.rs'])

    @unittest.skipUnless(HAS_GIT, 'git')
    def test_max_and_batches(self):
        self.tree()
        many = self.proj / 'many'
        many.mkdir()
        for i in range(4500):
            (many / f'f{i:05}.txt').write_text('x\n')
        self.run_files([self.find(0, '', 100000), self.find(0, '', 3)], cmd='request', wait=2500)
        batches = self.found(1)
        self.assertGreaterEqual(len(batches), 3)
        self.assertTrue(all(len(b) <= 2000 for b in batches))
        self.assertEqual(sum(len(b) for b in batches), 4508)
        self.assertIn('ok 1 4508 complete', self.replies())
        self.run_files([self.find(0, '', 3)], cmd='request', wait=1500)
        self.assertEqual(len(self.paths(1)), 3)
        self.assertEqual(self.replies(), ['ok 1 3 limit'])

    def test_links_to_folders(self):
        if os.name == 'nt':
            self.skipTest('symbolic links')
        self.tree(git=False)
        (self.proj / 'loop').symlink_to(self.proj)
        (self.proj / 'docs2').symlink_to(self.proj / 'docs')
        self.run_files([self.find()], cmd='request')
        got = self.paths()
        self.assertNotIn('docs2/guide.md', got)
        self.run_files([self.find(4)], cmd='request')
        got = self.paths()
        self.assertIn('docs2/guide.md', got)
        self.assertFalse(any(p.startswith('loop/') for p in got), 'a link back is read once')

    # ---------------- errors ----------------

    def test_errors_before_a_run(self):
        self.tree(git=False)
        self.run_files([self.find(0, '', 1000, 7), self.find(16), self.find(0, '', 100001), self.find(0, '', 0),
                        self.find(0, 'GLOB\n'), self.find(0, '+a{b\n'), self.find(0, '+[ab\n'),
                        self.find(), self.find(), 'find-files 1 10 0'], wait=1500)
        r = self.replies()
        self.assertIn('error 1 nofile no such folder', r)
        self.assertTrue(any(x.startswith('error 2 syntax') for x in r), r)
        self.assertIn('error 3 toobig MAX is at most 100000', r)
        self.assertTrue(any(x.startswith('error 4 syntax') for x in r), r)
        for i in (5, 6, 7):
            self.assertTrue(any(x.startswith(f'error {i} syntax') for x in r), r)
        self.assertIn('error 9 busy a find or search of this extension is running', r)
        self.assertTrue(any(x.startswith('ok 8 ') for x in r), r)
        self.assertTrue(any(x.startswith('error 10 syntax') for x in r), r)

    def test_needs_project_and_the_feature(self):
        self.tree(git=False)
        self.manifest(needs='')
        self.run_files([self.find()], cmd='request')
        self.assertEqual(self.replies(), ['error 1 needs project=read'])
        self.manifest()
        self.env['RES_FEATURES'] = ''
        self.run_files([self.find()], cmd='request')
        self.assertEqual(self.replies(), ['error 1 unknown no such request'])

    def test_cancel(self):
        self.tree(git=False)
        self.run_files([self.search('TODO'), 'cancel 1'], wait=800)
        r = self.replies()
        self.assertIn('error 1 cancelled', r)
        self.assertIn('ok 2', r)
        self.assertEqual(self.found(1), [])

    # ---------------- search-text ----------------

    @unittest.skipUnless(HAS_GIT, 'git')
    def test_literal_search(self):
        self.tree()
        self.run_files([self.search('TODO')], cmd='request')
        groups = {g[3]: g for b in self.found() for g in b}
        self.assertEqual(sorted(groups), sorted(['docs/guide.md', '.hidden/x.txt', 'new.txt', 'src/deep/x/y.rs',
                                                 'src/lib.rs', 'src/main.rs']))
        main = groups['src/main.rs']
        self.assertEqual(main[1:3], (0, 0), 'read from disk')
        self.assertEqual(main[4], [(2, 8, 12, 1, '    // TODO: write it'),
                                   (3, 32, 36, 1, '    let todo = 1; // todos are TODOs')])
        guide = groups['docs/guide.md']
        self.assertEqual([m[:3] for m in guide[4]], [(1, 1, 5), (2, 8, 12)])
        self.assertEqual(guide[4][0][4], 'TODO first', 'no CR in the preview')
        r = self.replies()
        self.assertEqual(r, ['ok 1 8 6 0 complete'], r)

    @unittest.skipUnless(HAS_GIT, 'git')
    def test_ignore_case_and_whole_words(self):
        self.tree()
        self.run_seq([self.search('todo', 16, '+src/main.rs\n'), self.search('TODO', 32, '+src/main.rs\n'),
                      self.search('todo', 48, '+src/main.rs\n')])
        m1 = [m[:3] for g in sum(self.found(1), []) for m in g[4]]
        self.assertEqual(m1, [(2, 8, 12), (3, 9, 13), (3, 22, 26), (3, 32, 36)])
        m2 = [m[:3] for g in sum(self.found(2), []) for m in g[4]]
        self.assertEqual(m2, [(2, 8, 12)])
        m3 = [m[:3] for g in sum(self.found(3), []) for m in g[4]]
        self.assertEqual(m3, [(2, 8, 12), (3, 9, 13)])

    def test_regex_programs(self):
        self.tree(git=False)
        prog = literal_program('TODO', anchor=True)         # ^TODO, line by line
        progi = literal_program('TODO', flags=2)            # todo with i (scalars canonical: upper case)
        digit = rnrx([(1, ord('('), 0, 0), (3, 0, 0, 0), (0, 0, 0, 0)], classes=[(0, 1)], ranges=[(ord('a'), ord('z'))])
        bad = b'RNRX' + b'\x00' * 10
        lines = []
        for p, g in ((prog, ''), (progi, '+src/main.rs\n'), (digit, ''), (bad, '')):
            body = f'{len(p)} {len(g)}\n'.encode() + p + g.encode()
            lines.append(body)
        # bodies with arbitrary bytes go through a file of requests the fake extension sends as is
        reqs = self.state / 'raw.bin'
        log = self.state / 'res.log'
        if log.exists():
            log.unlink()
        # one run at a time: each program in a session of its own, the logs joined with ids 1 to 4
        joined = b''
        for i, body in enumerate(lines, 1):
            reqs.write_bytes(f'search-text 0 100 64 {len(body)}\n'.encode() + body)
            self.env['RES_RAW'] = '{state}/raw.bin'
            self.run_editor(['cmd rt/files.raw', 'wait-ext files running', 'wait 900'], exts=self.root, files=())
            joined += log.read_bytes().replace(b'0 found 1 ', f'0 found {i} '.encode()) \
                .replace(b'ok 1 ', f'ok {i} '.encode()).replace(b'error 1 ', f'error {i} '.encode())
            log.unlink()
        log.write_bytes(joined)
        f1 = sorted((g[3], [m[:3] for m in g[4]]) for g in sum(self.found(1), []))
        self.assertIn(('docs/guide.md', [(1, 1, 5)]), f1)
        self.assertIn(('src/deep/x/y.rs', [(1, 1, 5)]), f1)
        self.assertNotIn('src/main.rs', [x[0] for x in f1])
        f2 = [m[:3] for g in sum(self.found(2), []) for m in g[4]]
        self.assertEqual(f2, [(2, 8, 12), (3, 9, 13), (3, 22, 26), (3, 32, 36)])
        f3 = sorted((g[3], [m[:3] for m in g[4]]) for g in sum(self.found(3), []))
        self.assertIn(('src/lib.rs', [(1, 22, 24)]), f3)
        r = self.replies()
        self.assertTrue(any(x.startswith('error 4 syntax') for x in r), r)

    def test_unsaved_text_is_searched(self):
        self.tree(git=False)
        main = self.proj / 'src/main.rs'
        self.run_files([self.search('UNSAVED', 0, '+src/main.rs\n')], cmd='request',
                       actions=[], files=('src/main.rs',))
        self.assertEqual(self.found(), [])
        (self.state / 'args.txt').write_text(self.search('UNSAVED', 0, '+src/main.rs\n') + '\n')
        self.run_editor(['key ctrl+End', 'type UNSAVED here', 'cmd rt/files.request', 'wait-ext files running',
                         'wait 1200'], exts=self.root, files=('src/main.rs',))
        g = sum(self.found(), [])
        self.assertEqual(len(g), 1)
        self.assertGreater(g[0][1], 0, 'the document')
        self.assertGreater(g[0][2], 0, 'its version')
        self.assertEqual(g[0][4][0][4], 'UNSAVED here')
        self.assertNotIn('UNSAVED', main.read_text())

    def test_binary_big_and_long_lines(self):
        self.tree(git=False)
        (self.proj / 'bin.dat').write_bytes(b'TODO\x00\x01')
        (self.proj / 'big.txt').write_bytes(b'x' * (8 * 1024 * 1024 + 1))
        long_line = 'a' * 1000 + 'TODO' + 'é' * 400 + '\n'
        (self.proj / 'long.txt').write_text(long_line, encoding='utf-8')
        self.run_files([self.search('TODO', 0, '+*.dat\n+big.txt\n+long.txt\n')], cmd='request', wait=1500)
        g = sum(self.found(), [])
        self.assertEqual([x[3] for x in g], ['long.txt'])
        line_no, col, end, pre, text = g[0][4][0]
        self.assertEqual((line_no, col, end), (1, 1001, 1005))
        self.assertEqual(pre, 1001 - 128)
        self.assertLessEqual(len(text.encode()), 512)
        self.assertTrue(text.startswith('a' * 128 + 'TODO'))
        self.assertEqual(self.replies(), ['ok 1 1 1 2 complete'])

    def test_search_max(self):
        self.tree(git=False)
        self.run_files([self.search('TODO', 0, '', 2)], cmd='request')
        n = sum(len(g[4]) for g in sum(self.found(), []))
        self.assertEqual(n, 2)
        r = self.replies()
        self.assertTrue(r and r[0].startswith('ok 1 2 ') and r[0].endswith(' limit'), r)


if __name__ == '__main__':
    unittest.main()
