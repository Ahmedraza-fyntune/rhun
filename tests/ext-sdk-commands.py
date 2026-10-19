#!/usr/bin/env python3
"""The extension SDKs' protocol 1.1 commands against rhun itself: the same program written with
the Go, C and Rust SDKs (tests/sdk-commands) runs from the palette, a command reference, a key
binding with ARGS and an explorer menu item (FROM and bodies arrive as the SDK's invocation), adds
a status item whose click runs its command reference, moves the cursor with run-command, calls
another extension's callable command, and sets a context key a when clause reads.

The SDK checkout is RHUN_EXT_SDK (default ~/tmp/rhun-editor/extension-protocol); a language whose
toolchain is missing, or an SDK without these features, is skipped."""
import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path

contribhost = __import__('contribhost')
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'tests/sdk-commands'
OUT = ROOT / 'build/sdk-commands'
SDK = Path(os.environ.get('RHUN_EXT_SDK', Path.home() / 'tmp/rhun-editor/extension-protocol'))
CONFIG = ('[ui]\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
MANIFEST = '''name = {name}
owner = {owner}
title = SDK Sample
version = 1
protocol = 1
run.macos-arm64 = {program}
run.linux-x86_64 = {program}
run.windows-x64 = {program}
on = command

[commands]
say = Say
jump = Jump
ask_other = Ask Other
mode = Set Mode
answer = Answer

[command-options]
answer.callable = yes
say.icon = play

[keys]
ctrl+alt+m = mode normal

[menu.explorer]
say.command = say
say.args = picked

[needs]
documents = read

[context]
mode = start
'''
OTHER = '''name = other
owner = bob
title = SDK Sample
version = 1
protocol = 1
run.macos-arm64 = sample
run.linux-x86_64 = sample
run.windows-x64 = sample
on = command

[commands]
answer = Answer

[command-options]
answer.callable = yes
'''


def build_go():
    work = OUT / 'go'
    work.mkdir(parents=True, exist_ok=True)
    shutil.copy(SRC / 'go/main.go', work / 'main.go')
    mod = (SRC / 'go/go.mod.in').read_text(encoding='utf-8').replace('@SDK@', SDK.as_posix())
    (work / 'go.mod').write_text(mod, encoding='utf-8')
    subprocess.run(['go', 'build', '-o', 'sample', '.'], cwd=work, check=True, capture_output=True,
                   env=dict(os.environ, GOFLAGS='-mod=mod'))
    return work / 'sample'


def build_c():
    work = OUT / 'c'
    work.mkdir(parents=True, exist_ok=True)
    out = work / 'sample'
    subprocess.run(['cc', '-std=c99', '-O1', '-I', (SDK / 'c').as_posix(), (SRC / 'c/main.c').as_posix(), '-o',
                    out.as_posix()], check=True, capture_output=True)
    return out


def build_rust():
    work = OUT / 'rust'
    work.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SRC / 'rust/src', work / 'src', dirs_exist_ok=True)
    toml = (SRC / 'rust/Cargo.toml.in').read_text(encoding='utf-8')
    (work / 'Cargo.toml').write_text(toml.replace('@SDK@', (SDK / 'rust/rhun-ext').as_posix()), encoding='utf-8')
    env = dict(os.environ)
    cargo = Path(shutil.which('cargo')).resolve()
    if 'RUSTUP_HOME' not in env and cargo.parent.name == 'bin' and cargo.parent.parent.name == '.cargo':
        # a test's own HOME hides rustup's toolchains
        env.setdefault('CARGO_HOME', cargo.parent.parent.as_posix())
        env['RUSTUP_HOME'] = (cargo.parent.parent.parent / '.rustup').as_posix()
    subprocess.run(['cargo', 'build', '-q', '--offline'], cwd=work, check=True, capture_output=True, env=env)
    return work / 'target/debug/sdkcommands'


BUILDERS = {'go': (build_go, 'go', SDK / 'go/rhunext/invoke.go'),
            'c': (build_c, 'cc', SDK / 'c/rhunext.h'),
            'rust': (build_rust, 'cargo', SDK / 'rust/rhun-ext/src/commands.rs')}
PROGRAMS = {}


def program(lang):
    """The sample built with that SDK, or None (no toolchain, or an SDK without the features)."""
    if lang not in PROGRAMS:
        build, tool, marker = BUILDERS[lang]
        ok = shutil.which(tool) and marker.exists()
        if ok and lang == 'c':
            ok = 'rx_run_command' in marker.read_text(encoding='utf-8')
        try:
            PROGRAMS[lang] = build() if ok else None
        except (OSError, subprocess.CalledProcessError) as e:
            print(f'{lang}: build failed: {getattr(e, "stderr", b"").decode(errors="replace")[:2000]}')
            PROGRAMS[lang] = None
    return PROGRAMS[lang]


