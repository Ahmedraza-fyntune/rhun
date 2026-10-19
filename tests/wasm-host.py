#!/usr/bin/env python3
"""WebAssembly extensions (run.wasm32-wasip1, src/app/extwasm.s and src/wasm): extensions compiled
to wasm32-wasip1 from Rust (tests/wasm/rust, on the rhun-ext crate), Go (tests/wasm/go, on the
rhunext package) and C (tests/wasm/c, on rhunext.h) run in `rhun --wasm-host`, driven headlessly
through real protocol exchanges: commands, toasts, versioned edits, files in the state folder and
the project as [needs] allows them, refused paths outside, clocks, a module that spins, traps or
exits.

The modules are built here when the toolchains are present (rustup's wasm32-wasip1 target and
the SDK checkout, Go, clang with a WASI sysroot), into build/wasm-ext; RHUN_WASM_MODULES names a
folder of prebuilt ones instead (a module runs unchanged on every system: build on one, test on
all). A module that cannot be had is skipped, not passed."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()
SRC = ROOT / 'tests/wasm'
OUT = ROOT / 'build/wasm-ext'
SDK = Path(os.environ.get('RHUN_EXT_SDK', Path.home() / 'tmp/rhun-editor/extension-protocol'))
WASI_SYSROOT = Path(os.environ.get('WASI_SYSROOT', '/opt/homebrew/share/wasi-sysroot'))

CONFIG = ('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')


def sdk_has(path, text):
    """the SDK checkout knows wasm32-wasip1 (an older one would build a module that cannot run)"""
    f = SDK / path
    if not f.exists() or text not in f.read_text(encoding='utf-8'):
        raise OSError('the SDK at %s has no wasm32-wasip1 support (%s); set RHUN_EXT_SDK' % (SDK, path))


def build_rust():
    sdk_has('rust/rhun-ext/src/lib.rs', 'target_os = "wasi"')
    work = OUT / 'rust'
    work.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SRC / 'rust/src', work / 'src', dirs_exist_ok=True)
    toml = (SRC / 'rust/Cargo.toml.in').read_text(encoding='utf-8')
    (work / 'Cargo.toml').write_text(toml.replace('@SDK@', (SDK / 'rust/rhun-ext').as_posix()), encoding='utf-8')
    subprocess.run(['cargo', 'build', '-q', '--release', '--target', 'wasm32-wasip1'], cwd=work, check=True)
    return work / 'target/wasm32-wasip1/release/wasmtest.wasm'


def build_go():
    sdk_has('go/rhunext/stdin_wasip1.go', 'SetNonblock')
    work = OUT / 'go'
    work.mkdir(parents=True, exist_ok=True)
    shutil.copy(SRC / 'go/main.go', work / 'main.go')
    mod = (SRC / 'go/go.mod.in').read_text(encoding='utf-8').replace('@SDK@', SDK.as_posix())
    (work / 'go.mod').write_text(mod, encoding='utf-8')
    env = dict(os.environ, GOOS='wasip1', GOARCH='wasm', GOFLAGS='-mod=mod')
    subprocess.run(['go', 'build', '-o', 'wasmtest-go.wasm', '.'], cwd=work, env=env, check=True,
                   capture_output=True)
    return work / 'wasmtest-go.wasm'


def build_c():
    work = OUT / 'c'
    work.mkdir(parents=True, exist_ok=True)
    clang = shutil.which('clang', path='/opt/homebrew/opt/llvm/bin') or 'clang'
    out = work / 'wasmtest-c.wasm'
    subprocess.run([clang, '--target=wasm32-wasip1', '--sysroot=' + WASI_SYSROOT.as_posix(), '-O2',
                    '-I', (SDK / 'c').as_posix(), (SRC / 'c/main.c').as_posix(), '-o', out.as_posix()],
                   check=True, capture_output=True)
    return out


def module(name, builder):
    """The module's path, built or prebuilt, or None"""
    pre = os.environ.get('RHUN_WASM_MODULES')
    if pre:
        p = Path(pre) / (name + '.wasm')
        return p if p.exists() else None
    try:
        return builder()
    except (OSError, subprocess.CalledProcessError) as e:
        sys.stderr.write('wasm-host: cannot build %s: %s\n' % (name, e))
        return None


MODULES = {}


def get(name, builder):
    if name not in MODULES:
        MODULES[name] = module(name, builder)
    return MODULES[name]


