#!/usr/bin/env python3
"""Window placement across real X11 restarts, on a private display and user state."""
import ctypes as c
import ctypes.util
import os
from pathlib import Path
import select
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time

if sys.platform != 'linux' or not all(shutil.which(p) for p in ('Xvfb', 'openbox', 'xdotool', 'xprop')):
    print('skip linux/window-state (requires Xvfb, openbox, xdotool and xprop)')
    raise SystemExit(0)
ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()


def until(fn, message):
    end = time.monotonic() + 15
    while time.monotonic() < end:
        result = fn()
        if result:
            return result
        time.sleep(.05)
    raise AssertionError(message)


class Client(c.Structure):
    _fields_ = [('type', c.c_int), ('serial', c.c_ulong), ('send_event', c.c_int),
                ('display', c.c_void_p), ('window', c.c_ulong), ('message_type', c.c_ulong),
                ('format', c.c_int), ('data', c.c_long * 5)]


class Event(c.Union):
    _fields_ = [('client', Client), ('pad', c.c_long * 24)]


class Changes(c.Structure):
    _fields_ = [('x', c.c_int), ('y', c.c_int), ('width', c.c_int), ('height', c.c_int),
                ('border_width', c.c_int), ('sibling', c.c_ulong), ('stack_mode', c.c_int)]


