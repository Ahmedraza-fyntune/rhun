#!/usr/bin/env python3
"""A repository a rhun://file/ link opens runs no git until it is trusted. Its own config can name
programs that git runs: a clean filter runs on git status as soon as the index's file times do not
match, as in a repository unpacked from an archive. A web page can link to such a folder, so git is
paused there behind a bar (Trust folder, or the palette's Trust Folder for Git), which remembers the
folder. Folders opened otherwise (command line, Finder, Open Folder) work as before."""
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import unittest
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
# at 1000x600, scale 1: the bar is y 40 to 68 over the editor column, Trust folder and its close
# button at its right end
BAR_Y = 54
TRUST_X = 920
CLOSE_X = 986


@unittest.skipIf(os.name == 'nt', 'the filter is a shell command')
class GitTrust(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-trust-')
        self.work = Path(self.tmp.name).resolve()
        self.marker = self.work / 'ran'
        self.env = dict(os.environ, HOME=str(self.work),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(),
                        GIT_CONFIG_NOSYSTEM='1')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = true\n'
                          '[editor]\ncursor_blink = false\n'
                          '[ui]\nagents_panel = false\nsidebar = false\n', encoding='utf-8')
        # a repository whose config names a clean filter for every file, packed and unpacked again:
        # its index's file times then match nothing, and git status runs the filter on each file
        source = self.work / 'source'
        source.mkdir()
        self.git(source, 'init', '-q', '-b', 'main')
        self.git(source, 'config', 'user.name', 'Test')
        self.git(source, 'config', 'user.email', 'test@example.invalid')
        (source / '.gitattributes').write_text('* filter=probe\n')
        (source / 'a.txt').write_text('one\ntwo\nthree\n')
        self.git(source, 'add', '-A')
        self.git(source, 'commit', '-qm', 'Initial')
        self.git(source, 'config', 'filter.probe.clean', f'sh -c \'touch "{self.marker}"; cat\'')
        with tarfile.open(self.work / 'repo.tar', 'w') as archive:
            archive.add(source, arcname='repo')
        shutil.rmtree(source)
        time.sleep(1.1)
        with tarfile.open(self.work / 'repo.tar') as archive:
            archive.extractall(self.work / 'downloads')
        self.repo = self.work / 'downloads/repo'

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, folder, *args):
        return subprocess.run(['git', '-C', str(folder), *args], env=self.env, check=True,
                              capture_output=True).stdout

    def link(self, path, end=''):
        return 'rhun://file' + urllib.parse.quote(str(path)) + end

    def run_editor(self, paths, actions):
        script = self.work / 'commands.rsc'
        script.write_text('\n'.join(['wait-git', *actions, 'quit']) + '\n', encoding='utf-8')
        elsewhere = self.work / 'elsewhere'     # a launch without a project takes up its folder
        elsewhere.mkdir(exist_ok=True)
        result = subprocess.run([str(EXE), *paths, '--headless', '1000x600', '--scale', '1',
                                 '--script', str(script)], env=self.env, capture_output=True, timeout=30,
                                cwd=elsewhere)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return [line for line in result.stdout.decode('utf-8').splitlines() if line.startswith('git ')]

    def trusted(self):
        listed = self.work / 'state/rhun/trusted-folders'
        return listed.read_text(encoding='utf-8').splitlines() if listed.exists() else []

    def test_the_repository_runs_its_filter_for_git(self):
        # so that the tests below would see it run
        self.git(self.repo, 'status', '--porcelain')
        self.assertTrue(self.marker.exists())

    def test_a_link_pauses_git_until_trusted(self):
        for target in (self.link(self.repo / 'a.txt', ':2'), self.link(self.repo, '/')):
            with self.subTest(link=target):
                self.assertEqual(self.run_editor([target], ['print-git']), ['git paused branch=main'])
                self.assertFalse(self.marker.exists(), 'git ran in a repository a link opened')
        # the bar's Trust folder: git starts, and the folder is remembered
        out = self.run_editor([self.link(self.repo / 'a.txt')], ['print-git', f'click {TRUST_X} {BAR_Y}',
                                                                 'wait-git', 'print-git'])
        self.assertEqual(out, ['git paused branch=main', 'git on branch=main'])
        self.assertTrue(self.marker.exists())
        self.assertEqual(self.trusted(), [str(self.repo)])
        self.marker.unlink()
        self.assertEqual(self.run_editor([self.link(self.repo, '/')], ['print-git']), ['git on branch=main'])

    def test_a_launch_without_arguments_does_not_reopen_it_untrusted(self):
        # the last project comes back with restore_project: not one a link opened while git is paused
        # there, as it would come back as a folder opened by hand; once trusted, it does
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text(encoding='utf-8').replace('restore_project = false',
                                                                     'restore_project = true'), encoding='utf-8')
        self.assertEqual(self.run_editor([self.link(self.repo, '/')], ['print-git']), ['git paused branch=main'])
        self.assertEqual(self.run_editor([], ['print-git']), ['git off branch='])
        self.assertFalse(self.marker.exists())
        self.assertEqual(self.run_editor([self.link(self.repo, '/')], ['cmd trust_folder', 'wait-git', 'print-git']),
                         ['git on branch=main'])
        self.assertEqual(self.run_editor([], ['print-git']), ['git on branch=main'])

    def test_git_turned_off_keeps_the_pause(self):
        # a link's folder is paused with git off too, so that the last project does not come back as a
        # folder opened by hand once git is on
        config = self.work / 'config/rhun/config'
        text = config.read_text(encoding='utf-8').replace('restore_project = false', 'restore_project = true')
        config.write_text(text.replace('enabled = true', 'enabled = false'), encoding='utf-8')
        self.assertEqual(self.run_editor([self.link(self.repo, '/')], ['print-git']), ['git paused branch=main'])
        config.write_text(text, encoding='utf-8')
        self.assertEqual(self.run_editor([], ['print-git']), ['git off branch='])
        self.assertFalse(self.marker.exists(), 'git ran in a repository a link opened')

    def test_no_session_while_paused(self):
        # a session file would list the folder among the recent ones, which open it as by hand
        def sessions():
            return sorted(p.name for p in (self.work / 'state/rhun').glob('*.session'))
        config = self.work / 'config/rhun/config'
        config.write_text(config.read_text(encoding='utf-8').replace('restore_session = false',
                                                                     'restore_session = true'), encoding='utf-8')
        self.run_editor([self.link(self.repo, '/')], ['print-git'])
        self.assertEqual(sessions(), [])
        self.run_editor([self.link(self.repo, '/')], ['cmd trust_folder', 'wait-git'])
        self.assertEqual(len(sessions()), 1)

    def test_the_list_keeps_an_entry_without_a_line_break(self):
        listed = self.work / 'state/rhun/trusted-folders'
        listed.parent.mkdir(parents=True)
        listed.write_text('/some/other', encoding='utf-8')
        self.run_editor([self.link(self.repo, '/')], ['cmd trust_folder', 'wait-git'])
        self.assertEqual(self.trusted(), ['/some/other', str(self.repo)])

    def test_a_fifo_for_head_does_not_hang(self):
        # opening a FIFO to read waits for a writer; rhun reads its files without waiting
        fifo = self.work / 'fifo'
        (fifo / '.git/refs/heads').mkdir(parents=True)
        os.mkfifo(fifo / '.git/HEAD')
        (fifo / 'a.txt').write_text('a\n', encoding='utf-8')
        self.assertEqual(self.run_editor([self.link(fifo / 'a.txt')], ['print-git']), ['git paused branch='])

    def test_closing_the_bar_keeps_git_paused(self):
        out = self.run_editor([self.link(self.repo / 'a.txt')], [f'click {CLOSE_X} {BAR_Y}', 'wait 100',
                                                                 'print-git', 'cmd trust_folder', 'wait-git',
                                                                 'print-git'])
        self.assertEqual(out, ['git paused branch=main', 'git on branch=main'])
        self.assertEqual(self.trusted(), [str(self.repo)])

    def test_a_folder_opened_otherwise_runs_git(self):
        self.assertEqual(self.run_editor([str(self.repo)], ['print-git']), ['git on branch=main'])
        self.assertTrue(self.marker.exists())
        self.assertEqual(self.trusted(), [])

    def test_a_link_into_the_open_project_keeps_git(self):
        # the window's own project, opened from the command line: a link to a file in it changes
        # nothing; a link to another folder, which becomes the project, pauses git
        other = self.work / 'other'
        other.mkdir()
        self.git(other, 'init', '-q', '-b', 'trunk')
        out = self.run_editor([str(self.repo)], [f'open {self.link(self.repo / "a.txt", ":3")}', 'wait-git',
                                                 'print-git', f'open {self.link(other, "/")}', 'wait-git',
                                                 'print-git'])
        self.assertEqual(out, ['git on branch=main', 'git paused branch=trunk'])


if __name__ == '__main__':
    unittest.main()