class Wasm(unittest.TestCase):
    NAME = 'wasmtest'
    BUILDER = staticmethod(build_rust)
    MANIFEST = SRC / 'rust/extension.ini'

    def setUp(self):
        self.wasm = get(self.NAME, self.BUILDER)
        if self.wasm is None:
            self.skipTest('no %s module: toolchain missing' % self.NAME)
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-wasm-')
        self.work = Path(self.tmp.name).resolve()
        self.proj = self.work / 'proj'
        self.proj.mkdir()
        (self.proj / 'a.txt').write_text('hello world\n', encoding='utf-8')
        config = self.work / 'config/rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG, encoding='utf-8')
        self.secret = self.work / 'secret.txt'          # in HOME, outside the project
        self.secret.write_text('secret\n', encoding='utf-8')
        self.state = self.work / ('state/rhun/extensions/rhun-tests--%s' % self.NAME)
        self.env = dict(os.environ, HOME=self.work.as_posix(), USERPROFILE=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(),
                        WASMTEST_SECRET=self.secret.as_posix())

    def tearDown(self):
        self.tmp.cleanup()

    def install(self, needs='documents = write', extra='', module=True):
        exts = self.work / 'exts'
        d = exts / 'rhun-tests' / self.NAME
        if d.exists():
            shutil.rmtree(d)
        (d / 'bin').mkdir(parents=True)
        text = self.MANIFEST.read_text(encoding='utf-8').replace('documents = write', needs) + extra
        (d / 'extension.ini').write_text(text, encoding='utf-8')
        if module:
            shutil.copy(self.wasm, d / 'bin' / (self.NAME + '.wasm'))
        return exts

    def run_editor(self, actions, exts, timeout=60):
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join(['wait 100', 'open ' + (self.proj / 'a.txt').as_posix(), *actions, 'quit'])
                          + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', '1000x600', '--scale', '1',
                                 '--extensions', str(exts), '--script', script.as_posix()],
                                env=self.env, capture_output=True, timeout=timeout)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        return [l for l in result.stdout.decode('utf-8', errors='replace').splitlines() if not l.startswith('ext=')]

    def command(self, name, expect, **kw):
        """runs one command; the toast it answers with"""
        out = self.run_editor(['cmd %s.%s' % (self.NAME, name), 'wait-toast ' + expect], self.install(**kw))
        return out[0]

    def log(self):
        return (self.work / ('state/rhun/extensions/rhun-tests--%s.log' % self.NAME)).read_text(encoding='utf-8')

    def ext_line(self, out):
        return [l for l in out if l.startswith('rhun-tests/%s ' % self.NAME)][-1]

    # --- the tests ---

    def test_runs_as_webassembly(self):
        exts = self.install()
        out = self.run_editor(['print-extensions', 'print-wasm', 'cmd %s.hello' % self.NAME, 'wait-toast hello',
                               'print-extensions'], exts)
        self.assertTrue(out[0].startswith('rhun-tests/%s state=idle pid=0 cmds=%s.hello,' % (self.NAME, self.NAME)), out)
        self.assertTrue(out[1].startswith('rhun-tests/%s module=' % self.NAME), out)
        self.assertTrue(out[1].endswith('bin/%s.wasm' % self.NAME), out)
        self.assertEqual(out[2], 'toast=hello from wasm')
        self.assertIn(' state=running ', out[3])
        # held to its permissions by its host on every system, with or without a kernel sandbox
        self.assertTrue(out[3].endswith(' confined=1'), out[3])
        out = self.run_editor(['ext-page %s' % self.NAME, 'print-ext-page'], exts)
        self.assertIn('held=1', out)

    def test_a_versioned_edit(self):
        out = self.run_editor(['cmd %s.upper' % self.NAME, 'wait-toast upper', 'print-doc'], self.install())
        self.assertEqual(out[0], 'toast=upper ok')
        self.assertEqual(out[1], 'HELLO WORLD')

    def test_environment_and_arguments(self):
        self.assertEqual(self.command('env', 'env'), 'toast=env rhun-tests/%s args 1' % self.NAME)

    def test_the_state_folder_is_its_own(self):
        self.assertEqual(self.command('files', 'files'), 'toast=files ok written by wasm 2 16')
        self.assertEqual((self.state / 'sub/moved.txt').read_text(encoding='utf-8'), 'written by wasm\n')

    def test_the_project_as_needs_says(self):
        self.assertEqual(self.command('project', 'project'), 'toast=project read=false write=false')
        self.assertEqual(self.command('project', 'project', needs='documents = write\nproject = read'),
                         'toast=project read=true write=false')
        self.assertFalse((self.proj / 'from-wasm.txt').exists())
        self.assertEqual(self.command('project', 'project', needs='documents = write\nproject = write'),
                         'toast=project read=true write=true')
        self.assertTrue((self.proj / 'from-wasm.txt').exists())

    def test_nothing_outside(self):
        self.assertEqual(self.command('escape', 'escape'), 'toast=escape absolute=false climb=false')
        # home = read opens the home folder (where the secret is), read only (a climbing path that
        # a runtime cleans into the home folder may reach it too: Go cleans paths itself)
        self.assertTrue(self.command('escape', 'escape', needs='documents = write\nhome = read').startswith(
            'toast=escape absolute=true climb='))

    def test_its_own_folder_read_only(self):
        self.assertEqual(self.command('own', 'own'), 'toast=own read=true write=false')

    def test_clocks(self):
        self.assertTrue(self.command('time', 'time').startswith('toast=time true slept=true'))

    def test_a_spinning_module_does_not_hold_the_editor(self):
        exts = self.install()
        t0 = time.monotonic()
        out = self.run_editor(['cmd %s.spin' % self.NAME, 'wait-toast spinning', 'print-state',
                               'cmd %s.hello' % self.NAME, 'wait 300', 'print-extensions'], exts)
        self.assertEqual(out[0], 'toast=spinning')
        self.assertTrue(out[1].startswith('tabs=1'), out)
        self.assertIn(' state=running ', out[2])
        pid = int(out[2].split(' pid=')[1].split()[0])
        self.assertLess(time.monotonic() - t0, 30)
        # quitting stopped it
        for _ in range(50):
            if not alive(pid):
                break
            time.sleep(0.1)
        self.assertFalse(alive(pid), 'the spinning module outlived the editor')

    def test_a_trap_ends_the_program(self):
        # it answers a command first, so the trap is the command's and not a module that could not run
        out = self.run_editor(['cmd %s.hello' % self.NAME, 'wait-toast hello', 'cmd %s.trap' % self.NAME,
                               'wait-ext %s crashed' % self.NAME, 'print-extensions'], self.install())
        self.assertEqual(out[0], 'toast=hello from wasm')
        self.assertIn(' state=crashed reason=exited with status 134 ', self.ext_line(out))
        log = self.log()
        self.assertIn('rhun --wasm-host: trap: unreachable', log)

    def test_exit_status(self):
        out = self.run_editor(['cmd %s.exit' % self.NAME, 'wait-ext %s crashed' % self.NAME, 'print-extensions'],
                              self.install())
        self.assertIn(' reason=exited with status 3 ', self.ext_line(out))

    def test_a_missing_module_is_reported(self):
        out = self.run_editor(['print-extensions'], self.install(module=False))
        self.assertIn('the WebAssembly module named by run.wasm32-wasip1 is missing', out[0])

    def test_an_invalid_module_is_reported(self):
        exts = self.install()
        (exts / 'rhun-tests' / self.NAME / 'bin' / (self.NAME + '.wasm')).write_bytes(b'\0asm\x01\0\0\0\x05')
        out = self.run_editor(['cmd %s.hello' % self.NAME, 'wait-ext %s crashed' % self.NAME, 'print-extensions'],
                              exts)
        self.assertIn(' state=crashed ', self.ext_line(out))
        log = self.log()
        self.assertIn('rhun --wasm-host: the module cannot run: ', log)


