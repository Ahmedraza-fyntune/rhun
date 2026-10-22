#!/usr/bin/env python3
"""rhun new-extension and Extensions: New Extension... (docs/guide.md, "New extensions"), with no
network: RHUN_NEW_EXT_BASE points at a folder of archives laid out as codeload.github.com serves
them (BASE/rhun-editor/template-go/tar.gz/refs/heads/main). The archives are small stand-ins for
the templates (every place a template names itself) and the skills repository; with the real
template repositories at RHUN_TEMPLATES (git checkouts of rhun-editor/template-go, template-rust
and skills), their archives are made with git archive and the result is built with go and cargo
when those are installed. Covered: the flags for both languages, what is renamed, the skills in
both agents' folders, a folder that is not empty, archives with a link or a path outside
themselves, no terminal without the flags (the usage line), git config's github.user with --yes,
the questions in a terminal (a pty: arrows, digits, Ctrl+C putting the terminal back), and the
GUI's quick input steps, its result notification, Dev Install, a failure and Cancel."""
import io
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
TEMPLATES = Path(os.environ.get('RHUN_TEMPLATES', '/Users/vsh/tmp/rhun-editor'))
WINDOWS = os.name == 'nt'
CONFIG = ('[files]\nrestore_session = false\nrestore_project = false\n[updates]\ncheck = false\n'
          'extensions = off\n[git]\nenabled = false\n[ui]\nsidebar = false\nagents_panel = false\n'
          '[editor]\ncursor_blink = false\n')

MANIFEST = '''# The manifest.
name = hello
owner = rhun-editor
title = Hello
description = A starting point.
version = 0.1.0
protocol = 1
run.linux-x86_64 = bin/hello-linux-x86_64
run.macos-arm64 = bin/hello-macos-arm64
run.windows-x64 = bin/hello-windows-x64.exe
on = command

[commands]
say = Say Hello

[status]
hello.text = Hello
hello.command = say
'''
BASIC_TXT = '''# where DIR/rhun-editor/hello holds extension.ini and bin/
print-extensions
cmd hello.say
wait-ext hello running
print-toast
'''
BASIC_EXPECTED = '''rhun-editor/hello state=idle pid=0 cmds=hello.say,hello.upper confined=0
side=left prio=0 owner=rhun-editor/hello item=hello text=Hello
ext=hello state=running
hello world
'''
RUN_SH = '''#!/bin/sh
status=$(run | sed -n 's/^.*owner=rhun-editor\\/hello .* at=\\(.*\\)$/\\1/p')
'''


def template(lang):
    files = {'extension.ini': MANIFEST, 'README.md': '# rhun extension template (%s)\n\nText.\n' % lang,
             'AGENTS.md': '# Working on this rhun extension\n', 'CLAUDE.md': '@AGENTS.md\n',
             'tests/basic.txt': BASIC_TXT, 'tests/basic.expected': BASIC_EXPECTED, 'tests/run.sh': RUN_SH,
             '.claude/skills/rhun-extension/SKILL.md': 'the template copy\n'}
    if lang == 'go':
        files['go.mod'] = 'module github.com/rhun-editor/template-go\n\ngo 1.25\n'
        files['main.go'] = 'package main\n\nfunc main() {}\n'
    else:
        files['Cargo.toml'] = '[package]\nname = "hello"\nversion = "0.1.0"\n\n[dependencies]\nrhun-ext = "1"\n'
        files['Cargo.lock'] = 'version = 4\n\n[[package]]\nname = "hello"\nversion = "0.1.0"\n\n[[package]]\nname = "rhun-ext"\n'
        files['src/main.rs'] = 'fn main() {}\n'
    return files


SKILLS = {'README.md': '# Skills\n', 'plugins/rhun/skills/rhun-extension/SKILL.md': 'the latest skill\n',
          'plugins/rhun/skills/rhun-extension/reference/go.md': 'go reference\n',
          'plugins/rhun/.codex-plugin/plugin.json': '{}\n'}