with tempfile.TemporaryDirectory(prefix='rhun-window-state-') as directory:
    work = Path(directory)
    processes = []
    clients = []
    log = (work / 'desktop.log').open('wb')
    read_fd, write_fd = os.pipe()
    server = subprocess.Popen(['Xvfb', '-displayfd', str(write_fd), '-screen', '0',
                               '1600x1000x24', '-nolisten', 'tcp', '-ac', '-noreset'],
                              pass_fds=(write_fd,), stdout=log, stderr=log)
    processes.append(server)
    os.close(write_fd)
    try:
        assert select.select([read_fd], [], [], 15)[0], 'private X server did not start'
        number = os.read(read_fd, 64).decode().strip()
    finally:
        os.close(read_fd)
    assert number.isdigit(), number
    config = work / 'config/rhun/config'
    config.parent.mkdir(parents=True)
    config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                      '[files]\nrestore_session = false\nrestore_project = false\n'
                      '[updates]\ncheck = false\n[git]\nenabled = false\n')
    project = work / 'project'
    project.mkdir()
    env = dict(os.environ, DISPLAY=':' + number, RHUN_BACKEND='x11', HOME=str(work),
               XDG_CONFIG_HOME=str(work / 'config'), XDG_STATE_HOME=str(work / 'state'))
    env.pop('WAYLAND_DISPLAY', None)

    def output(*args):
        return subprocess.check_output(args, env=env, text=True, stderr=subprocess.DEVNULL).strip()

    x = c.CDLL(ctypes.util.find_library('X11'))
    for name, args, result in [
        ('XOpenDisplay', [c.c_char_p], c.c_void_p),
        ('XDefaultRootWindow', [c.c_void_p], c.c_ulong),
        ('XInternAtom', [c.c_void_p, c.c_char_p, c.c_int], c.c_ulong),
        ('XSendEvent', [c.c_void_p, c.c_ulong, c.c_int, c.c_long, c.POINTER(Event)], c.c_int),
        ('XFlush', [c.c_void_p], c.c_int), ('XCloseDisplay', [c.c_void_p], c.c_int),
        ('XConfigureWindow', [c.c_void_p, c.c_ulong, c.c_uint, c.POINTER(Changes)], c.c_int),
    ]:
        getattr(x, name).argtypes, getattr(x, name).restype = args, result
    display = x.XOpenDisplay(env['DISPLAY'].encode())
    assert display
    try:
        manager = subprocess.Popen(['openbox'], env=env, stdout=log, stderr=log)
        processes.append(manager)
        until(lambda: '_NET_SUPPORTING_WM_CHECK' in output('xprop', '-root', '_NET_SUPPORTED'),
              'private window manager did not start')

        def launch():
            control = work / 'control'
            control.unlink(missing_ok=True)
            process = subprocess.Popen([str(EXE), '--wait', str(project), '--control', str(control)],
                                       env=env, stdout=log, stderr=log)
            processes.append(process)
            until(control.exists, 'editor did not open its control socket')
            client = socket.socket(socket.AF_UNIX)
            client.settimeout(15)
            client.connect(str(control))
            clients.append(client)
            reader = client.makefile('rb')

            def command(text):
                client.sendall((text + '\n').encode())
                lines = []
                while True:
                    line = reader.readline()
                    if line == b'ok\n':
                        return b''.join(lines)
                    assert line not in (b'', b'error\n'), (text, line)
                    lines.append(line)

            command('wait 300')
            def visible():
                result = subprocess.run(['xdotool', 'search', '--class', '^rhun$'],
                                        env=env, capture_output=True, text=True)
                return result.stdout.splitlines()
            window = until(visible, 'editor window did not appear')
            assert len(window) == 1, window
            return process, client, command, int(window[0])

        def bounds(window):
            values = dict(line.split('=', 1) for line in
                          output('xdotool', 'getwindowgeometry', '--shell', str(window)).splitlines())
            return tuple(int(values[k]) for k in ('X', 'Y', 'WIDTH', 'HEIGHT'))

        def max_axes(window):
            state = output('xprop', '-id', str(window), '_NET_WM_STATE')
            return sum(1 << n for n, part in enumerate(('HORZ', 'VERT'))
                       if '_NET_WM_STATE_MAXIMIZED_' + part in state)

        def maximized(window):
            return max_axes(window) == 3

        def maximize(window, enabled, axes=3):
            expected = max_axes(window) | axes if enabled else max_axes(window) & ~axes
            event = Event()
            event.client.type = 33
            event.client.display = display
            event.client.window = window
            event.client.message_type = x.XInternAtom(display, b'_NET_WM_STATE', 0)
            event.client.format = 32
            atoms = [x.XInternAtom(display, ('_NET_WM_STATE_MAXIMIZED_' + part).encode(), 0)
                     for n, part in enumerate(('HORZ', 'VERT')) if axes & (1 << n)]
            event.client.data[:] = [int(enabled), atoms[0], atoms[1] if len(atoms) > 1 else 0, 1, 0]
            assert x.XSendEvent(display, x.XDefaultRootWindow(display), 0, 0x180000, c.byref(event))
            x.XFlush(display)
            until(lambda: max_axes(window) == expected, 'maximize request was not applied')

        def close(process, client):
            client.sendall(b'quit\n')
            assert process.wait(timeout=15) == 0
            client.close()

        def capture(name, command):
            destination = os.environ.get('RHUN_TEST_ARTIFACTS')
            if not destination:
                return
            path = Path(destination) / ('window-' + name + '.ppm')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.unlink(missing_ok=True)
            command('shot ' + str(path))
            def complete():
                if not path.exists():
                    return False
                with path.open('rb') as frame:
                    if frame.readline() != b'P6\n':
                        return False
                    values = frame.readline().split()
                    if len(values) != 2 or frame.readline() != b'255\n':
                        return False
                    width, height = map(int, values)
                    return path.stat().st_size >= frame.tell() + width * height * 3
            until(complete, 'native frame was not captured')

        process, client, command, window = launch()
        output('xdotool', 'windowsize', str(window), '900', '640')
        output('xdotool', 'windowmove', str(window), '120', '100')
        command('wait 300')
        normal = bounds(window)
        assert normal[2:] == (900, 640), normal
        capture('normal-before', command)
        close(process, client)
        process, client, command, window = launch()
        actual = bounds(window)
        assert actual == normal, ('normal bounds not restored', normal, actual)
        capture('normal-reopened', command)
        print('ok   x11/window-normal-position-and-size', flush=True)

        maximize(window, True)
        command('wait 300')
        close(process, client)
        process, client, command, window = launch()
        until(lambda: maximized(window), 'maximized state not restored')
        capture('maximized-reopened', command)
        maximize(window, False)
        command('wait 300')
        actual = bounds(window)
        assert actual == normal, ('maximized bounds replaced the normal bounds', normal, actual)
        close(process, client)
        print('ok   x11/window-maximized-and-normal-restore', flush=True)

        process, client, command, window = launch()
        maximize(window, True, axes=2)
        changes = Changes(width=1100)
        x.XConfigureWindow(display, window, 4, c.byref(changes)) # CWWidth only
        x.XFlush(display)
        until(lambda: bounds(window)[2] == 1100, 'width-only resize did not apply')
        assert max_axes(window) == 2
        command('wait 300')
        close(process, client)
        process, client, command, window = launch()
        until(lambda: max_axes(window) == 2, 'vertical maximization was not restored')
        assert bounds(window)[2] == 1100, ('free-axis resize was lost', bounds(window))
        maximize(window, False, axes=2)
        command('wait 300')
        assert bounds(window)[2:] == (1100, 640)
        close(process, client)
        print('ok   x11/window-partial-maximize-keeps-free-axis-changes', flush=True)

        process, client, command, window = launch()
        process.send_signal(signal.SIGSTOP)
        try:
            output('xdotool', 'windowsize', str(window), '1050', '720')
            output('xdotool', 'windowmove', str(window), '170', '150')
            latest_normal = bounds(window)
            assert latest_normal[2:] == (1050, 720), latest_normal
            maximize(window, True)
        finally:
            process.send_signal(signal.SIGCONT)
        command('wait 300')
        close(process, client)
        process, client, command, window = launch()
        until(lambda: maximized(window), 'queued maximization was not restored')
        maximize(window, False)
        command('wait 300')
        assert bounds(window) == latest_normal, ('queued normal bounds were lost', latest_normal, bounds(window))
        close(process, client)
        print('ok   x11/window-busy-resize-move-then-maximize', flush=True)

        record = work / 'state/rhun/window-x11'
        record.write_bytes(b'invalid state')
        process, client, command, window = launch()
        assert bounds(window)[2:] == (1280, 820), ('invalid state changed defaults', bounds(window))
        close(process, client)
        print('ok   x11/window-invalid-state-uses-defaults', flush=True)
        record.write_bytes(struct.pack('<IiiIII', 0x31535752, 1000000, 1000000, 900, 640, 0))
        process, client, command, window = launch()
        actual = bounds(window)
        assert 0 <= actual[0] < 1600 and 0 <= actual[1] < 1000, ('obsolete position is off screen', actual)
        assert actual[2:] == (900, 640)
        close(process, client)
        print('ok   x11/window-obsolete-screen-position', flush=True)
    except Exception:
        log.flush()
        print((work / 'desktop.log').read_text(errors='replace'), file=sys.stderr)
        print(output('xwininfo', '-root', '-tree'), file=sys.stderr)
        print([(str(p.args), p.poll()) for p in processes], file=sys.stderr)
        raise
    finally:
        x.XCloseDisplay(display)
        for client in clients:
            client.close()
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        log.close()
