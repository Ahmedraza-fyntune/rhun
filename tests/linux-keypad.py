#!/usr/bin/env python3
"""Zoom from the keypad on real X11 and Wayland (PR 77): Ctrl with the keypad's +, -, = and 0 zooms
the focused editor or terminal, as the top row's keys do, also from the find bar and vim's normal
mode, and without Ctrl the keypad still types. Num Lock decides what the 0 key is: KP_0 with it on;
with it off KP_Insert, so Ctrl with it is Ctrl+Insert (copy), not a reset.
On X11 the keys go through the server's own keymap (rhun's xkey command, then xdotool); on Wayland
through a virtual keyboard with GNOME's US keymap. usage: linux-keypad.py [--wayland]"""
import configparser
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

if sys.platform != 'linux':
    print('skip linux/keypad (requires Linux)')
    sys.exit(0)
ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
wayland = '--wayland' in sys.argv

# evdev key codes; the X server's and the xkb keymap's are 8 more
KP_ADD, KP_SUBTRACT, KP_0, KP_EQUAL = 78, 74, 82, 117
CTRL, NUM_LOCK = 4, 16          # the keymap's modifier masks (Control, Mod2)


def until(predicate, message, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError(message)


with tempfile.TemporaryDirectory(prefix='rhun-keypad-') as directory:
    work = Path(directory)
    processes = []
    logs = []
    env = dict(os.environ, HOME=str(work), XDG_CONFIG_HOME=str(work / 'config'),
               XDG_STATE_HOME=str(work / 'state'))
    config = work / 'config/rhun/config'
    config.parent.mkdir(parents=True)
    file = work / 'a.txt'
    client = reader = keyboard = None

    def start(args, **kwargs):
        log = open(work / ('process-' + str(len(processes)) + '.log'), 'w')
        logs.append(log)
        kwargs.setdefault('stdout', log)
        p = subprocess.Popen(args, env=env, stderr=log, **kwargs)
        processes.append(p)
        return p

    def output(args):
        return subprocess.check_output(args, env=env, text=True).strip()

    def command(line):
        client.sendall((line + '\n').encode())
        parts = []
        while True:
            reply = reader.readline()
            if reply == 'ok\n':
                return ''.join(parts)
            assert reply not in ('', 'error\n'), (line, reply)
            parts.append(reply)

    def keys(mods, *codes):
        """each key pressed and released with mods held (and locked: Num Lock)"""
        if wayland:
            def send(line):
                keyboard.stdin.write(line + '\n')
                keyboard.stdin.flush()
                assert keyboard.stdout.readline() == 'ok\n'
            send(f'mods {mods & ~NUM_LOCK} 0 {mods & NUM_LOCK} 0')
            for code in codes:
                send(f'key {code} 1')
                send(f'key {code} 0')
            send(f'mods 0 0 {mods & NUM_LOCK} 0')
        else:
            for code in codes:
                command(f'xkey {code + 8} {mods}')
        command('wait 100')

    def check(name, actions, editor, terminal=12, doc='hello\n', setup=()):
        """actions run with the editor in front; then the fonts saved on quit, and the document"""
        global client, reader
        config.write_text('[editor]\nfont_size = 17\n[terminal]\nfont_size = 12\nshell = /bin/sh\n'
                          '[ui]\nsidebar = false\nagents_panel = false\n'
                          '[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n')
        file.write_text('hello\n')
        control = work / 'control'
        control.unlink(missing_ok=True)
        editor_process = start([str(EXE), str(file), '--control', str(control)])
        until(control.exists, 'editor control socket did not appear')
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(15)
        client.connect(str(control))
        reader = client.makefile('r', encoding='utf-8')
        try:
            until(lambda: 'tabs=1' in command('print-state'), 'the file did not open')
            until(focused, 'the editor did not get the focus')
            command('wait 300')
            for line in setup:
                command(line)
            for action in actions:
                action()
            got = command('print-doc').removesuffix('\n<eod>\n')
        finally:
            command('quit')
            reader.close()
            client.close()
            editor_process.wait(timeout=10)
        saved = configparser.ConfigParser(interpolation=None, strict=False)
        saved.read(config, encoding='utf-8')
        sizes = (saved.getint('editor', 'font_size'), saved.getint('terminal', 'font_size'))
        assert sizes == (editor, terminal), f'{name}: fonts {sizes}, expected {(editor, terminal)}'
        assert got == doc, f'{name}: the document is {got!r}, expected {doc!r}'
        print('ok   linux/' + ('wayland' if wayland else 'x11') + '-keypad-' + name)

    def press(mods, *codes):
        return lambda: keys(mods, *codes)

    try:
        if wayland:
            runtime = work / 'runtime'
            runtime.mkdir(mode=0o700)
            env.update(XDG_RUNTIME_DIR=str(runtime), WLR_BACKENDS='headless',
                       WLR_LIBINPUT_NO_DEVICES='1', WLR_RENDERER='pixman')
            env.pop('DISPLAY', None)
            env.pop('WAYLAND_DISPLAY', None)
            compositor = work / 'sway.conf'
            compositor.write_text('output * resolution 1280x800\n')
            start(['sway', '-d', '-c', str(compositor)])
            until(lambda: bool(list(runtime.glob('sway-ipc.*.sock'))), 'Sway did not start')
            env['SWAYSOCK'] = str(next(runtime.glob('sway-ipc.*.sock')))
            env['WAYLAND_DISPLAY'] = next(p.name for p in runtime.glob('wayland-*')
                                          if not p.name.endswith('.lock'))

            def nodes(tree):
                yield tree
                for child in tree.get('nodes', []) + tree.get('floating_nodes', []):
                    yield from nodes(child)

            def focused():
                tree = json.loads(output(['swaymsg', '-t', 'get_tree', '-r']))
                return any(n.get('app_id') == 'rhun' and n.get('focused') for n in nodes(tree))
            # one keyboard for every run, made before the editor starts: the seat then has a keyboard
            program = work / 'wayland-keyboard'
            subprocess.run(['cc', str(ROOT / 'tests/wayland-keyboard.c'), '-lwayland-client',
                            '-o', str(program)], check=True)
            keyboard = start([str(program), str(ROOT / 'tests/data/keymap-gnome-us.txt')],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            assert keyboard.stdout.readline() == 'ready\n', 'the keyboard did not start'
        else:
            read_fd, write_fd = os.pipe()
            start(['Xvfb', '-displayfd', str(write_fd), '-screen', '0', '1280x800x24', '-nolisten', 'tcp'],
                  pass_fds=(write_fd,))
            os.close(write_fd)
            with os.fdopen(read_fd) as pipe:
                env['DISPLAY'] = ':' + pipe.readline().strip()
            env['RHUN_BACKEND'] = 'x11'
            env.pop('WAYLAND_DISPLAY', None)
            # Openbox handles events only from its main loop on, which --startup runs just before
            started = work / 'openbox-started'
            start(['openbox', '--startup', 'touch ' + str(started)])
            until(started.exists, 'Openbox did not start')

            def focused():
                result = subprocess.run(['xdotool', 'getactivewindow'], env=env, capture_output=True,
                                        text=True)
                windows = subprocess.run(['xdotool', 'search', '--class', '^rhun$'], env=env,
                                         capture_output=True, text=True)
                return result.returncode == 0 and result.stdout.strip() in windows.stdout.splitlines()

        on = CTRL | NUM_LOCK
        check('zoom-in-and-out', [press(on, KP_ADD, KP_ADD, KP_SUBTRACT)], 18)
        check('reset', [press(on, KP_0)], 14)
        check('equal', [press(on, KP_EQUAL)], 18)
        check('num-lock-off', [press(CTRL, KP_0, KP_ADD)], 18)
        check('terminal', [press(on, KP_ADD, KP_ADD, KP_SUBTRACT, KP_SUBTRACT, KP_SUBTRACT)], 17, 11,
              setup=['cmd new_terminal', 'wait 300'])
        check('find-bar', [press(on, KP_ADD)], 18, setup=['cmd find'])
        check('vim-normal-mode', [press(on, KP_ADD)], 18, setup=['cmd toggle_vim'])
        check('typing', [press(NUM_LOCK, KP_ADD, KP_0)], 17, doc='+0hello\n')
        if not wayland:
            # the server's own events: xdotool presses Control and the keypad keys
            def xdotool(*names):
                return lambda: (output(['xdotool', 'key', '--delay', '30', *names]), command('wait 200'))
            check('xdotool', [xdotool('ctrl+KP_Add', 'ctrl+KP_Add', 'ctrl+KP_Subtract')], 18)
    except BaseException:
        for process, log in zip(processes, logs):
            log.flush()
            print('Process ' + str(process.args) + ':', file=sys.stderr)
            print(Path(log.name).read_text()[-4000:], file=sys.stderr)
        raise
    finally:
        if keyboard is not None and keyboard.poll() is None:
            keyboard.stdin.close()
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        for log in logs:
            log.close()
