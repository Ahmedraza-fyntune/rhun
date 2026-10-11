#!/usr/bin/env python3
"""Open tabs follow the explorer: deleting a file or a folder closes the tabs of what it removed
(not one with unsaved changes), and renaming a folder moves the tabs of the files inside it."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()

FOLDER_MENU = 'click 50 86 right'        # the first row: the folder
MENU_RENAME, MENU_DELETE = 'click 110 165', 'click 110 205'
CONFIRM = 'click 550 345'

with tempfile.TemporaryDirectory(prefix='rhun-explorer-tabs-') as temporary:
    work = Path(temporary).resolve()
    project = work / 'project'
    config = work / 'config/rhun/config'
    config.parent.mkdir(parents=True)
    config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                      '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
    env = dict(os.environ, HOME=work.as_posix(), XDG_CONFIG_HOME=(work / 'config').as_posix(),
               XDG_STATE_HOME=(work / 'state').as_posix())

    def fresh():
        shutil.rmtree(project, ignore_errors=True)
        (project / 'd').mkdir(parents=True)
        for name, text in (('d/a.txt', 'alpha\n'), ('d/b.txt', 'beta\n'), ('c.txt', 'gamma\n')):
            (project / name).write_text(text, encoding='utf-8')

    def run(lines, *files):
        script = work / 'commands.rsc'
        script.write_text('\n'.join([*lines, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), project.as_posix(), *(f.as_posix() for f in files),
                                 '--headless', '1000x700', '--scale', '1', '--script', script.as_posix()],
                                env=env, capture_output=True, timeout=30)
        assert result.returncode == 0, result.stderr.decode(errors='replace')
        out = result.stdout.decode('utf-8')
        assert 'unknown command' not in out, out
        return [line for line in out.splitlines() if line.startswith('tabs=')]

    fresh()
    tabs = run(['print-tabs', 'cmd delete_file', CONFIRM, 'print-tabs'],
               project / 'c.txt', project / 'd/a.txt')
    assert not (project / 'd/a.txt').exists()
    assert tabs == ['tabs=c.txt | *a.txt', 'tabs=*c.txt'], tabs
    print('ok   explorer-tabs/deleting-the-open-file-closes-its-tab')

    fresh()
    # b.txt is the active tab and gets an unsaved change
    tabs = run(['type X', 'print-tabs', FOLDER_MENU, MENU_DELETE, CONFIRM, 'print-tabs'],
               project / 'c.txt', project / 'd/a.txt', project / 'd/b.txt')
    assert not (project / 'd').exists()
    assert tabs[0] == 'tabs=c.txt | a.txt | *b.txt', tabs
    assert tabs[1] == 'tabs=c.txt | *b.txt', tabs
    print('ok   explorer-tabs/deleting-a-folder-closes-its-clean-tabs')

    if os.name != 'nt' and os.geteuid() != 0:
        # a deletion that fails part way: the tab of the file still there stays open
        fresh()
        (project / 'd/sub').mkdir()
        (project / 'd/sub/kept.txt').write_text('kept\n', encoding='utf-8')
        (project / 'd/sub').chmod(0o500)
        try:
            tabs = run([FOLDER_MENU, MENU_DELETE, CONFIRM, 'print-tabs'],
                       project / 'd/sub/kept.txt', project / 'd/a.txt')
        finally:
            (project / 'd/sub').chmod(0o700)
        # the folder's entries come in the order the file system lists them: a.txt may go or stay
        assert (project / 'd/sub/kept.txt').exists()
        names = tabs[0].removeprefix('tabs=').replace('*', '').split(' | ')
        assert names == ['kept.txt'] + ['a.txt'] * (project / 'd/a.txt').exists(), tabs
        print('ok   explorer-tabs/a-failed-deletion-keeps-the-tabs-of-what-is-left')

    fresh()
    tabs = run([FOLDER_MENU, MENU_RENAME, 'key ctrl+a', 'type e', 'key Return', 'wait 100',
                'type X', 'key ctrl+s', 'wait 100', 'print-tabs'], project / 'd/a.txt')
    assert tabs == ['tabs=*a.txt'], tabs
    assert not (project / 'd').exists()
    assert (project / 'e/a.txt').read_text(encoding='utf-8') == 'Xalpha\n'
    print('ok   explorer-tabs/renaming-a-folder-moves-its-tabs')

    if os.name == 'nt':
        # Windows paths compare without case: a file opened as D\A.TXT closes with the folder d
        fresh()
        tabs = run([FOLDER_MENU, MENU_DELETE, CONFIRM, 'print-tabs'],
                   project / 'c.txt', Path(str(project / 'D' / 'A.TXT')))
        assert tabs == ['tabs=*c.txt'], tabs
        print('ok   explorer-tabs/windows-paths-compare-without-case')
