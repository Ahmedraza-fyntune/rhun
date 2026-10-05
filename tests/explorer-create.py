#!/usr/bin/env python3
"""Explorer creation: the header's New File and New Folder buttons, the prompt saying what it creates,
and the menu of the empty space below the rows (the project folder, without Rename and Delete)."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()

# 1000x700 at scale 1: the explorer header's buttons (New File, New Folder, Refresh) end 8 points from
# its right edge at 240; the first row is at 80. A menu opened at 600 is moved up to fit: its items
# start at 566 and are 32 high.
NEW_FILE = 'click 162 60'
NEW_FOLDER = 'click 190 60'
EMPTY = 'click 120 600 right'
ITEM = [f'click 180 {582 + 32 * i}' for i in range(4)]

with tempfile.TemporaryDirectory(prefix='rhun-create-') as temporary:
    work = Path(temporary).resolve()
    project = work / "project café ' $test"
    project.mkdir()
    (project / 'src').mkdir()
    (project / 'src' / 'main.c').write_text('int main(void) { return 0; }\n')
    config = work / 'config/rhun/config'
    config.parent.mkdir(parents=True)
    config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                      '[updates]\ncheck = false\n[git]\nenabled = false\n[ui]\nagents_panel = false\n')
    env = dict(os.environ, HOME=str(work), XDG_CONFIG_HOME=str(work / 'config'),
               XDG_STATE_HOME=str(work / 'state'))

    def run(lines):
        script = work / 'commands.rsc'
        script.write_text('\n'.join([*lines, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(project), '--headless', '1000x700', '--scale', '1',
                                 '--script', str(script)], env=env, capture_output=True, timeout=20, check=True)
        return result.stdout.decode('utf-8')

    def field(output):
        # the prompt's text, with the platform's separators as /
        lines = [line for line in output.splitlines() if line.startswith('field=')]
        return [line[6:].replace('\\', '/') for line in lines]

    output = run([NEW_FILE, 'print-palette', 'type docs/notes.md', 'key Return', 'print-state'])
    assert 'prompt=New file\n' in output, output
    assert field(output)[0].endswith('/' + project.name + '/'), output
    assert (project / 'docs' / 'notes.md').is_file()
    assert 'active=notes.md ' in output, output
    print('ok   explorer/new-file-button')

    output = run([NEW_FOLDER, 'print-palette', 'type assets/icons', 'key Return', 'print-palette'])
    assert 'prompt=New folder\n' in output and output.endswith('none\n'), output
    assert (project / 'assets' / 'icons').is_dir()
    print('ok   explorer/new-folder-button')

    # The empty space's menu creates in the project folder, even after a folder's row was selected.
    output = run(['click 50 86', EMPTY, 'print-menu', ITEM[1], 'print-palette', 'type empty-space',
                  'key Return'])
    label = {'darwin': 'Show in Finder', 'win32': 'Show in Explorer'}.get(sys.platform, 'Open in File Manager')
    assert f'New File\nNew Folder\nCopy Path\n{label}\n' in output, output
    assert 'Rename' not in output and 'Delete' not in output, output
    assert 'prompt=New folder\n' in output and field(output)[0].endswith('/' + project.name + '/'), output
    assert (project / 'empty-space').is_dir()
    output = run([EMPTY, ITEM[0], 'print-palette', 'key Escape'])
    assert 'prompt=New file\n' in output and field(output)[0].endswith('/' + project.name + '/'), output
    print('ok   explorer/empty-space-menu-creates-at-the-top')

    output = run([EMPTY, ITEM[2], 'cmd new_file', 'key ctrl+v', 'print-doc'])
    assert output.replace('\\', '/').rstrip('\n').removesuffix('<eod>').rstrip('\n').endswith('/' + project.name), output
    print('ok   explorer/empty-space-copy-path')

    # Rename and Delete never take the project folder from that menu.
    output = run([EMPTY, 'key Escape', 'cmd focus_explorer', 'cmd delete_file', 'print-state',
                  'cmd rename_file', 'print-palette'])
    assert 'focus=5 ' not in output and output.endswith('none\n'), output
    assert project.is_dir() and (project / 'src' / 'main.c').is_file()
    print('ok   explorer/empty-space-keeps-project-safe')