class SdkCommands(contribhost.Contrib):
    def setUp(self):
        super().setUp()
        (self.work / 'config/rhun/config').write_text(CONFIG, encoding='utf-8')

    def exts(self, prog):
        root = self.work / 'exts'
        for owner, name, manifest in (('alice', 'sample', MANIFEST), ('bob', 'other', OTHER)):
            folder = root / owner / name
            folder.mkdir(parents=True, exist_ok=True)
            shutil.copy(prog, folder / 'sample')
            (folder / 'extension.ini').write_text(manifest.format(owner=owner, name=name, program='sample'),
                                                  encoding='utf-8')
        return root

    def ext_log(self, owner='alice', name='sample'):
        path = self.work / f'state/rhun/extensions/{owner}--{name}.log'
        lines = path.read_text(encoding='utf-8', errors='replace').splitlines() if path.exists() else []
        return [l for l in lines if re.match(r'(status|context|invoke|goto_line|call|mode) ', l)]

    def each(self, check):
        """check(lang, exts) for every SDK that builds, each a subtest with fresh logs."""
        built = 0
        for lang in BUILDERS:
            prog = program(lang)
            if prog is None:
                continue
            built += 1
            with self.subTest(sdk=lang):
                for p in (self.work / 'state').glob('rhun/extensions/*.log'):
                    p.unlink()
                check(lang, self.exts(prog))
        if not built:
            self.skipTest('no SDK with protocol 1.1 commands could be built')

    def test_palette_reference_key_and_menu_invocations(self):
        a = (self.proj / 'a.txt').as_posix()
        def check(lang, exts):
            self.run_editor(exts=exts, files=('a.txt',), drop_waits=True, actions=[
                'cmd sample.say', 'wait-ext sample running', 'wait 300',
                'cmd-args sample.say a reference', 'wait 300',
                'click 500 300', 'key ctrl+alt+m', 'wait 300',
                'click 50 94 right', 'menu-pick Say', 'wait 300'])     # a.txt, the explorer's first row
            log = self.ext_log()
            self.assertEqual(log[:2], ['status ok', 'context ok'], (lang, log))
            self.assertIn('invoke say doc=1 from=palette body=', log)
            self.assertIn('invoke say doc=1 from=ref body=a reference', log)
            self.assertIn('invoke mode doc=1 from=key body=normal', log)
            self.assertIn('mode normal ok', log)
            self.assertIn(f'invoke say doc=1 from=menu target=file path={a} args=picked', log)
        self.each(check)

    def test_status_item_click_runs_its_reference(self):
        def check(lang, exts):
            out = self.run_editor(exts=exts, files=('a.txt',), drop_waits=True, actions=[
                'cmd sample.say', 'wait-ext sample running', 'wait 300', 'print-status'])
            line = [l for l in out if ' item=go ' in l]
            self.assertTrue(line and 'owner=alice/sample' in line[0] and 'text=$(play) Sample' in line[0]
                            and 'command=say' in line[0], (lang, out))
            x, y, w, h = map(int, line[0].rsplit('at=', 1)[1].split(','))
            self.run_editor(exts=exts, files=('a.txt',), drop_waits=True, actions=[
                'cmd sample.say', 'wait-ext sample running', 'wait 300', f'click {x + w // 2} {y + h // 2}', 'wait 300'])
            self.assertIn('invoke say doc=1 from=ref body=from the status bar', self.ext_log())
        self.each(check)

    def test_run_command_call_and_context(self):
        def check(lang, exts):
            out = self.run_editor(exts=exts, files=('a.txt',), drop_waits=True, actions=[
                'when alice/sample.mode == start',
                'cmd sample.jump', 'wait-ext sample running', 'wait 300', 'print-state',
                'when alice/sample.mode == ready',
                'cmd sample.ask_other', 'wait-ext other running', 'wait 500',
                'cmd-args sample.mode insert', 'wait 300', 'when alice/sample.mode == insert',
                'ext-set sample stop', 'wait-ext sample stopped', 'when alice/sample.mode == start'])
            log = self.ext_log()
            self.assertIn('goto_line ok', log, (lang, log))
            self.assertIn('call result=answer to question ok', log)
            self.assertIn('call answer from alice/sample args=question', self.ext_log('bob', 'other'))
            self.assertIn('mode insert ok', log)
            whens = [l for l in out if l.startswith('when=')]
            self.assertEqual(whens, ['when=1'] * 4, (lang, out))
            self.assertTrue(any('line=2 col=1' in l for l in out), (lang, out))
        self.each(check)


if __name__ == '__main__':
    unittest.main()