class WasmGo(Wasm):
    """the same commands from Go (GOOS=wasip1): one thread, goroutines scheduled around a reader
    parked on standard input by WASI poll_oneoff"""
    NAME = 'wasmtest-go'
    BUILDER = staticmethod(build_go)
    MANIFEST = SRC / 'go/extension.ini'

    def test_goroutines_run_while_the_reader_waits(self):
        self.assertEqual(self.command('tick', 'ticks'), 'toast=ticks 5')

    def test_a_trap_ends_the_program(self):
        # Go's runtime catches the index error and exits with status 2; unwinding, rhunext closes
        # standard output first, and rhun ends a program whose output ended (status 137 when that
        # comes first), as it does a native one
        out = self.run_editor(['cmd %s.hello' % self.NAME, 'wait-toast hello', 'cmd %s.trap' % self.NAME,
                               'wait-ext %s crashed' % self.NAME, 'print-extensions'], self.install())
        self.assertEqual(out[0], 'toast=hello from wasm')
        self.assertRegex(self.ext_line(out), r' state=crashed reason=exited with status (2|137) ')


class WasmC(Wasm):
    """the same commands from C (rhunext.h on wasi-libc: blocking stdio)"""
    NAME = 'wasmtest-c'
    BUILDER = staticmethod(build_c)
    MANIFEST = SRC / 'c/extension.ini'


