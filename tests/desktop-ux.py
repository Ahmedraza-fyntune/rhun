#!/usr/bin/env python3
"""Startup project precedence and desktop actions, with isolated user state."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()

with tempfile.TemporaryDirectory(prefix='rhun-desktop-') as temporary:
    work = Path(temporary).resolve()
    project = work / 'project café with spaces'
    other = work / 'other'
    project.mkdir()
    other.mkdir()
    file = project / "file ' $test.txt"
    file.write_text('hello\n')
    config = work / 'config/rhun/config'
    config.parent.mkdir(parents=True)
    env = dict(os.environ, HOME=work.as_posix(), XDG_CONFIG_HOME=(work / 'config').as_posix(),
               XDG_STATE_HOME=(work / 'state').as_posix())

    def configure(enabled=None, tabs=True):
        restore = '' if enabled is None else 'restore_project = ' + str(enabled).lower() + '\n'
        config.write_text('[files]\n' + restore +
                          'restore_session = ' + str(tabs).lower() +
                          '\n[updates]\ncheck = false\n[git]\nenabled = false\n')

    def run(paths=(), lines=('print-project', 'print-state', 'quit')):
        script = work / 'commands.rsc'
        script.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), *map(str, paths), '--headless', '1000x700',
                                 '--script', str(script)], cwd=other, env=env,
                                capture_output=True, timeout=20, check=True)
        return result.stdout.decode('utf-8')

    def check_project(output, name):
        assert f'project=~/{name}\n' in output, output

    configure()
    run([project, file])
    output = run()
    check_project(output, project.name)
    assert 'tabs=1 ' in output, output
    print('ok   desktop/default-restore-project-and-tabs')

    check_project(run([other]), other.name)
    run([project])
    marker = work / 'state/rhun/last-project'
    previous = marker.read_bytes()
    output = run([file])
    assert 'project=\n' in output, output
    assert 'tabs=1 active=' + file.name in output, output
    assert marker.read_bytes() == previous
    output = run([file, other / 'second.rb'])
    assert 'project=\n' in output and 'tabs=2 ' in output, output
    assert marker.read_bytes() == previous
    print('ok   desktop/explicit-folder-and-file-win')
    output = run(['--empty'])
    assert 'project=\n' in output and 'tabs=0 ' in output, output
    assert marker.read_bytes() == previous
    print('ok   desktop/explicit-empty-window')

    stored = other / 'stored.rb'
    stored.write_text('stored\n')
    run([other, stored])
    output = run([file], ['type pending', f'open {other.as_posix()}', 'print-project', 'print-state',
                        'key Escape', 'print-project', 'cmd save', f'open {other.as_posix()}',
                        'print-project', 'print-state', 'quit'])
    assert output.count('project=\n') == 2, output
    assert 'dirty=1 ' in output, output
    check_project(output, other.name)
    assert 'tabs=1 active=stored.rb' in output, output
    print('ok   desktop/standalone-folder-switch-preserves-edits-and-restores-session')
    run([project])

    configure(tabs=False)
    run([project])
    output = run()
    check_project(output, project.name)
    assert 'tabs=0 ' in output, output
    print('ok   desktop/project-without-tab-restoration')

    configure(enabled=False)
    check_project(run(), other.name)
    configure()
    marker = work / 'state/rhun/last-project'
    marker.write_text((work / 'missing').as_posix(), encoding='utf-8')
    check_project(run(), other.name)
    marker.write_text('', encoding='utf-8')
    check_project(run(), other.name)
    marker.unlink()
    check_project(run(), other.name)
    print('ok   desktop/disabled-missing-empty-first-launch')

    # A project switch is remembered immediately, including without saved tabs.
    configure(tabs=False)
    run([other], [f'open {project.as_posix()}', 'quit'])
    check_project(run(), project.name)
    print('ok   desktop/switched-project')

    # Another instance can replace the marker while this project is still open.
    # Simulate that write, then verify that quitting remembers this project's folder.
    run([project], [f'open {marker.as_posix()}', 'key ctrl+a',
                    f'type {other.as_posix()}', 'cmd save', 'quit'])
    # The marker is UTF-8; Windows would otherwise decode it in the ANSI code page.
    remembered = marker.read_text(encoding='utf-8')
    assert remembered == project.as_posix(), remembered
    check_project(run(), project.name)
    print('ok   desktop/last-closed-project')

    # Never open real desktop applications in the automated suite.
    if os.name != 'nt':
        bin_dir = work / 'bin'
        bin_dir.mkdir()
        opener = bin_dir / ('open' if sys.platform == 'darwin' else 'xdg-open')
        opener.write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> "$RHUN_DESKTOP_LOG"\n')
        opener.chmod(0o755)
        log = work / 'opened'
        env.update(PATH=str(bin_dir) + os.pathsep + os.environ.get('PATH', ''),
                   RHUN_DESKTOP_LOG=str(log))
        run([project, file], ['cmd website', 'wait 200', 'cmd email', 'wait 200',
                              'cmd feedback', 'wait 200',
                              'cmd reveal_file', 'wait 200', 'quit'])
        expected = ['https://rhun.app', 'mailto:hi@rhun.app?subject=rhun%20feedback',
                    'https://github.com/vshvedov/rhun/issues']
        expected += ['-R', file.as_posix()] if sys.platform == 'darwin' else [project.as_posix()]
        assert log.read_text().splitlines() == expected, log.read_text()
        print('ok   desktop/links-and-literal-file-path')

        log.unlink()
        with config.open('a') as settings:
            settings.write('[ui]\nagents_panel = false\n')
        run([project], ['cmd settings', 'click 300 202', 'wait 200',
                        'click 410 202', 'wait 200', 'click 510 202', 'wait 200', 'quit'])
        assert log.read_text().splitlines() == [
            'https://rhun.app', 'mailto:hi@rhun.app?subject=rhun%20feedback',
            'https://github.com/vshvedov/rhun/issues'], log.read_text()
        print('ok   desktop/settings-links')

        # The menu operates on a directory as well as a file, with the same path rules.
        log.unlink()
        directory = project / 'a folder café'
        directory.mkdir()
        output = run([project], ['click 50 86 right', 'print-menu', 'click 110 265',
                                  'wait 200', 'quit'])
        label = 'Show in Finder' if sys.platform == 'darwin' else 'Open in File Manager'
        assert label in output, output
        expected = ['-R', directory.as_posix()] if sys.platform == 'darwin' else [project.as_posix()]
        assert log.read_text().splitlines() == expected, log.read_text()
        print('ok   desktop/directory-context-menu-action')
