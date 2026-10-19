#!/usr/bin/env python3
"""The viewfake extension: retained views for the host tests (tests/ext-views-tree.py), standard
library only. It agrees view-tree, fills its declared views when they open and changes them when
its commands run. VIEWFAKE_LOG receives every line rhun sends and every reply, one per line (a
body after its line). VIEWFAKE_MODE: normal, nofeature (agrees nothing).

Commands: rescan (the same ids again, with a new count), renamed (new ids), vanish (removes the
selected node), badpatch (a patch whose third op names a missing node), big (100001 nodes), show
(vshow items focus), empty (state empty with a text and a key), msg (a message line), busy (busy 1),
expand (expands f:main.rs), reveal (vreveal t:lib.rs:1 select,focus after collapsing lib.rs),
multi (items becomes multi-select), delpin (removes the pin action).

The items view (panel) has a lazy node "a" (its children come with vkids: VIEWFAKE_LAZY answer,
error, late (after 1 s), or never) and pages of root children (vmore adds two, three pages).
TODO has a title action "rescan" and node actions "pin" (inline) and "pin hide" (menu).
"""
import threading
import time
import os
import sys

MODE = os.environ.get('VIEWFAKE_MODE', 'normal')
LOG = os.environ.get('VIEWFAKE_LOG')
ROOT = os.environ.get('VIEWFAKE_ROOT', '/nonexistent')
out = sys.stdout.buffer
inp = sys.stdin.buffer
LAZY = os.environ.get('VIEWFAKE_LAZY', 'answer')
next_id = 1
lock = threading.Lock()
views = {}              # manifest key -> VIEW
selected = {}           # VIEW -> selected node id
rescans = 0


def log(data):
    if LOG:
        with open(LOG, 'ab') as f:
            f.write(data + b'\n')


def send(line, body=b''):
    with lock:
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
    ops = [rec('title', data=b'TODO'), rec('badge', '4'), rec('action', 'rescan refresh title', b'Rescan'),
           rec('action', 'pin pin node', b'Pin'), rec('action', 'hide - node', b'Hide')]
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
                rec('open', f'{i + 1} 1', path.encode()) + rec('tip', data=f'tip of {i + 1}'.encode()) + \
                rec('inline', data=b'pin') + rec('menu', data=b'pin hide')
            items.append(node(f'{prefix}t:{name}:{i + 1}', text, 'leaf', extra))
        ops.append(kids(f'{prefix}f:{name}', items))
    ops.append(rec('state', 'ready 0'))
    patch(view, ops)


def items_tree(view):
    ops = [kids('', [node('a', 'Alpha', 'closed'), node('b', 'Beta'), node('c', 'Gamma', 'leaf', rec('check', '0'))],
                more=1)]
    ops.append(rec('state', 'ready 0'))
    patch(view, ops)


pages = 0


def answer(rid, body):
    send(f'ok {rid} {len(body)}', body)


def host_request(rid, verb, fields, body):
    """vkids VIEW REV LEN + id, vmore VIEW REV HAVE LEN + id."""
    global pages
    if verb == 'vkids':
        nid = body.decode()
        if LAZY == 'error':
            send(f'error {rid} refused cannot list {nid}')
            return
        if LAZY == 'never':
            return
        reply = f'1\n'.encode() + kids(nid, [node(nid + '1', nid.upper() + ' one'), node(nid + '2', nid.upper() + ' two')])
        if LAZY == 'late':
            threading.Timer(1.0, answer, (rid, reply)).start()
        else:
            answer(rid, reply)
    elif verb == 'vmore':
        pages += 1
        have = int(fields[3])
        more = 1 if pages < 3 else 0
        items = [node(f'p{have + i}', f'Page item {have + i}') for i in range(2)]
        answer(rid, b'1\n' + kids('', items, more=more, op='add'))
    else:
        send(f'error {rid} unknown')


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
    elif name == 'reveal' and todo:
        patch(todo, [rec('collapse', data=b'f:lib.rs')])
        request(f'vreveal {todo} select,focus', b't:lib.rs:1')
    elif name == 'multi' and views.get('items'):
        patch(views['items'], [rec('select-mode', 'multi')])
    elif name == 'delpin' and todo:
        patch(todo, [rec('action', 'pin - none', b'')])


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
        elif fields[0].isdigit() and fields[0] != '0' and len(fields) >= 3 and fields[1] in ('vkids', 'vmore'):
            n = int(fields[-1])
            body = inp.read(n)
            log(body)
            host_request(fields[0], fields[1], fields[1:], body)
            continue
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