class Direct(unittest.TestCase):
    """The modules driven through `rhun --wasm-host` alone, as rhun drives them over the pipes:
    where the editor's headless tests cannot run (Windows under Wine: RHUN_WASM_HOST="wine64
    Z:/path/rhun.com", RHUN_WASM_PATH_PREFIX=Z: for the paths the host sees)."""

    def setUp(self):
        host = os.environ.get('RHUN_WASM_HOST')
        self.host = host.split() if host else [str(EXE)]
        self.prefix = os.environ.get('RHUN_WASM_PATH_PREFIX', '')
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-wasm-direct-')
        self.work = Path(self.tmp.name).resolve()

    def tearDown(self):
        self.tmp.cleanup()

    def hp(self, p):
        return self.prefix + p.as_posix()

    def drive(self, name, builder, commands):
        wasm = get(name, builder)
        if wasm is None:
            self.skipTest('no %s module' % name)
        ext = self.work / name
        if ext.exists():
            shutil.rmtree(ext)
        (ext / 'bin').mkdir(parents=True)
        shutil.copy(wasm, ext / 'bin' / (name + '.wasm'))
        (ext / 'extension.ini').write_text('name = %s\n' % name, encoding='utf-8')
        state = self.work / ('state-' + name)
        shutil.rmtree(state, ignore_errors=True)
        state.mkdir()
        secret = self.work / 'secret.txt'
        secret.write_text('secret\n', encoding='utf-8')
        env = dict(os.environ, RHUN_STATE=self.hp(state), RHUN_EXTENSION='rhun-tests/' + name,
                   WASMTEST_SECRET=self.hp(secret))
        p = subprocess.Popen(self.host + ['--wasm-host', '--dir', self.hp(state), '--dir-ro', self.hp(ext),
                                          self.hp(ext / 'bin' / (name + '.wasm'))],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=open(self.work / 'err.txt', 'wb'),
                             env=env)
        out = p.stdout

        def line():
            b = out.readline()
            if not b:
                raise EOFError('the module ended: ' + (self.work / 'err.txt').read_text(errors='replace')[-500:])
            return b.decode().rstrip('\n')
        self.assertEqual(line(), 'hello 1')
        p.stdin.write(b'0 ready -\n')
        toasts = []
        for c in commands:
            p.stdin.write(('0 run %s.%s 7\n' % (name, c)).encode())
            p.stdin.flush()
            while True:
                rid, verb, *fields = line().split(' ')
                if verb == 'toast':
                    toasts.append(out.read(int(fields[-1])).decode())
                    p.stdin.write(('ok %s\n' % rid).encode())
                    p.stdin.flush()
                    break
                p.stdin.write(('error %s unknown\n' % rid).encode())
                p.stdin.flush()
        p.stdin.write(b'0 bye\n')
        p.stdin.close()
        p.wait(timeout=30)
        return toasts

    def check(self, name, builder):
        commands = ['hello', 'env', 'files', 'escape', 'own', 'time']
        toasts = self.drive(name, builder, commands)
        self.assertEqual(toasts[0], 'hello from wasm')
        self.assertEqual(toasts[1], 'env rhun-tests/%s args 1' % name)
        self.assertEqual(toasts[2], 'files ok written by wasm 2 16')
        self.assertEqual(toasts[3], 'escape absolute=false climb=false')
        self.assertEqual(toasts[4], 'own read=true write=false')
        self.assertTrue(toasts[5].startswith('time true slept=true'), toasts[5])

    def test_rust(self):
        self.check('wasmtest', build_rust)

    def test_go(self):
        self.check('wasmtest-go', build_go)
        self.assertEqual(self.drive('wasmtest-go', build_go, ['tick'])[0], 'ticks 5')

    def test_c(self):
        self.check('wasmtest-c', build_c)


def alive(pid):
    if os.name == 'nt':
        import ctypes
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.OpenProcess(0x1000, False, pid)
        if not handle:
            return False
        code = ctypes.c_ulong()
        kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
        kernel32.CloseHandle(handle)
        return code.value == 259
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    # a zombie child of an exited editor is gone for our purposes
    try:
        with open('/proc/%d/stat' % pid) as f:
            return f.read().split(') ')[1][0] != 'Z'
    except OSError:
        return True


if __name__ == '__main__':
    unittest.main()
