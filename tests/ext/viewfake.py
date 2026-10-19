#!/usr/bin/env python3
"""The viewfake extension: retained views for the host tests (tests/ext-views-tree.py), standard
library only. It agrees view-tree, fills its declared views when they open and changes them when
its commands run. VIEWFAKE_LOG receives every line rhun sends and every reply, one per line (a
body after its line). VIEWFAKE_MODE: normal, nofeature (agrees nothing).

Commands: rescan (the same ids again, with a new count), renamed (new ids), vanish (removes the
selected node), badpatch (a patch whose third op names a missing node), big (100001 nodes), show
(vshow items focus), empty (state empty with a text and a key), msg (a message line), busy (busy 1),
expand (expands f:main.rs).
"""
import os
import sys

MODE = os.environ.get('VIEWFAKE_MODE', 'normal')
LOG = os.environ.get('VIEWFAKE_LOG')
ROOT = os.environ.get('VIEWFAKE_ROOT', '/nonexistent')
out = sys.stdout.buffer
inp = sys.stdin.buffer
next_id = 1
views = {}              # manifest key -> VIEW
selected = {}           # VIEW -> selected node id
rescans = 0


def log(data):
    if LOG:
        with open(LOG, 'ab') as f:
            f.write(data + b'\n')


def send(line, body=b''):
    out.write(line.encode() + b'\n' + body)
    out.flush()


def request(verb, body=None):
    global next_id
    rid = next_id
    next_id += 1
    if body is None:
        send(f'{rid} {verb}')
    else:
        send(f'{rid} {verb} {len(body)}', body)
    return rid


def rec(name, args='', data=b''):
    head = f'{name} {args} {len(data)}' if args else f'{name} {len(data)}'
    return head.encode() + b'\n' + data


def node(nid, label, kids='leaf', extra=b''):
    nid, label = nid.encode(), label.encode()
    return f'{len(nid)} {len(label)} {len(extra)} {kids}\n'.encode() + nid + label + extra


def kids(parent, nodes, more=0, op='kids'):
    parent = parent.encode()
    data = parent + b''.join(nodes)
    return rec(op, f'{len(parent)} {len(nodes)} {more}', data)


def patch(view, ops):
    body = f'{len(ops)}\n'.encode() + b''.join(ops)
    return request(f'vpatch {view}', body)


def todo_tree(view, prefix='', count=2):
    files = [('main.rs', 'src', 2), ('lib.rs', 'src', 1), ('README.md', '', 1)]
    ops = [rec('title', data=b'TODO'), rec('badge', '4')]
    top = []
    for name, folder, n in files:
        extra = rec('icon', f'file:{name} -') + rec('badge', f'{n}')
        if folder:
            extra = rec('desc', data=folder.encode()) + extra
        top.append(node(f'{prefix}f:{name}', name, 'open', extra))
    ops.append(kids('', top))
    for name, folder, n in files:
        path = os.path.join(ROOT, folder, name) if folder else os.path.join(ROOT, name)
        items = []
        for i in range(n):
            text = f'TODO: item {i + 1} of {name} ({count})'
            extra = rec('hl', '0 4') + rec('icon', 'warning warning') + \
                rec('open', f'{i + 1} 1', path.encode()) + rec('tip', data=f'tip of {i + 1}'.encode())
            items.append(node(f'{prefix}t:{name}:{i + 1}', text, 'leaf', extra))
        ops.append(kids(f'{prefix}f:{name}', items))
    ops.append(rec('state', 'ready 0'))
    patch(view, ops)


def items_tree(view):
    ops = [kids('', [node('a', 'Alpha', 'closed'), node('b', 'Beta'), node('c', 'Gamma', 'leaf', rec('check', '0'))])]
    ops.append(kids('a', [node('a1', 'Alpha one'), node('a2', 'Alpha two')]))
    ops.append(rec('state', 'ready 0'))
    patch(view, ops)


def on_command(name):
    global rescans
    todo = views.get('todo')
    if name == 'rescan' and todo:
        rescans += 1
        todo_tree(todo, count=2 + rescans)
    elif name == 'renamed' and todo:
        todo_tree(todo, prefix='n')
    elif name == 'vanish' and todo:
        sel = selected.get(todo)
        if sel:
            patch(todo, [rec('del', data=sel.encode())])
    elif name == 'badpatch' and todo:
        patch(todo, [rec('title', data=b'Changed'), rec('badge', '9'),
                     kids('missing-parent', [node('x', 'X')])])
    elif name == 'big' and todo:
        patch(todo, [kids('', [node(f'n{i}', f'N {i}') for i in range(100001)])])
    elif name == 'show':
        request('vshow items focus')
    elif name == 'empty' and todo:
        patch(todo, [rec('state', 'empty 13', b'Nothing found.rescan')])
    elif name == 'msg' and todo:
        patch(todo, [rec('message', data=b'Scanned 3 files')])
    elif name == 'busy' and todo:
        patch(todo, [rec('busy', '1')])
    elif name == 'expand' and todo:
        patch(todo, [rec('collapse', data=b'f:main.rs'), rec('expand', data=b'f:lib.rs')])


def main():
    features = '' if MODE == 'nofeature' else ' view-tree'
    send('hello 1' + features)
    while True:
        line = inp.readline()
        if not line:
            return
        line = line.rstrip(b'\n')
        log(line)
        fields = line.decode('utf-8', 'replace').split(' ')
        body = b''
        # a line whose last field is a length carries a body
        if fields[0] == '0' and len(fields) >= 3 and fields[1] == 'view' and \
                fields[3] in ('select', 'activate', 'expand', 'collapse', 'check', 'action', 'discarded'):
            n = int(fields[-1])
            body = inp.read(n)
            log(body)
        elif fields[0] == 'ok' and len(fields) == 3:
            pass
        if fields[0] == '0' and len(fields) >= 3 and fields[1] == 'view':
            view = int(fields[2])
            what = fields[3]
            if what == 'open':
                key = fields[6]
                views[key] = view
                if key == 'todo':
                    todo_tree(view)
                elif key == 'items':
                    items_tree(view)
            elif what == 'select':
                ids = body.split(b'\n')
                selected[view] = ids[0].decode() if ids and ids[0] else None
        elif fields[0] == '0' and len(fields) >= 3 and fields[1] == 'run':
            name = fields[2].split('.')[-1]
            on_command(name)


main()
