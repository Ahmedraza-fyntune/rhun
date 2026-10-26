#!/usr/bin/env python3
"""Restore normal size and maximization on private Sway and Weston compositors."""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

if sys.platform != 'linux':
    print('skip wayland/window-state (requires Linux)')
    raise SystemExit(0)
ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()


def until(fn, message):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        result = fn()
        if result:
            return result
        time.sleep(.05)
    raise AssertionError(message)


def check(compositor):
    with tempfile.TemporaryDirectory(prefix='rhun-wayland-window-') as directory:
        work = Path(directory)
        runtime = work / 'runtime'
        runtime.mkdir(mode=0o700)
        project = work / 'project'
        project.mkdir()
        config = work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[ui]\nsidebar = false\nagents_panel = false\ndecorations = client\n'
                          '[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n')
        env = dict(os.environ, HOME=str(work), XDG_RUNTIME_DIR=str(runtime),
                   XDG_CONFIG_HOME=str(work / 'config'), XDG_STATE_HOME=str(work / 'state'),
                   WLR_BACKENDS='headless', WLR_LIBINPUT_NO_DEVICES='1', WLR_RENDERER='pixman')
        for name in ('DISPLAY', 'WAYLAND_DISPLAY', 'RHUN_BACKEND', 'SWAYSOCK'):
            env.pop(name, None)
        processes, clients = [], []
        log = (work / 'desktop.log').open('wb')
        try:
            if compositor == 'sway':
                cfg = work / 'sway.conf'
                cfg.write_text('output * resolution 1600x1000\ndefault_border none\n'
                               'default_floating_border none\n'
                               'for_window [app_id="rhun"] floating enable\n')
                args = ['sway', '-c', str(cfg)]
            else:
                args = ['weston', '--backend=headless-backend.so', '--width=1600', '--height=1000',
                        '--socket=wayland-test', '--idle-time=0', '--no-config']
            processes.append(subprocess.Popen(args, env=env, stdout=log, stderr=log))
            sockets = until(lambda: [p for p in runtime.glob('wayland-*')
                                      if not p.name.endswith('.lock')], 'compositor did not start')
            env['WAYLAND_DISPLAY'] = sockets[0].name
            if compositor == 'sway':
                env['SWAYSOCK'] = str(until(lambda: next(runtime.glob('sway-ipc.*.sock'), None),
                                           'Sway IPC did not start'))

            def launch():
                control = work / 'control'
                control.unlink(missing_ok=True)
                process = subprocess.Popen([str(EXE), '--wait', str(project), '--scale', '1',
                                            '--control', str(control)], env=env, stdout=log, stderr=log)
                processes.append(process)
                until(control.exists, 'editor did not open its control socket')
                client = socket.socket(socket.AF_UNIX)
                client.settimeout(15)
                client.connect(str(control))
                clients.append(client)
                reader = client.makefile('rb')

                def command(text):
                    client.sendall((text + '\n').encode())
                    while True:
                        line = reader.readline()
                        if line == b'ok\n':
                            return
                        assert line not in (b'', b'error\n'), (text, line)

                def size():
                    command('wait 100')
                    path = work / 'frame.ppm'
                    path.unlink(missing_ok=True)
                    command('shot ' + str(path))
                    def ready():
                        if not path.exists():
                            return None
                        with path.open('rb') as frame:
                            if frame.readline() != b'P6\n':
                                return None
                            values = frame.readline().split()
                            if len(values) != 2 or frame.readline() != b'255\n':
                                return None
                            width, height = map(int, values)
                            return (width, height) if path.stat().st_size >= frame.tell() + width * height * 3 else None
                    return until(ready, 'native frame was not captured')

                command('wait 300')
                return process, client, command, size

            def close(process, client):
                client.sendall(b'quit\n')
                assert process.wait(timeout=15) == 0
                client.close()

            process, client, command, size = launch()
            if compositor == 'sway':
                def sway(action):
                    subprocess.run(['swaymsg', '[app_id="rhun"]', action], env=env,
                                   check=True, capture_output=True)
                sway('resize set width 900 px height 640 px')
                until(lambda: size() == (900, 640), 'floating resize did not apply')
                close(process, client)
                process, client, command, size = launch()
                assert size() == (900, 640), ('normal size not restored', size())
                print('ok   wayland/window-normal-size', flush=True)
                sway('floating disable')
                until(lambda: size() != (900, 640), 'tiling did not apply')
                close(process, client)
                process, client, command, size = launch()
                assert size() == (900, 640), ('tiling overwrote normal size', size())
                print('ok   wayland/window-tiling-keeps-normal-size', flush=True)
            else:
                normal = size()
                command(f'click {normal[0] - 72} 18')
                maximized = until(lambda: (s := size()) != normal and s,
                                  'maximize button did not apply')
                close(process, client)
                process, client, command, size = launch()
                assert size() == maximized, ('maximized state not restored', maximized, size())
                command(f'click {maximized[0] - 72} 18')
                until(lambda: size() == normal, 'unmaximize did not restore normal size')
                print('ok   wayland/window-maximized-and-normal-restore', flush=True)
            close(process, client)
        except Exception:
            log.flush()
            print((work / 'desktop.log').read_text(errors='replace'), file=sys.stderr)
            raise
        finally:
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


for compositor in ('sway', 'weston'):
    if shutil.which(compositor):
        check(compositor)
    else:
        print('skip wayland/window-state (requires ' + compositor + ')')
