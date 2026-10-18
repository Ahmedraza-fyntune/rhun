#!/usr/bin/env python3
"""Switching to another window and back on X11 and Wayland leaves the editor where it was scrolled,
also far from the cursor (issue 85): a wheel or the scrollbar moves the view, the cursor stays on the
first line, and Alt+Tab (Openbox's own binding) or Sway's focus goes to another window and back.
usage: linux-focus.py [--wayland]"""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

if sys.platform != 'linux':
    print('skip linux/focus (requires Linux)')
    sys.exit(0)
ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
wayland = '--wayland' in sys.argv


def until(predicate, message, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError(message)


with tempfile.TemporaryDirectory(prefix='rhun-focus-') as directory:
    work = Path(directory)
    processes = []
    logs = []
    env = dict(os.environ, HOME=str(work), XDG_CONFIG_HOME=str(work / 'config'),
               XDG_STATE_HOME=str(work / 'state'))
    config = work / 'config/rhun/config'
    config.parent.mkdir(parents=True)
    file = work / 'lines.txt'
    file.write_text(''.join(f'line {i}\n' for i in range(3000)))
    client = None
    reader = None

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

    def y():
        return int(command('print-scroll').split('y=')[1].split()[0])

    def settled():
        """the scroll offset once the events sent have reached the editor and it stopped moving"""
        last = None
        for _ in range(40):
            command('wait 100')
            now = y()
            if now == last:
                return now
            last = now
        return last

    def check(name, scroll, away, back, focused):
        """scroll() moves the view, away() and back() switch windows; focused() is rhun's focus"""
        global client, reader
        config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                          '[editor]\ncursor_blink = false\n'
                          '[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n')
        control = work / 'control'
        control.unlink(missing_ok=True)
        editor = start([str(EXE), str(file), '--control', str(control)])
        until(control.exists, 'editor control socket did not appear')
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(15)
        client.connect(str(control))
        reader = client.makefile('r', encoding='utf-8')
        try:
            until(lambda: 'tabs=1' in command('print-state'), 'the file did not open')
            until(focused, 'the editor did not get the focus')
            command('wait 300')
            scroll()
            scrolled = settled()
            assert scrolled > 0, name + ': the editor did not scroll'
            assert ' line=1 col=1 ' in command('print-state'), name + ': the cursor moved'
            away()
            until(lambda: not focused(), name + ': the other window did not get the focus')
            assert settled() == scrolled, f'{name}: the view moved when the window lost the focus'
            back()
            until(focused, name + ': the editor did not get the focus back')
            assert settled() == scrolled, f'{name}: the view moved when the window got the focus back'
            # a key still brings the cursor into view
            command('type x')
            assert settled() == 0, name + ': typing did not show the cursor'
            print('ok   linux/' + ('wayland' if wayland else 'x11') + '-focus-keeps-the-view-' + name)
        finally:
            command('quit')
            reader.close()
            client.close()
            editor.wait(timeout=10)

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
            # the other window; its virtual keyboard gives the seat the keyboard that focus moves
            protocols = Path(output(['pkg-config', '--variable=pkgdatadir', 'wayland-protocols']))
            sources = []
            for name, xml in [('xdg-shell', protocols / 'stable/xdg-shell/xdg-shell.xml'),
                              ('xdg-activation', protocols / 'staging/xdg-activation/xdg-activation-v1.xml')]:
                subprocess.run(['wayland-scanner', 'client-header', str(xml),
                                str(work / (name + '-client-protocol.h'))], check=True)
                source = work / (name + '-protocol.c')
                subprocess.run(['wayland-scanner', 'private-code', str(xml), str(source)], check=True)
                sources.append(str(source))
            launcher = work / 'launcher'
            subprocess.run(['cc', '-I', str(work), str(ROOT / 'tests/wayland-launcher.c'), *sources,
                            '-lwayland-client', '-o', str(launcher)], check=True)
            start([str(launcher), str(work / 'token')])
            until(lambda: (work / 'token').exists(), 'the other window did not get the focus')
            program = work / 'wayland-pointer'
            subprocess.run(['cc', str(ROOT / 'tests/wayland-pointer.c'), '-lwayland-client',
                            '-o', str(program)], check=True)
            pointer = start([str(program)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            assert pointer.stdout.readline() == 'ready\n', 'the pointer did not start'

            def window():
                tree = json.loads(output(['swaymsg', '-t', 'get_tree', '-r']))
                return next(n['rect'] for n in nodes(tree) if n.get('app_id') == 'rhun')

            def wheel():
                r = window()
                x, yy = r['x'] + r['width'] // 2, r['y'] + r['height'] // 2
                # a move first, so that the editor's new window has the pointer
                pointer.stdin.write(f'{x + 1} {yy} wheel 0 0\n{x} {yy} wheel 15 20\n')
                pointer.stdin.flush()
                assert pointer.stdout.readline() == 'ok\n'
                assert pointer.stdout.readline() == 'ok\n'

            def to(app_id):
                return lambda: output(['swaymsg', f'[app_id="{app_id}"]', 'focus'])
            check('wheel', wheel, to('rhun-launcher'), to('rhun'), focused)
        else:
            read_fd, write_fd = os.pipe()
            start(['Xvfb', '-displayfd', str(write_fd), '-screen', '0', '1280x800x24', '-nolisten', 'tcp'],
                  pass_fds=(write_fd,))
            os.close(write_fd)
            with os.fdopen(read_fd) as pipe:
                env['DISPLAY'] = ':' + pipe.readline().strip()
            env['RHUN_BACKEND'] = 'x11'
            env.pop('WAYLAND_DISPLAY', None)
            wm = work / 'openbox.xml'
            wm.write_text('<openbox_config xmlns="http://openbox.org/3.4/rc"><keyboard>'
                          '<keybind key="A-Tab"><action name="NextWindow"/></keybind>'
                          '</keyboard></openbox_config>')
            # Openbox handles events only from its main loop on, which --startup runs just before
            started = work / 'openbox-started'
            start(['openbox', '--config-file', str(wm), '--startup', 'touch ' + str(started)])
            until(started.exists, 'Openbox did not start')
            # the other window, before the editor: Openbox gives the newest window the focus
            start(['xmessage', '-name', 'rhun-other', '-geometry', '300x100+100+100', 'Other application'])
            until(lambda: subprocess.run(['xdotool', 'search', '--name', 'rhun-other'], env=env,
                                         capture_output=True).returncode == 0, 'the other window did not map')

            def rhun():
                result = subprocess.run(['xdotool', 'search', '--onlyvisible', '--class', '^rhun$'],
                                        env=env, capture_output=True, text=True)
                return result.stdout.split()[0] if result.returncode == 0 else None

            def focused():
                result = subprocess.run(['xdotool', 'getactivewindow'], env=env,
                                        capture_output=True, text=True)
                return result.returncode == 0 and result.stdout.strip() == rhun()

            def wheel():
                output(['xdotool', 'mousemove', '--window', rhun(), '400', '300'])
                output(['xdotool', 'click', '--repeat', '20', '--delay', '20', '5'])

            def drag():
                # the issue's steps: the scrollbar along the window's right edge, down to the end
                window = rhun()
                shape = dict(line.split('=') for line in
                             output(['xdotool', 'getwindowgeometry', '--shell', window]).splitlines())
                x, height = int(shape['WIDTH']) - 6, int(shape['HEIGHT'])
                output(['xdotool', 'mousemove', '--window', window, str(x), '120'])
                output(['xdotool', 'mousedown', '1'])
                for yy in range(160, height, 40):
                    output(['xdotool', 'mousemove', '--window', window, str(x), str(yy)])
                    time.sleep(.03)
                output(['xdotool', 'mousemove', '--window', window, str(x), str(height - 5)])
                time.sleep(.1)
                output(['xdotool', 'mouseup', '1'])

            def alt_tab():
                # Openbox switches when Alt comes up
                output(['xdotool', 'keydown', 'alt'])
                output(['xdotool', 'key', 'Tab'])
                time.sleep(.2)
                output(['xdotool', 'keyup', 'alt'])
            check('wheel', wheel, alt_tab, alt_tab, focused)
            check('scrollbar', drag, alt_tab, alt_tab, focused)
    except BaseException:
        for process, log in zip(processes, logs):
            log.flush()
            print('Process ' + str(process.args) + ':', file=sys.stderr)
            print(Path(log.name).read_text()[-4000:], file=sys.stderr)
        raise
    finally:
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
