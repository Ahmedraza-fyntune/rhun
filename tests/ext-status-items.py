#!/usr/bin/env python3
"""Status bar items (docs/extensions/v1.1.md "Feature: status-items"): manifest [status] items and
runtime status-item / status-remove, priority order on both sides, when clauses, icons ("$(play)",
ext:NAME from [icons]), colors and backgrounds, tooltips, a click running the item's command with
FROM ref, the 8-item cap, the 40 % budget, v1's status text as _v1, cleanup when the program stops."""
import re
import struct
import unittest
import zlib

contribhost = __import__('contribhost')
HELLO = 'hello 1 status-items command-args'


def body(align='right', prio=0, text='x', tip='', extra=b''):
    t, p = text.encode(), tip.encode()
    return (f'{align} {prio} {len(t)} {len(p)} {len(extra)}\n'.encode() + t + p + extra).decode('latin-1')


def png(path, rgba):
    """A 4x4 PNG of one color."""
    raw = b''.join(b'\0' + bytes(rgba) * 4 for _ in range(4))
    def chunk(t, b): return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 6, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


MANIFEST = '''[status]
tasks.text = $(play) Tasks
tasks.tooltip = Run a task of this project
tasks.command = run_task
tasks.args = all
tasks.align = left
tasks.priority = 20
rust.text = Rust only
rust.when = resourceLang == Rust
low.text = low
low.priority = -5
high.text = high
high.priority = 50
'''