def archive(prefix, files, extra=None):
    """A .tar.gz as GitHub's codeload makes one: everything under PREFIX/; extra(tar) adds more."""
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w:gz') as tar:
        dirs = set()
        for name in sorted(files):
            parts = (prefix + '/' + name).split('/')
            for i in range(1, len(parts)):
                d = '/'.join(parts[:i])
                if d not in dirs:
                    dirs.add(d)
                    info = tarfile.TarInfo(d + '/')
                    info.type = tarfile.DIRTYPE
                    info.mode = 0o755
                    tar.addfile(info)
            body = files[name].encode()
            info = tarfile.TarInfo(prefix + '/' + name)
            info.size = len(body)
            info.mode = 0o755 if name.endswith('.sh') else 0o644
            tar.addfile(info, io.BytesIO(body))
        if extra:
            extra(tar)
    return data.getvalue()


def add_link(tar):
    info = tarfile.TarInfo('template-go-main/evil')
    info.type = tarfile.SYMTYPE
    info.linkname = '/etc/passwd'
    tar.addfile(info)


def add_dotdot(tar):
    body = b'outside\n'
    info = tarfile.TarInfo('template-go-main/../outside.txt')
    info.size = len(body)
    tar.addfile(info, io.BytesIO(body))


class Base(unittest.TestCase):
    def setUp(self):
        self.work = Path(tempfile.mkdtemp(prefix='rhun-newext-')).resolve()
        self.home = self.work / 'home'
        (self.home / 'config/rhun').mkdir(parents=True)
        (self.home / 'config/rhun/config').write_text(CONFIG, encoding='utf-8')
        (self.home / 'tmp').mkdir()
        self.base = self.work / 'base'
        self.out = self.work / 'out'
        self.out.mkdir()
        self.publish('template-go', template('go'))
        self.publish('template-rust', template('rust'))
        self.publish('skills', SKILLS)

    def tearDown(self):
        shutil.rmtree(self.work, ignore_errors=True)

    def publish(self, repo, files, extra=None, data=None):
        path = self.base / 'rhun-editor' / repo / 'tar.gz/refs/heads/main'
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() or path.is_symlink():
            path.unlink()
        path.write_bytes(data if data is not None else archive(repo + '-main', files, extra))
        return path

    def env(self, **extra):
        env = dict(os.environ)
        for k in ('RHUN_NEW_EXT_BASE', 'XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'GIT_DIR'):
            env.pop(k, None)
        env.update(HOME=str(self.home), USERPROFILE=str(self.home), XDG_CONFIG_HOME=str(self.home / 'config'),
                   XDG_STATE_HOME=str(self.home / 'state'), TMPDIR=str(self.home / 'tmp'),
                   RHUN_NEW_EXT_BASE=self.base.as_uri(), GIT_CONFIG_NOSYSTEM='1')
        env.update(extra)
        return env

    def cli(self, *args, **env):
        """rhun new-extension ARGS without a terminal: (status, output, errors)."""
        r = subprocess.run([str(EXE), 'new-extension', *map(str, args)], cwd=self.out, env=self.env(**env),
                           stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        return r.returncode, r.stdout.decode('utf-8', 'replace'), r.stderr.decode('utf-8', 'replace')

    def leftovers(self, folder=None):
        return [p.name for p in (folder or self.out).iterdir() if p.name.startswith('.rhun-new-')]

    def read(self, d, name):
        return (d / name).read_text(encoding='utf-8')


class Flags(Base):
    def test_go_with_the_flags(self):
        code, out, err = self.cli('my-ext', '--owner', 'octo', '--lang', 'go')
        self.assertEqual(code, 0, err)
        d = self.out / 'my-ext'
        ini = self.read(d, 'extension.ini')
        for line in ('name = my-ext', 'owner = octo', 'title = My Ext', 'run.linux-x86_64 = bin/my-ext-linux-x86_64',
                     'run.macos-arm64 = bin/my-ext-macos-arm64', 'run.windows-x64 = bin/my-ext-windows-x64.exe',
                     'hello.text = Hello', 'description = A starting point.'):
            self.assertIn(line + '\n', ini)
        self.assertNotIn('rhun-editor', ini)
        self.assertEqual(self.read(d, 'go.mod').splitlines()[0], 'module github.com/octo/my-ext')
        self.assertEqual(self.read(d, 'tests/basic.txt'), BASIC_TXT.replace('rhun-editor/hello', 'octo/my-ext')
                         .replace('cmd hello.say', 'cmd my-ext.say').replace('wait-ext hello', 'wait-ext my-ext'))
        expected = self.read(d, 'tests/basic.expected').splitlines()
        self.assertEqual(expected, ['octo/my-ext state=idle pid=0 cmds=my-ext.say,my-ext.upper confined=0',
                                    'side=left prio=0 owner=octo/my-ext item=hello text=Hello',
                                    'ext=my-ext state=running', 'hello world'])
        self.assertIn('owner=octo\\/my-ext .*', self.read(d, 'tests/run.sh'))
        if not WINDOWS:
            self.assertTrue(os.stat(d / 'tests/run.sh').st_mode & stat.S_IXUSR)
        self.assertTrue(self.read(d, 'README.md').startswith('# My Ext\n\nText.\n'))
        # the latest skill for both agents, replacing the template's copy
        for agent in ('.claude', '.agents'):
            self.assertEqual(self.read(d, agent + '/skills/rhun-extension/SKILL.md'), 'the latest skill\n')
            self.assertEqual(self.read(d, agent + '/skills/rhun-extension/reference/go.md'), 'go reference\n')
        self.assertEqual(self.read(d, 'AGENTS.md'), '# Working on this rhun extension\n')
        if shutil.which('git'):
            self.assertTrue((d / '.git').is_dir())
            log = subprocess.run(['git', '-C', str(d), 'log'], capture_output=True, env=self.env())
            self.assertNotEqual(log.returncode, 0)      # no commit
        self.assertIn('Created octo/my-ext (Go) in ' + str(d), out)
        self.assertIn('Link Extension Folder (development)', out)
        self.assertEqual(self.leftovers(), [])

    def test_rust_without_the_skills(self):
        code, out, err = self.cli('--name', 'rs-ext', '--owner', 'Octo-Org', '--lang', 'rust', '--no-skills',
                                  self.out / 'nested' / 'place')
        self.assertEqual(code, 0, err)
        d = self.out / 'nested/place'
        self.assertIn('name = "rs-ext"\n', self.read(d, 'Cargo.toml'))
        lock = self.read(d, 'Cargo.lock')
        self.assertIn('name = "rs-ext"\n', lock)
        self.assertIn('name = "rhun-ext"\n', lock)
        self.assertIn('owner = Octo-Org\n', self.read(d, 'extension.ini'))
        self.assertFalse((d / 'go.mod').exists())
        self.assertEqual(self.read(d, '.claude/skills/rhun-extension/SKILL.md'), 'the template copy\n')
        self.assertFalse((d / '.agents').exists())
        self.assertIn('Created Octo-Org/rs-ext (Rust)', out)

    def test_agents_md_is_written_when_the_template_has_none(self):
        files = template('go')
        del files['AGENTS.md'], files['CLAUDE.md']
        self.publish('template-go', files)
        code, out, err = self.cli('pointer', '--owner', 'octo', '--lang', 'go')
        self.assertEqual(code, 0, err)
        d = self.out / 'pointer'
        self.assertIn('.agents/skills/rhun-extension/SKILL.md', self.read(d, 'AGENTS.md'))
        self.assertEqual(self.read(d, 'CLAUDE.md'), '@AGENTS.md\n')

    def test_an_empty_folder_is_used_and_a_full_one_refused(self):
        (self.out / 'empty').mkdir()
        code, out, err = self.cli('empty', '--owner', 'octo', '--lang', 'go')
        self.assertEqual(code, 0, err)
        self.assertTrue((self.out / 'empty/extension.ini').exists())
        full = self.out / 'full'
        full.mkdir()
        (full / 'mine.txt').write_text('keep', encoding='utf-8')
        code, out, err = self.cli('full', '--owner', 'octo', '--lang', 'go')
        self.assertEqual(code, 1)
        self.assertIn('rhun new-extension: %s is not empty' % full, err)
        self.assertEqual(sorted(p.name for p in full.iterdir()), ['mine.txt'])
        self.assertEqual(self.leftovers(), [])

    def test_archives_with_a_link_or_a_path_outside_are_refused(self):
        if not WINDOWS:
            self.publish('template-go', template('go'), add_link)
            code, out, err = self.cli('linked', '--owner', 'octo', '--lang', 'go')
            self.assertEqual(code, 1)
            self.assertIn('rhun new-extension: the template holds links or devices', err)
            self.assertFalse((self.out / 'linked').exists())
        self.publish('template-go', template('go'), add_dotdot)
        code, out, err = self.cli('dotdot', '--owner', 'octo', '--lang', 'go')
        self.assertEqual(code, 1)
        self.assertIn('rhun new-extension: the template reaches outside itself', err)
        self.assertFalse((self.out / 'dotdot').exists())
        self.assertFalse((self.work / 'outside.txt').exists())
        self.assertEqual(self.leftovers(), [])
        self.publish('skills', SKILLS, lambda tar: add_dotdot_skills(tar))
        self.publish('template-go', template('go'))
        code, out, err = self.cli('skilled', '--owner', 'octo', '--lang', 'go')
        self.assertEqual(code, 1)
        self.assertIn('the skills archive reaches outside itself', err)
        self.assertFalse((self.out / 'skilled').exists())
        self.assertEqual(self.leftovers(), [])

    def test_a_missing_template_says_where_it_looked(self):
        shutil.rmtree(self.base / 'rhun-editor/template-go')
        code, out, err = self.cli('nothing', '--owner', 'octo', '--lang', 'go')
        self.assertEqual(code, 1)
        self.assertIn('could not download the Go template (' + self.base.as_uri() +
                      '/rhun-editor/template-go/tar.gz/refs/heads/main)', err)
        self.assertEqual(self.leftovers(), [])

    def test_without_a_terminal_the_flags_are_needed(self):
        usage = 'usage: rhun new-extension [DIR] [--name NAME] [--owner OWNER] [--lang rust|go]'
        for args, why in ((['--owner', 'octo', '--lang', 'go'], 'it needs --name NAME (or DIR)'),
                          (['x', '--lang', 'go'], 'it needs --owner OWNER'),
                          (['x', '--owner', 'octo'], 'it needs --lang rust|go'),
                          (['x', '--owner', 'octo', '--lang', 'cobol'], '--lang is rust or go'),
                          (['x', '--owner', 'octo', '--lang', 'go', '--bogus'], 'unknown option'),
                          (['x', 'y', '--owner', 'octo', '--lang', 'go'], 'one folder only')):
            code, out, err = self.cli(*args)
            self.assertEqual(code, 2, args)
            self.assertIn(why, err)
            self.assertIn(usage, err)
        code, out, err = self.cli('Bad_Name', '--owner', 'octo', '--lang', 'go')
        self.assertEqual(code, 2)
        self.assertIn('rhun new-extension: the name is lowercase letters, digits and dashes', err)
        code, out, err = self.cli('x', '--owner', '-octo', '--lang', 'go')
        self.assertEqual(code, 2)
        self.assertIn('the owner is a GitHub user or organization', err)
        code, out, err = self.cli('9lives', '--owner', 'octo', '--lang', 'rust')
        self.assertEqual(code, 1)
        self.assertIn('a Rust package name starts with a letter: 9lives', err)
        self.assertEqual(sorted(p.name for p in self.out.iterdir()), [])
        code, out, err = self.cli('--help')
        self.assertEqual(code, 0)
        self.assertIn(usage, out)
        self.assertIn('RHUN_NEW_EXT_BASE', out)

    def test_yes_takes_the_owner_from_git_and_rust(self):
        (self.home / '.gitconfig').write_text('[user]\n\tname = Someone\n[github]\n\tuser = git-octo\n',
                                              encoding='utf-8')
        code, out, err = self.cli('--yes', '--name', 'from-git')
        self.assertEqual(code, 0, err)
        d = self.out / 'from-git'
        self.assertIn('owner = git-octo\n', self.read(d, 'extension.ini'))
        self.assertTrue((d / 'Cargo.toml').exists())
        self.assertTrue((d / '.agents/skills/rhun-extension/SKILL.md').exists())
        # the current folder by itself: its name
        here = self.out / 'here-ext'
        here.mkdir()
        r = subprocess.run([str(EXE), 'new-extension', '.', '--yes'], cwd=here, env=self.env(),
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('name = here-ext\n', self.read(here, 'extension.ini'))


def add_dotdot_skills(tar):
    body = b'outside\n'
    info = tarfile.TarInfo('skills-main/../../outside.txt')
    info.size = len(body)
    tar.addfile(info, io.BytesIO(body))


@unittest.skipIf(WINDOWS, 'a pty is POSIX')
class Terminal(Base):
    def start(self, *args):
        import pty
        import termios
        master, slave = pty.openpty()
        self.before = termios.tcgetattr(slave)
        proc = subprocess.Popen([str(EXE), 'new-extension', *args], cwd=self.out, env=self.env(TERM='xterm'),
                                stdin=slave, stdout=slave, stderr=slave, close_fds=True)
        self.slave = slave
        self.buf = b''
        return master, proc

    def expect(self, master, text, timeout=20):
        import select
        end = time.time() + timeout
        while text.encode() not in self.buf:
            left = end - time.time()
            if left <= 0:
                self.fail('no %r in %r' % (text, self.buf[-600:]))
            ready, _, _ = select.select([master], [], [], left)
            if ready:
                try:
                    self.buf += os.read(master, 4096)
                except OSError:
                    break
        i = self.buf.index(text.encode()) + len(text)
        self.buf = self.buf[i:]

    def finish(self, master, proc):
        import termios
        rest = b''
        import select
        end = time.time() + 60
        while proc.poll() is None and time.time() < end:
            ready, _, _ = select.select([master], [], [], 0.2)
            if ready:
                try:
                    rest += os.read(master, 4096)
                except OSError:
                    break
        proc.wait(timeout=10)
        after = termios.tcgetattr(self.slave)
        # PENDIN is the kernel's own (set when input waits as canonical mode comes back)
        pendin = getattr(termios, 'PENDIN', 0)
        after[3] &= ~pendin
        self.before[3] &= ~pendin
        os.close(self.slave)
        os.close(master)
        return proc.returncode, self.buf + rest, after

    def test_the_questions_in_a_terminal(self):
        (self.home / '.gitconfig').write_text('[github]\n\tuser = git-octo\n', encoding='utf-8')
        master, proc = self.start('pty-ext')
        self.expect(master, 'Name: pty-ext')           # DIR's name, to keep or edit
        os.write(master, b'\x7f\x7fxt\r')              # Backspace twice, then "xt": the same name
        self.expect(master, 'Owner (GitHub user or organization): git-octo')
        os.write(master, b'\x7f' * 9 + b'Bad Owner')     # the space is typed, refused at Enter
        os.write(master, b'\r')
        self.expect(master, 'the owner is a GitHub user or organization')
        self.expect(master, 'Owner (GitHub user or organization): Bad Owner')
        os.write(master, b'\x7f' * 9 + b'octo\r')
        self.expect(master, 'Language:')
        self.expect(master, '> Rust')                  # Rust marked first
        os.write(master, b'\x1b[B')                     # Down: Go
        time.sleep(0.2)
        os.write(master, b'\r')
        self.expect(master, 'Language: Go')
        self.expect(master, 'Agent skills for Claude Code and Codex:')
        os.write(master, b'2')                          # a digit takes it at once: No
        self.expect(master, 'Agent skills for Claude Code and Codex: No')
        code, out, after = self.finish(master, proc)
        self.assertEqual(code, 0, out)
        self.assertEqual(after, self.before)
        d = self.out / 'pty-ext'
        ini = self.read(d, 'extension.ini')
        self.assertIn('name = pty-ext\n', ini)
        self.assertIn('owner = octo\n', ini)
        self.assertTrue((d / 'go.mod').exists())
        self.assertFalse((d / '.agents').exists())
        self.assertIn(b'Created octo/pty-ext (Go)', out)

    def test_flags_skip_their_questions_and_enter_takes_the_defaults(self):
        master, proc = self.start('--name', 'flagged', '--owner', 'octo')
        self.expect(master, 'Language:')
        os.write(master, b'\r')
        self.expect(master, 'Language: Rust')
        os.write(master, b'\r')
        self.expect(master, 'Agent skills for Claude Code and Codex: Yes')
        code, out, after = self.finish(master, proc)
        self.assertEqual(code, 0, out)
        self.assertNotIn(b'Name:', out)
        self.assertTrue((self.out / 'flagged/Cargo.toml').exists())
        self.assertTrue((self.out / 'flagged/.agents/skills/rhun-extension/SKILL.md').exists())

    def test_ctrl_c_puts_the_terminal_back(self):
        master, proc = self.start()
        self.expect(master, 'Name: ')
        os.write(master, b'abc\x03')
        code, out, after = self.finish(master, proc)
        self.assertEqual(code, 130)
        self.assertEqual(after, self.before)
        self.assertEqual(list(self.out.iterdir()), [])


class Gui(Base):
    def ui(self, lines, timeout=180):
        project = self.work / 'project'
        project.mkdir(exist_ok=True)
        script = self.work / 'script.txt'
        script.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        r = subprocess.run([str(EXE), str(project), '--headless', '1200x800', '--scale', '1', '--script',
                            str(script)], env=self.env(), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=timeout)
        return r.stdout.decode('utf-8', 'replace').splitlines()

    def head(self, out):
        return [l for l in out if l.startswith('quick ')]

    def steps(self):
        return ['cmd new_extension', 'wait 100', 'print-quick', 'type gui-ext', 'key Return', 'wait 100',
                'print-quick', 'type octo', 'key Return', 'wait 100', 'print-quick', 'key Down', 'key Return',
                'wait 100', 'print-quick', 'key Return', 'wait 100', 'print-quick']

    def test_the_steps_the_job_and_the_buttons(self):
        out = self.ui(self.steps() + ['key Return', 'wait-new-extension', 'print-notes', 'print-quick'])
        heads = self.head(out)
        self.assertIn(' title=New Extension step=1/5 mode=input ', heads[0])
        self.assertIn(' prompt=Name: lowercase letters', heads[0])
        self.assertIn(' step=2/5 mode=input ', heads[1])
        self.assertIn(' step=3/5 mode=pick ', heads[2])
        self.assertIn(' step=4/5 mode=pick ', heads[3])
        self.assertIn(' step=5/5 mode=input ', heads[4])
        home = self.home.as_posix() if not WINDOWS else str(self.home)
        self.assertTrue(heads[4].endswith(' field=' + home + '/code/gui-ext'), heads[4])
        rows = [l for l in out if l.startswith('row ')]
        self.assertTrue(any(' id=rust label=Rust' in r and ' active' in r for r in rows), rows)
        self.assertTrue(any(' id=go label=Go' in r for r in rows), rows)
        self.assertTrue(any(' id=yes label=Yes' in r for r in rows), rows)
        self.assertIn('new-extension=done', out)
        d = self.home / 'code/gui-ext'
        self.assertIn('owner = octo\n', self.read(d, 'extension.ini'))
        self.assertTrue((d / 'go.mod').exists())
        self.assertTrue((d / '.agents/skills/rhun-extension/SKILL.md').exists())
        note = [l for l in out if 'Created octo/gui-ext in ' in l]
        self.assertTrue(note, out)
        for button in ('Open Folder', 'New Window', 'Dev Install'):
            self.assertIn(button, note[0])
        self.assertEqual(out[-1], 'quick none')
        self.assertEqual(self.leftovers(self.home / 'code'), [])

    def test_a_wrong_name_shows_under_the_field_and_back_returns(self):
        out = self.ui(['cmd new_extension', 'wait 100', 'type Bad Name', 'key Return', 'wait 100', 'print-quick',
                       'key ctrl+a', 'key BackSpace', 'type good', 'key Return', 'wait 100', 'print-quick',
                       'key alt+Left', 'wait 100', 'print-quick', 'key Escape', 'wait 100', 'print-quick',
                       'wait-new-extension'])
        heads = self.head(out)
        self.assertIn(' msg=error:the name is lowercase letters, digits and dashes', heads[0])
        self.assertIn(' step=2/5 ', heads[1])
        self.assertIn(' step=1/5 ', heads[2])
        self.assertTrue(heads[2].endswith(' field=good'), heads[2])
        self.assertIn('quick none', out)
        self.assertIn('new-extension=idle', out)

    def test_a_folder_that_is_not_empty_is_refused_at_its_step(self):
        full = self.home / 'code/gui-ext'
        full.mkdir(parents=True)
        (full / 'x').write_text('x', encoding='utf-8')
        out = self.ui(self.steps() + ['key Return', 'wait 100', 'print-quick'])
        self.assertIn(' msg=error:that folder is not empty', self.head(out)[-1])

    def test_dev_install_links_the_folder(self):
        out = self.ui(self.steps() + ['key Return', 'wait-new-extension', 'note-press 0 3', 'wait-install',
                                      'print-dialog'])
        d = self.home / 'code/gui-ext'
        self.assertIn('install=asking', out)
        self.assertTrue(any(l.startswith('text=Version 0.1.0, linked to the folder ' + d.as_posix()) for l in out),
                        out)

    def test_a_failure_is_a_notification(self):
        shutil.rmtree(self.base / 'rhun-editor/template-go')
        out = self.ui(self.steps() + ['key Return', 'wait-new-extension', 'print-notes'])
        self.assertIn('new-extension=failed', out)
        self.assertTrue(any('Could not create octo/gui-ext: could not download the Go template' in l for l in out),
                        out)
        self.assertFalse((self.home / 'code/gui-ext').exists())
        self.assertEqual(self.leftovers(self.home / 'code'), [])

    @unittest.skipIf(WINDOWS, 'a FIFO holds the download open')
    def test_cancel_stops_the_job_and_cleans_up(self):
        path = self.publish('template-go', None, data=b'')
        path.unlink()
        os.mkfifo(path)                                 # curl waits on it until Cancel
        out = self.ui(self.steps() + ['key Return', 'wait 900', 'print-notes', 'note-press 0 cancel',
                                      'wait-new-extension', 'print-notes'])
        self.assertTrue(any('New extension octo/gui-ext' in l for l in out), out)
        self.assertIn('new-extension=cancelled', out)
        self.assertTrue(any('Cancelled the new extension' in l for l in out), out)
        self.assertFalse((self.home / 'code/gui-ext').exists())
        self.assertEqual(self.leftovers(self.home / 'code'), [])


@unittest.skipUnless(all((TEMPLATES / r / '.git').exists() for r in ('template-go', 'template-rust', 'skills')),
                     'the template repositories are not at RHUN_TEMPLATES')
class RealTemplates(Base):
    """The real templates' archives (their origin/main, else main): the result builds."""
    def setUp(self):
        super().setUp()
        for repo in ('template-go', 'template-rust', 'skills'):
            ref = 'origin/main'
            if subprocess.run(['git', '-C', str(TEMPLATES / repo), 'rev-parse', '-q', '--verify', ref],
                              capture_output=True).returncode:
                ref = 'main'
            data = subprocess.run(['git', '-C', str(TEMPLATES / repo), 'archive', '--format=tar.gz',
                                   '--prefix=%s-main/' % repo, ref], capture_output=True, check=True).stdout
            self.publish(repo, None, data=data)

    def build_env(self):
        env = dict(os.environ)
        env.pop('GOWORK', None)
        env.update(GOWORK='off', GOFLAGS='-mod=mod', GOPROXY='off', CARGO_NET_OFFLINE='true')
        return env

    def test_go_builds(self):
        if not shutil.which('go'):
            self.skipTest('no go')
        code, out, err = self.cli('real-go', '--owner', 'octo', '--lang', 'go')
        self.assertEqual(code, 0, err)
        d = self.out / 'real-go'
        self.assertIn('module github.com/octo/real-go', self.read(d, 'go.mod'))
        self.assertIn('owner=octo\\/real-go', self.read(d, 'tests/run.sh'))
        r = subprocess.run(['go', 'build', '-o', 'bin/real-go', '.'], cwd=d, env=self.build_env(),
                           capture_output=True, timeout=300)
        if r.returncode and b'module lookup disabled' in r.stderr:
            self.skipTest('the SDK module is not in the Go module cache')
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_rust_builds(self):
        if not shutil.which('cargo'):
            self.skipTest('no cargo')
        code, out, err = self.cli('real-rust', '--owner', 'octo', '--lang', 'rust')
        self.assertEqual(code, 0, err)
        d = self.out / 'real-rust'
        r = subprocess.run(['cargo', 'build', '--quiet'], cwd=d, env=self.build_env(), capture_output=True,
                           timeout=600)
        if r.returncode and (b'offline' in r.stderr or b'failed to download' in r.stderr):
            self.skipTest('the SDK crate is not in the cargo cache')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((d / 'target/debug' / ('real-rust.exe' if WINDOWS else 'real-rust')).exists())


if __name__ == '__main__':
    unittest.main()
