#!/usr/bin/env python3
"""Native window placement survives restarts, using private configuration and state."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

if os.name != 'nt':
    print('skip windows/window-state (requires Windows)')
    raise SystemExit(0)
import ctypes as c
from ctypes import wintypes as w

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/windows/rhun.exe')).resolve()
user = c.WinDLL('user32', use_last_error=True)
Callback = c.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)


class Placement(c.Structure):
    _fields_ = [('length', w.UINT), ('flags', w.UINT), ('showCmd', w.UINT),
                ('ptMinPosition', w.POINT), ('ptMaxPosition', w.POINT),
                ('rcNormalPosition', w.RECT)]


for name, arguments, result in [
    ('EnumWindows', [Callback, w.LPARAM], w.BOOL),
    ('GetWindowThreadProcessId', [w.HWND, c.POINTER(w.DWORD)], w.DWORD),
    ('IsWindowVisible', [w.HWND], w.BOOL), ('IsZoomed', [w.HWND], w.BOOL),
    ('IsIconic', [w.HWND], w.BOOL),
    ('GetWindowPlacement', [w.HWND, c.POINTER(Placement)], w.BOOL),
    ('SetWindowPlacement', [w.HWND, c.POINTER(Placement)], w.BOOL),
    ('ShowWindow', [w.HWND, c.c_int], w.BOOL),
    ('PostMessageW', [w.HWND, w.UINT, w.WPARAM, w.LPARAM], w.BOOL),
]:
    getattr(user, name).argtypes, getattr(user, name).restype = arguments, result


def until(fn, message):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        result = fn()
        if result:
            return result
        time.sleep(.05)
    raise AssertionError(message)


def placement(window):
    value = Placement()
    value.length = c.sizeof(value)
    assert user.GetWindowPlacement(window, c.byref(value)), c.get_last_error()
    return value


def normal(window):
    rect = placement(window).rcNormalPosition
    return rect.left, rect.top, rect.right, rect.bottom


with tempfile.TemporaryDirectory(prefix='rhun-window-state-') as directory:
    work = Path(directory)
    project = work / 'project'
    project.mkdir()
    config = work / 'config/rhun/config'
    config.parent.mkdir(parents=True)
    config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                      '[files]\nrestore_session = false\nrestore_project = false\n'
                      '[updates]\ncheck = false\n[git]\nenabled = false\n')
    env = dict(os.environ, HOME=work.as_posix(), XDG_CONFIG_HOME=(work / 'config').as_posix(),
               XDG_STATE_HOME=(work / 'state').as_posix())
    processes = []
    log = (work / 'editor.log').open('wb')
    try:
        def launch():
            process = subprocess.Popen([str(EXE), '--wait', str(project)], env=env,
                                       stdout=log, stderr=log)
            processes.append(process)

            def find():
                found = []
                @Callback
                def visit(window, _):
                    pid = w.DWORD()
                    user.GetWindowThreadProcessId(window, c.byref(pid))
                    if pid.value == process.pid and user.IsWindowVisible(window):
                        found.append(window)
                    return True
                user.EnumWindows(visit, 0)
                return found[0] if found else None

            window = until(find, 'editor window did not open')
            return process, window

        def close(process, window):
            assert user.PostMessageW(window, 0x10, 0, 0), c.get_last_error()
            assert process.wait(timeout=15) == 0

        process, window = launch()
        target = placement(window)
        target.flags, target.showCmd = 0, 1
        target.rcNormalPosition = w.RECT(80, 70, 840, 590)
        assert user.SetWindowPlacement(window, c.byref(target)), c.get_last_error()
        time.sleep(.3)
        expected = normal(window)
        close(process, window)
        process, window = launch()
        assert normal(window) == expected, ('normal bounds not restored', expected, normal(window))
        assert not user.IsIconic(window) and not user.IsZoomed(window)
        print('ok   windows/window-normal-position-and-size', flush=True)

        user.ShowWindow(window, 3)
        until(lambda: user.IsZoomed(window), 'maximize failed')
        close(process, window)
        process, window = launch()
        until(lambda: user.IsZoomed(window), 'maximized state not restored')
        assert normal(window) == expected, ('maximized bounds replaced normal bounds', normal(window))
        print('ok   windows/window-maximized-and-normal-restore', flush=True)

        user.ShowWindow(window, 2)
        until(lambda: user.IsIconic(window), 'minimize failed')
        close(process, window)
        process, window = launch()
        until(lambda: user.IsZoomed(window), 'minimized maximized window lost its restored state')
        assert not user.IsIconic(window)
        user.ShowWindow(window, 9)
        until(lambda: not user.IsZoomed(window), 'restore failed')
        assert normal(window) == expected
        user.ShowWindow(window, 2)
        until(lambda: user.IsIconic(window), 'minimize failed')
        close(process, window)
        process, window = launch()
        assert not user.IsIconic(window) and not user.IsZoomed(window)
        assert normal(window) == expected
        close(process, window)
        print('ok   windows/window-minimized-restores-visible', flush=True)
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.wait()
        log.close()
