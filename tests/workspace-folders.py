#!/usr/bin/env python3
"""Workspace folders (resources group): folders from the command line, Add and Remove (nested, twice
and a 17th refused), remembered with the primary folder, the primary's removal, the explorer's roots,
quick open across folders; for extensions: "0 folders" before ready and again when folders change
(a program that reads the project restarts instead), folder-of, on = contains:, find-files over
every folder, a folder's own .rhun/extensions.ini. The fake extension is tests/ext/res.py."""
import os
from pathlib import Path
import re
import subprocess
import unittest

lifecycle = __import__('ext-lifecycle')
host = __import__('ext-host')
RES = lifecycle.RES


class Folders(lifecycle.Base):
    def setUp(self):
        super().setUp()
        self.app = self.proj
        self.lib = self.work / 'lib'
        (self.lib / 'pkg').mkdir(parents=True)
        (self.lib / 'pkg/p.go').write_text('package pkg\n')
        (self.app / 'src').mkdir()
        (self.app / 'src/main.rs').write_text('fn main() {}\n')
        self.root = self.work / 'exts'

    def ext(self, name, needs='', on='startup', features='workspace-folders', extra=''):
        folder = self.root / 'rt' / name
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'extension.ini').write_text(
            f'name = {name}\nowner = rt\ntitle = {name.title()}\nversion = 1\nprotocol = 1\n'
            f'runtime = python3\nrun = {RES.as_posix()}\non = {on}\n{extra}'
            '[commands]\nrequest = Request\nbatch = Batch\n'
            f'[needs]\nrun = python3\n{needs}', encoding='utf-8')
        state = self.work / f'state/rhun/extensions/rt--{name}'
        state.mkdir(parents=True, exist_ok=True)
        self.env[f'RES_FEATURES_{name}'] = features
        return state

    def run_ws(self, args, actions, files=()):
        self.env['RES_ARGS'] = '{state}/args.txt'
        self.env['RES_LOG'] = '{state}/res.log'
        script = self.work / 'actions.rsc'
        opens = ['open ' + str(f) for f in files]
        script.write_text('\n'.join(['wait 200', *opens, *actions, 'quit']) + '\n', encoding='utf-8')
        r = subprocess.run([str(host.EXE), *map(str, args), '--headless', '1000x700', '--extensions',
                            str(self.root), '--script', str(script)], env=self.env, capture_output=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr.decode(errors='replace'))
        return r.stdout.decode(errors='replace').splitlines()

    def folders(self, out):
        return [dict(x.split('=', 1) for x in l.split(' ') if '=' in x) for l in out if l.startswith('folder=')]

    def reslog(self, name):
        p = self.work / f'state/rhun/extensions/rt--{name}/res.log'
        return p.read_bytes().decode(errors='replace').splitlines() if p.exists() else []

    # ---------------- the editor ----------------

    def test_two_folders_from_the_command_line(self):
        out = self.run_ws([self.app, self.lib], ['print-folders', 'print-explorer', 'cmd quick_open', 'type pkg/p.go',
                                                  'print-palette', 'key Return', 'wait 100', 'print-tabs'])
        f = self.folders(out)
        self.assertEqual([x['name'] for x in f], ['proj', 'lib'])
        self.assertEqual(f[0]['flags'], '3')            # primary, trusted
        self.assertEqual(f[1]['flags'], '2')
        self.assertIn('proj/', out)
        self.assertIn('lib/', out)
        self.assertIn('  pkg/', out)
        self.assertIn('> lib/pkg/p.go', out)
        self.assertTrue(any(l.startswith('tabs=') and 'p.go' in l for l in out), out)

    def test_add_remove_and_remember(self):
        other = self.work / 'other'
        other.mkdir()
        many = []
        for i in range(15):
            d = self.work / f'm{i:02}'
            d.mkdir()
            many.append(d)
        out = self.run_ws([self.app], [f'folder-add {self.app / "src"}', f'folder-add {self.app}',
                                       f'folder-add {self.work}', f'folder-add {self.lib}', 'print-folders'])
        self.assertEqual(out[:3], ['error=22', 'error=17', 'error=22'])
        self.assertEqual([x['name'] for x in self.folders(out)], ['proj', 'lib'])
        # remembered with the primary folder
        out = self.run_ws([self.app], ['print-folders'])
        self.assertEqual([x['name'] for x in self.folders(out)], ['proj', 'lib'])
        # 16 at most
        out = self.run_ws([self.app], [f'folder-add {d}' for d in many] + ['print-folders'])
        self.assertEqual(out[14], 'error=28')
        self.assertEqual(len(self.folders(out)), 16)
        # a removal is remembered too
        out = self.run_ws([self.app], ['folder-remove 2', 'print-folders'])
        names = [x['name'] for x in self.folders(out)]
        self.assertNotIn('lib', names)
        self.assertEqual(len(names), 15)

    def test_removing_the_primary(self):
        out = self.run_ws([self.app, self.lib, self.work / 'lib'], ['folder-remove 1', 'wait 300', 'print-folders'])
        f = self.folders(out)
        self.assertEqual(f[0]['path'], str(self.lib))
        self.assertEqual(f[0]['flags'], '3')

    # ---------------- extensions ----------------

    def test_folders_event_and_folder_of(self):
        state = self.ext('wf')
        (state / 'args.txt').write_text(f'folder-of {self.lib}/pkg/p.go\nfolder-of {self.app}/src\n'
                                        f'folder-of /nowhere/x\nfolder-of file://{self.lib}/pkg\n')
        other = self.work / 'other'
        other.mkdir()
        out = self.run_ws([self.app, self.lib], ['wait-ext wf running', 'wait 300', 'cmd rt/wf.batch', 'wait 400',
                                                 'print-extensions', f'folder-add {other}', 'wait 600',
                                                 'print-extensions'])
        log = self.reslog('wf')
        i = log.index('0 features workspace-folders')
        self.assertTrue(log[i + 1].startswith('0 folders '), log)
        body = log[i + 2]
        self.assertTrue(body.startswith('body 2'), log)
        j = [n for n, l in enumerate(log) if l.startswith('0 ready ')][0]
        self.assertLess(i, j)
        self.assertIn(f'1 local 3 4 {len(str(self.app))}', '\n'.join(log))
        self.assertIn('ok 1 2', log)
        self.assertIn('ok 2 1', log)
        self.assertIn('ok 3 0', log)
        self.assertIn('ok 4 2', log)
        # a third folder: told again, the same program
        pids = [re.search(r'pid=(\d+)', l).group(1) for l in out if l.startswith('rt/wf ')]
        self.assertEqual(len(set(pids)), 1, out)
        self.assertEqual(sum(1 for l in log if l.startswith('0 folders ')), 2, log)
        self.assertIn('3 local 2 5', '\n'.join(log))

    def test_a_program_that_reads_the_project_restarts(self):
        self.ext('rd', needs='project = read\n')
        other = self.work / 'other'
        other.mkdir()
        out = self.run_ws([self.app], ['wait-ext rd running', 'wait 300', 'print-extensions', f'folder-add {other}',
                                       'wait 2500', 'wait-ext rd running', 'print-extensions'])
        pids = [re.search(r'pid=(\d+)', l).group(1) for l in out if l.startswith('rt/rd ')]
        self.assertEqual(len(pids), 2, out)
        self.assertNotEqual(pids[0], pids[1])

    def test_contains_activation(self):
        self.ext('cargo', on='contains:Cargo.toml contains:*.cabal', features='')
        out = self.run_ws([self.app], ['wait 500', 'print-extensions'])
        self.assertTrue(any(l.startswith('rt/cargo state=idle') for l in out), out)
        crate = self.work / 'crate'
        crate.mkdir()
        (crate / 'Cargo.toml').write_text('[package]\n')
        out = self.run_ws([self.app], [f'folder-add {crate}', 'wait 500', 'print-extensions'])
        self.assertTrue(any(l.startswith('rt/cargo state=running') for l in out), out)
        hs = self.work / 'hs'
        hs.mkdir()
        (hs / 'x.cabal').write_text('name: x\n')
        out = self.run_ws([hs], ['wait 500', 'print-extensions'])
        self.assertTrue(any(l.startswith('rt/cargo state=running') for l in out), out)

    def test_find_files_over_every_folder(self):
        state = self.ext('ff', needs='project = read\n', features='files workspace-folders')
        (state / 'args.txt').write_text('find-files 0 100 0 {LEN}|+*.{rs,go}\\n\nfind-files 2 100 0 {LEN}|\n')
        self.run_ws([self.app, self.lib], ['wait-ext ff running', 'wait 300', 'cmd rt/ff.request', 'wait 800',
                                           'cmd rt/ff.request', 'wait 800'])
        log = '\n'.join(self.reslog('ff'))
        self.assertIn('1 11\nsrc/main.rs', log)
        self.assertIn('2 8\npkg/p.go', log)
        self.assertIn('ok 1 3 complete', log)      # b.go of the host tests' project too
        self.assertIn('ok 2 1 complete', log)

    def test_find_files_in_two_repositories(self):
        import shutil
        if not shutil.which('git'):
            self.skipTest('git')
        (self.work / 'config/rhun/config').write_text(host.CONFIG.replace('enabled = false', 'enabled = true'))
        for repo, ignored in ((self.app, 'a.txt'), (self.lib, 'pkg/')):
            (repo / '.gitignore').write_text(ignored + '\n')
            g = ['git', '-C', str(repo), '-c', 'user.name=t', '-c', 'user.email=t@t']
            subprocess.run(['git', 'init', '-q', str(repo)], check=True, env=self.env)
            subprocess.run(g + ['add', '-A'], check=True, env=self.env)
            subprocess.run(g + ['commit', '-qm', 'one'], check=True, env=self.env)
        (self.lib / 'top.go').write_text('package lib\n')
        state = self.ext('ff', needs='project = read\n', features='files')
        (state / 'args.txt').write_text('find-files 0 100 0 {LEN}|\n')
        self.run_ws([self.app, self.lib], ['wait-ext ff running', 'wait 300', 'cmd rt/ff.request', 'wait 1500'])
        log = '\n'.join(self.reslog('ff'))
        self.assertNotIn('a.txt', log)                  # app's .gitignore
        self.assertNotIn('pkg/p.go', log)               # lib's own .gitignore
        self.assertIn('2 6\ntop.go', log)               # lib's untracked file, through its git
        self.assertIn('1 11\nsrc/main.rs', log)

    def git_repos(self, branches=('main', 'feature')):
        import shutil
        if not shutil.which('git'):
            self.skipTest('git')
        (self.work / 'config/rhun/config').write_text(host.CONFIG.replace('enabled = false', 'enabled = true'))
        for repo, branch in zip((self.app, self.lib), branches):
            g = ['git', '-C', str(repo), '-c', 'user.name=t', '-c', 'user.email=t@t']
            subprocess.run(['git', 'init', '-q', str(repo)], check=True, env=self.env)
            subprocess.run(g + ['checkout', '-qb', branch], check=True, env=self.env)
            subprocess.run(g + ['add', '-A'], check=True, env=self.env)
            subprocess.run(g + ['commit', '-qm', 'one'], check=True, env=self.env)

    def repos(self, out):
        return [dict(x.split('=', 1) for x in l.split(' ') if '=' in x) for l in out if l.startswith('repo=')]

    def test_every_folders_repository(self):
        """Each folder's repository: its own status colours the explorer, the active document's folder's
        repository is the one shown (branch, Source Control), a repository line picks another, and the
        one shown goes back to the project's when its folder is removed."""
        self.git_repos()
        (self.lib / 'pkg/p.go').write_text('package pkg // changed\n')
        (self.lib / 'new.go').write_text('package lib\n')
        (self.app / 'src/main.rs').write_text('fn main() { }\n')
        shot = Path(os.environ.get('RHUN_GR_SHOT', self.work / 'scm.ppm'))
        lib, app = self.lib.as_posix(), self.app.as_posix()
        out = self.run_ws([self.app, self.lib], [
            'wait-git', 'print-repos', f'print-vcs {lib}/pkg/p.go', f'print-vcs {lib}/new.go',
            f'print-vcs {lib}/pkg', f'print-vcs {lib}/top.go', f'print-vcs {app}/src/main.rs', 'print-git',
            f'open {lib}/pkg/p.go', 'wait 100', 'wait-git', 'print-repos', 'print-git',
            f'print-vcs {app}/src/main.rs', f'print-vcs {lib}/pkg/p.go',
            'cmd git_history', 'wait-git', f'shot {shot}',
            'click 650 98', 'wait 100', 'wait-git', 'print-repos', 'print-git',  # proj's line
            'repo-show 1', 'wait 100', 'wait-git', 'print-folders', 'folder-remove 2', 'wait 100', 'wait-git',
            'print-repos', 'print-git'])
        marks = [l for l in out if l.startswith(('repo=', 'vcs=', 'git ')) or l.startswith('folder=')]
        r = [self.repos(out[:i]) for i, l in enumerate(out) if l.startswith('git ')]
        self.assertEqual([(x['repo'], x['branch'], x['shown']) for x in r[0]],
                         [('proj', 'main', '1'), ('lib', 'feature', '0')], marks)
        self.assertEqual(r[0][1]['changes'], '2', marks)
        vcs = [l.split(' ')[0] for l in out if l.startswith('vcs=')]
        self.assertEqual(vcs[:5], ['vcs=M', 'vcs=U', 'vcs=M', 'vcs=-', 'vcs=M'], marks)
        git = [l for l in out if l.startswith('git ')]
        self.assertIn('branch=main', git[0])
        # the active document is lib's: its repository is shown, the project's keeps its colours
        self.assertEqual([x['shown'] for x in self.repos(out[:out.index(git[1])])[-2:]], ['0', '1'], marks)
        self.assertIn('branch=feature', git[1])
        self.assertEqual(vcs[5:7], ['vcs=M', 'vcs=M'], marks)
        self.assertTrue(shot.exists() and shot.stat().st_size > 1000)
        # proj's line clicked: the project's again
        self.assertIn('branch=main', git[2])
        # lib's folder removed while shown: the project's
        self.assertEqual([x['repo'] for x in self.repos(out[out.index(git[2]):])][-1:], ['proj'], marks)
        self.assertIn('branch=main', git[3], marks)

    def test_a_folders_own_settings(self):
        state = self.ext('st', features='scoped-settings', extra='', on='startup')
        ini = self.root / 'rt/st/extension.ini'
        ini.write_text(ini.read_text() + '[settings]\nstyle.type = choice\nstyle.options = a b c\nstyle.default = a\n'
                       'style.scope = folder\n')
        (self.app / '.rhun').mkdir()
        (self.app / '.rhun/extensions.ini').write_text('[rt/st]\nsetting.style = b\n')
        (self.lib / '.rhun').mkdir()
        (self.lib / '.rhun/extensions.ini').write_text('[rt/st]\nsetting.style = c\n')
        (state / 'args.txt').write_text('setting-get style 0 -\nsetting-get style 1 -\nsetting-get style 2 -\n')
        self.run_ws([self.app, self.lib], ['wait-ext st running', 'wait 300', 'cmd rt/st.batch', 'wait 500'])
        log = self.reslog('st')
        bodies = [l[5:] for l in log if l.startswith('body ')]
        self.assertEqual(bodies, ['b', 'b', 'c'], log)

    # ---------------- workspace files ----------------

    def test_workspace_files(self):
        self.run_ws([self.app, self.lib], ['workspace-save team', 'print-folders'])
        wsfile = self.app / 'team.rhun-workspace'
        text = wsfile.read_text()
        self.assertIn('[folders]\npath = .\n', text)
        self.assertIn(f'path = {self.lib}\n', text)
        # settings in it; a fresh state: the folders come from the file alone
        state = self.ext('st', features='scoped-settings')
        ini = self.root / 'rt/st/extension.ini'
        ini.write_text(ini.read_text() + '[settings]\nstyle.type = choice\nstyle.options = a b c\nstyle.default = a\n'
                       'style.scope = folder\n')
        wsfile.write_text(text + '\n[rt/st]\nsetting.style = c\n')
        (self.app / '.rhun').mkdir()
        (self.app / '.rhun/extensions.ini').write_text('[rt/st]\nsetting.style = b\n')
        for f in (self.work / 'state/rhun').glob('*.folders'):
            f.unlink()
        (state / 'args.txt').write_text('setting-get style 0 -\nsetting-get style 1 -\nsetting-get style 2 -\n')
        out = self.run_ws([wsfile], ['print-folders', 'wait-ext st running', 'wait 300', 'cmd rt/st.batch', 'wait 500',
                                     'workspace-save team'])
        self.assertEqual([x['path'] for x in self.folders(out)], [str(self.app), str(self.lib)])
        bodies = [l[5:] for l in self.reslog('st') if l.startswith('body ')]
        self.assertEqual(bodies, ['c', 'b', 'c'])       # the file's for the window and lib, the folder's own
        self.assertIn('[rt/st]\nsetting.style = c', wsfile.read_text())   # kept when saved again


if __name__ == '__main__':
    unittest.main()