class StatusItems(contribhost.Contrib):
    def setUp(self):
        super().setUp()
        (self.proj / 'main.rs').write_text('fn main() {}\n', encoding='utf-8')

    def exts(self, manifest=MANIFEST, actions=None, hello=HELLO):
        root = self.work / 'exts'
        actions = actions or {}
        commands = ['run_task = Run Task'] + [k + ' = ' + k for k in actions]
        self.make_ext(root, hello=hello, actions=actions, commands=commands, extra=manifest)
        return root

    def items(self, out):
        """print-status lines as dicts, by item name."""
        res = {}
        for line in out:
            m = re.match(r'side=(\S+) prio=(\S+) owner=(\S+) item=(\S+) text=(.*) tooltip=(.*) command=(\S*) '
                         r'shown=(\d) at=(\S+)$', line)
            if m:
                res[m.group(4)] = dict(zip(('side', 'prio', 'owner', 'item', 'text', 'tooltip', 'command', 'shown',
                                            'at'), m.groups()), line=line)
        return res

    def runs(self):
        lines = self.contrib_log()
        return [(l, lines[i + 1]) for i, l in enumerate(lines) if l.startswith('0 run ')]

    def test_manifest_items_order_and_when(self):
        out = self.run_editor(exts=self.exts(), files=('a.txt',), drop_waits=True, actions=[
            'print-status', 'open ' + (self.proj / 'main.rs').as_posix(), 'print-status'])
        first = self.items(out[:len(out) // 2])
        second = self.items(out[len(out) // 2:])
        self.assertEqual(first['rust']['shown'], '0')
        self.assertEqual(second['rust']['shown'], '1')
        x = {k: int(v['at'].split(',')[0]) for k, v in second.items()}
        # right side: higher priority further left
        self.assertLess(x['high'], x['rust'])
        self.assertLess(x['rust'], x['low'])
        self.assertEqual(second['tasks']['side'], 'left')
        self.assertLess(x['tasks'], x['high'])
        self.assertIn('tooltip=Run a task of this project', second['tasks']['line'])

    def test_click_runs_the_command(self):
        out = self.run_editor(exts=self.exts(), files=('main.rs',), drop_waits=True, actions=['print-status'])
        x, y, w, h = map(int, self.items(out)['tasks']['at'].split(','))
        self.run_editor(exts=self.exts(), files=('main.rs',), drop_waits=True, actions=[
            f'click {x + w // 2} {y + h // 2}', 'wait-ext demo running', 'wait 300'])
        self.assertEqual(self.runs(), [('0 run demo.run_task 1 ref 3', 'body=all')])

    def test_tooltip(self):
        out = self.run_editor(exts=self.exts(), files=('main.rs',), drop_waits=True, actions=['print-status'])
        x, y, w, h = map(int, self.items(out)['tasks']['at'].split(','))
        out = self.run_editor(exts=self.exts(), files=('main.rs',), drop_waits=True, actions=[
            f'move {x + w // 2} {y + h // 2}', 'wait 700', 'wait 300', 'print-tip'])
        self.assertEqual(out[-1], 'tip=Run a task of this project')

    def test_runtime_items(self):
        cmd = b'command run_task 4\nargs'
        actions = {
            'add': [('status-item build #', body('left', 30, '$(gear) Build', 'Builds it',
                                                  cmd + b'color accent 0\nbackground error 0\nfuture x y 3\nabc'))],
            'replace': [('status-item build #', body('right', 1, 'Built'))],
            'remove': ['status-remove build', 'status-remove tasks', 'status-remove nothing'],
            'bad': [('status-item b1 #', body(text='x' * 121)), ('status-item b2 #', body(extra=b'color pink 0\n')),
                    'status-remove nothing', 'status-item ok 0'],   # (three syntax errors in a row end it)
            'many': [('status-item m%d #' % i, body(text='m%d' % i)) for i in range(5)],
        }
        out = self.run_editor(exts=self.exts(actions=actions), files=('main.rs',), drop_waits=True, actions=[
            'cmd demo.add', 'wait-ext demo running', 'wait 300', 'print-status',
            'cmd demo.replace', 'wait 300', 'print-status',
            'cmd demo.remove', 'wait 300', 'print-status',
            'cmd demo.bad', 'wait 300', 'cmd demo.many', 'wait 300', 'print-status',
            'ext-set demo stop', 'wait-ext demo stopped', 'print-status'])
        log = self.contrib_log()
        self.assertIn('ok 1', log)
        blocks, cur = [], []
        for line in out:
            if line.startswith('side=') and cur and line.split(' item=')[1].split(' ')[0] in [l.split(' item=')[1].split(' ')[0] for l in cur]:
                blocks.append(cur)
                cur = []
            cur.append(line)
        added = self.items(out)
        added_line = [l for l in out if ' item=build ' in l][0]
        self.assertIn('side=left prio=30', added_line)
        self.assertIn('text=$(gear) Build tooltip=Builds it command=run_task', added_line)
        replaced = [l for l in out if ' item=build ' in l][1]
        self.assertIn('side=right prio=1', replaced)
        self.assertIn('text=Built', replaced)
        self.assertIn('error 6 syntax cannot parse the line', log)     # text over 120 bytes
        self.assertIn('error 7 syntax cannot parse the line', log)     # pink is not a color
        self.assertIn('error 9 syntax cannot parse the line', log)     # no body
        # 4 manifest items + m0..m3; the fifth runtime item is refused
        self.assertIn('error 14 toobig 8 items', log)
        final = out[-4:]
        self.assertEqual(sorted(l.split(' item=')[1].split(' ')[0] for l in final), ['high', 'low', 'rust', 'tasks'])

    def test_click_on_runtime_item(self):
        actions = {'add': [('status-item go #', body('left', 99, 'Go', '', b'command run_task 3\nnow'))]}
        out = self.run_editor(exts=self.exts(manifest='', actions=actions), files=('main.rs',), drop_waits=True,
                              actions=['cmd demo.add', 'wait-ext demo running', 'wait 300', 'print-status'])
        x, y, w, h = map(int, self.items(out)['go']['at'].split(','))
        self.run_editor(exts=self.exts(manifest='', actions=actions), files=('main.rs',), drop_waits=True,
                        actions=['cmd demo.add', 'wait-ext demo running', 'wait 300',
                                 f'click {x + w // 2} {y + h // 2}', 'wait 300'])
        self.assertIn(('0 run demo.run_task 1 ref 3', 'body=now'), self.runs())

    def test_v1_status_text(self):
        actions = {'say': [('status #', 'hello v1')]}
        for hello in ('hello 1', HELLO):
            with self.subTest(hello=hello):
                out = self.run_editor(exts=self.exts(manifest='', actions=actions, hello=hello), files=('main.rs',),
                                      drop_waits=True, actions=['cmd demo.say', 'wait-ext demo running', 'wait 300',
                                                                'print-status', 'ext-set demo stop',
                                                                'wait-ext demo stopped', 'print-status'])
                self.assertEqual(len(out), 1, out)
                self.assertTrue(out[0].startswith('side=right prio=0 owner=alice/demo item=_v1 text=hello v1 '), out)

    def test_unagreed_feature(self):
        actions = {'add': [('status-item x #', body())]}
        self.run_editor(exts=self.exts(manifest='', actions=actions, hello='hello 1'), files=('main.rs',),
                        drop_waits=True, actions=['cmd demo.add', 'wait-ext demo running', 'wait 300'])
        self.assertIn('error 1 unknown no such request', self.contrib_log())

    def test_budget_drops_the_lowest(self):
        manifest = '[status]\n' + ''.join(f'i{i}.text = {"x" * 40}\ni{i}.priority = {i}\n' for i in range(8))
        out = self.run_editor(exts=self.exts(manifest=manifest), files=('main.rs',), drop_waits=True,
                              actions=['print-status'])
        shown = {k: v['shown'] for k, v in self.items(out).items()}
        self.assertEqual(shown['i7'], '1')
        self.assertEqual(shown['i0'], '0')
        width = sum(int(v['at'].split(',')[2]) for v in self.items(out).values() if v['shown'] == '1')
        self.assertLessEqual(width, 400)

    def test_icons(self):
        root = self.exts(manifest='[icons]\nlogo = logo.png\ngrey = grey.png\n[status]\n'
                                  'a.text = $(ext:logo) A\nb.text = A\nc.text = $(nosuch) A\nd.text = $(ext:grey) A\n')
        png(root / 'alice/demo/logo.png', (255, 0, 0, 255))
        png(root / 'alice/demo/grey.png', (128, 128, 128, 255))
        out = self.run_editor(exts=root, files=('main.rs',), drop_waits=True, actions=['print-status'])
        w = {k: int(v['at'].split(',')[2]) for k, v in self.items(out).items()}
        self.assertGreater(w['a'], w['b'])
        self.assertGreater(w['c'], w['a'])        # "$(nosuch)" stays text
        self.assertEqual(w['d'], w['a'])


if __name__ == '__main__':
    unittest.main()
