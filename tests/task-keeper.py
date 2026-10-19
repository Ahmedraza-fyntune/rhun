#!/usr/bin/env python3
"""Execute the native process-keeper fixture and reject malformed early-helper arguments."""
import argparse
import importlib.util
import os
import select
import signal
import re
import tempfile
import struct
import time
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]



class PosixKeeper:
    """Exercise the actual early helper with owned control, status and capture pipes."""
    nonce = 37

    def __init__(self, executable):
        import fcntl
        control_read, self.control = os.pipe()
        self.status, status_write = os.pipe()
        self.output, output_write = os.pipe()
        null = os.open('/dev/null', os.O_RDWR)
        os.set_blocking(control_read, False)
        os.set_blocking(status_write, False)
        sources = [fcntl.fcntl(fd, fcntl.F_DUPFD_CLOEXEC, 64)
                   for fd in (control_read, status_write, null, null, output_write, output_write)]
        actions = [(os.POSIX_SPAWN_DUP2, fd, index) for index, fd in enumerate(sources)]
        actions += [(os.POSIX_SPAWN_CLOSE, fd) for fd in
                    (*sources, control_read, self.control, self.status, status_write,
                     self.output, output_write, null) if fd >= 6]
        self.pid = os.posix_spawn(str(executable), [str(executable), '--process-keeper', 'v1', str(self.nonce)],
                                  {'PATH': '/usr/bin:/bin'}, file_actions=actions)
        for fd in (*sources, control_read, status_write, output_write, null):
            os.close(fd)
        os.set_blocking(self.status, False)
        os.set_blocking(self.output, False)
        self.received = bytearray()
        self.captured = bytearray()
        self.frames = []
        self.info = (0, 0, 0)
        self.collected = False

    def send(self, kind, body=b''):
        frame = struct.pack('<8sQII', b'RHKPCTL1', self.nonce, kind, len(body)) + body
        if os.write(self.control, frame) != len(frame):
            raise AssertionError('short helper control write')

    def initialize(self, command, executable='/bin/sh'):
        argv = [executable.encode() + b'\0', b'-c\0', command.encode() + b'\0']
        body = struct.pack('<IIIII12x', 2, len(argv), 0, 1, 0) + b'/\0'
        body += b''.join(struct.pack('<I', len(arg)) + arg for arg in argv)
        self.send(1, body)

    def drain(self):
        for fd, destination in ((self.status, self.received), (self.output, self.captured)):
            for _ in range(16):
                try:
                    block = os.read(fd, 65536)
                except BlockingIOError:
                    break
                if not block:
                    break
                destination.extend(block)
        while len(self.received) >= 64:
            frame = bytes(self.received[:64])
            del self.received[:64]
            if frame[:8] != b'RHKPSTA1' or struct.unpack_from('<Q', frame, 8)[0] != self.nonce:
                raise AssertionError('invalid helper status header')
            flags, error, exit_code, raw, target = struct.unpack_from('<IiiIQ', frame, 16)
            if self.frames and flags | self.frames[-1][0] != flags:
                raise AssertionError('helper status flags regressed')
            self.info = struct.unpack_from('<IIQ', frame, 40)
            if frame[56:] != bytes(8):
                raise AssertionError('nonzero status reserved bytes')
            self.frames.append((flags, error, exit_code, raw, target))

    def wait(self, predicate, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.drain()
            if self.frames and predicate(self.frames[-1]):
                return self.frames[-1]
            time.sleep(.005)
        raise AssertionError(f'helper status deadline: {self.frames!r}')

    def stop(self):
        if self.control is not None:
            os.close(self.control)
            self.control = None

    def finish(self, timeout=5):
        frame = self.wait(lambda status: status[0] & 4, timeout)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.collected = True
                self.drain()
                if os.waitstatus_to_exitcode(status):
                    raise AssertionError(f'helper exited abnormally: {status}')
                if self.received:
                    raise AssertionError('partial final status')
                return frame
            time.sleep(.005)
        raise AssertionError('helper did not collect after DONE')

    def close(self):
        self.stop()
        if not self.collected:
            try:
                os.kill(self.pid, signal.SIGCONT)
                self.finish()
            except (AssertionError, ProcessLookupError):
                try:
                    os.kill(self.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                os.waitpid(self.pid, 0)
        os.close(self.status)
        os.close(self.output)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def posix_lifecycle(executable, deadlines):
    # Closing the unopened gate cannot execute even a valid target.
    with PosixKeeper(executable) as keeper:
        keeper.initialize('printf should-not-execute')
        keeper.wait(lambda status: status[0] & 1)
        keeper.stop()
        keeper.finish()
        if keeper.captured:
            raise AssertionError('closed gate executed target')

    # Exec errno must survive a fast leader exit before setup-pipe consumption.
    with PosixKeeper(executable) as keeper:
        keeper.initialize('exit 0', '/nonexistent/rhun-keeper-test')
        keeper.wait(lambda status: status[0] & 1)
        keeper.send(2)
        result = keeper.finish()
        if not result[0] & 8 or result[1] != -2:
            raise AssertionError(f'exec failure lost: {result!r}')

    # Leader exit alone cannot end a protected group with a live, TERM-ignoring child.
    with PosixKeeper(executable) as keeper:
        keeper.initialize("trap 'exit 23' USR1; (trap '' TERM; printf descendant; kill -USR1 \"$$\"; while :; do sleep 1; done) & wait")
        keeper.wait(lambda status: status[0] & 1)
        keeper.send(2)
        result = keeper.finish()
        if result[0] & 8 or result[2] != 23 or not result[0] & 32 or keeper.captured != b'descendant':
            raise AssertionError(f'group cleanup failed: {result!r}')
        try:
            os.killpg(result[4], 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError('DONE left protected group present')

    # A buffered START followed by observable control EOF cannot open the gate.
    with PosixKeeper(executable) as keeper:
        keeper.initialize('printf should-not-execute')
        keeper.wait(lambda status: status[0] & 1)
        os.kill(keeper.pid, signal.SIGSTOP)
        os.waitpid(keeper.pid, os.WUNTRACED)
        keeper.send(2)
        keeper.stop()
        os.kill(keeper.pid, signal.SIGCONT)
        keeper.finish()
        if keeper.captured or any(frame[0] & 2 for frame in keeper.frames):
            raise AssertionError('buffered START opened gate after control EOF')

    if deadlines:
        # Watch the real Darwin process for fork, so premature target creation is observable.
        with PosixKeeper(executable) as keeper:
            keeper.wait(lambda status: status[0] == 0)
            tracker = select.kqueue() if hasattr(select, 'kqueue') else None
            if tracker:
                tracker.control([select.kevent(keeper.pid, filter=select.KQ_FILTER_PROC,
                                flags=select.KQ_EV_ADD, fflags=select.KQ_NOTE_FORK)], 0, 0)
            try:
                os.kill(keeper.pid, signal.SIGSTOP)
                os.waitpid(keeper.pid, os.WUNTRACED)
                keeper.initialize('exit 0')
                time.sleep(10.2)
                os.kill(keeper.pid, signal.SIGCONT)
                result = keeper.finish()
                if result[1] != -110 or not result[0] & 8:
                    raise AssertionError(f'expired initialization lost failure: {result!r}')
                if tracker and any(event.fflags & select.KQ_NOTE_FORK for event in tracker.control(None, 8, 0)):
                    raise AssertionError('expired buffered INIT created a target')
            finally:
                if tracker:
                    tracker.close()
    print('ok   task-keeper closed gate, exec failure, descendant cleanup and control EOF', flush=True)




def extension_init(keeper, root, payload, state, home, command, *, kind=2, identifier=None,
                   expected=None, needs=16, runs='', program='/bin/cat'):
    strings = [str(root), 'owner', 'name', str(payload), str(state), program, '', runs,
               '', str(home), '']
    auth = bytearray(320)
    struct.pack_into('<QIIIIQ', auth, 0, 0x315455414b485252, 1, kind, needs, 1, 1)
    if expected is not None:
        auth[32:192] = expected
    if identifier is not None:
        auth[192:256] = identifier.encode()
    for index, value in enumerate(strings):
        value = value.encode() + b'\0'
        struct.pack_into('<I', auth, 276 + index * 4, len(value))
        auth.extend(value)
    argv = [program.encode() + b'\0', *(value.encode() + b'\0' for value in command)]
    environment = [b'PATH=/usr/bin:/bin\0', ('HOME=' + str(state)).encode() + b'\0']
    body = struct.pack('<IIIII12x', len(str(payload).encode()) + 1, len(argv), len(auth), 2,
                       len(environment)) + str(payload).encode() + b'\0'
    body += b''.join(struct.pack('<I', len(value)) + value for value in argv + environment) + auth
    keeper.send(1, body)


def selection_record(generation, identifier):
    return struct.pack('<8sIIQQ64s64s', b'RHEXIDX\0', 1, 1, generation, 0,
                       identifier.encode(), bytes(64))


def posix_extension_lifecycle(executable):
    import fcntl
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-auth-') as temporary:
        base = Path(temporary).resolve()
        root = base / 'store'
        payload = root / 'owner/name'
        payload.mkdir(parents=True)
        (root / '.change.lock').touch()
        lease = root / '.leases/legacy' / b'owner'.hex() / (b'name'.hex() + '.lock')
        lease.parent.mkdir(parents=True)
        lease.touch()
        state = base / 'state'
        state.mkdir()
        home = base / 'actual-home'
        home.mkdir()
        (home / 'approved').write_bytes(b'approved-home')
        denied = base / 'unapproved'
        denied.write_bytes(b'must-not-read')
        with PosixKeeper(executable) as keeper:
            extension_init(keeper, root, payload, state, home, [str(home / 'approved')])
            keeper.wait(lambda status: status[0] & 1)
            actual_confinement = keeper.info[0]
            descriptor = os.open(lease, os.O_RDONLY)
            try:
                try:
                    fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    pass
                else:
                    raise AssertionError('running helper did not hold lifetime lease')
                keeper.send(2, bytes(160) + struct.pack('<Q', 1))
                result = keeper.finish()
                if result[0] & 8 or result[2] or keeper.captured != b'approved-home':
                    raise AssertionError(f'approved host HOME denied: {result!r}, {keeper.captured!r}')
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            finally:
                os.close(descriptor)
        with PosixKeeper(executable) as keeper:
            extension_init(keeper, root, payload, state, home, ['HOME'], program='/usr/bin/printenv')
            keeper.wait(lambda status: status[0] & 1)
            keeper.send(2, bytes(160) + struct.pack('<Q', 1))
            result = keeper.finish()
            if result[2] or keeper.captured != str(state).encode() + b'\n':
                raise AssertionError('target HOME changed while preparing host-home permission')
        if actual_confinement:
            with PosixKeeper(executable) as keeper:
                extension_init(keeper, root, payload, state, home, [str(denied)])
                keeper.wait(lambda status: status[0] & 1)
                keeper.send(2, bytes(160) + struct.pack('<Q', 1))
                result = keeper.finish()
                if result[2] == 0 or b'must-not-read' in keeper.captured:
                    raise AssertionError('native extension sandbox read an unapproved path')
        # Required state I/O errors must fail even when fallback is explicitly allowed.
        with PosixKeeper(executable) as keeper:
            extension_init(keeper, root, payload, base / 'missing-state', home,
                           [str(home / 'approved')])
            result = keeper.finish()
            if not result[0] & 8 or result[1] != -2 or result[0] & 64 or keeper.captured:
                raise AssertionError(f'missing state silently used fallback: {result!r}')
        fifo = payload / 'fifo-runtime'
        os.mkfifo(fifo)
        with PosixKeeper(executable) as keeper:
            extension_init(keeper, root, payload, state, home, [], program=str(fifo))
            result = keeper.finish()
            if not result[0] & 8 or result[1] != -22 or result[0] & 64:
                raise AssertionError(f'FIFO confinement probe created target or lost error: {result!r}')
        # Managed candidate is leased before publication but cannot execute under old selection.
        owner = b'owner'.hex()
        name = b'name'.hex()
        index = root / '.installed' / owner / name
        index.mkdir(parents=True)
        old = selection_record(1, 'a' * 64)
        new = selection_record(2, 'b' * 64)
        (index / '0000000000000001.idx').write_bytes(old)
        candidate = root / '.packages' / owner / name / ('b' * 64)
        managed_payload = candidate / 'payload'
        managed_payload.mkdir(parents=True)
        (candidate / 'lease').touch()
        with PosixKeeper(executable) as keeper:
            extension_init(keeper, root, managed_payload, state, home, [str(home / 'approved')],
                           kind=3, identifier='b' * 64, expected=old)
            keeper.wait(lambda status: status[0] & 1)
            keeper.send(2, new + struct.pack('<Q', 1))
            result = keeper.finish()
            if result[1] != -116 or keeper.captured or result[0] & 2:
                raise AssertionError(f'unpublished candidate executed: {result!r}')
        # A writer holding EX wins before gate authorization. No gate opens until it publishes.
        with PosixKeeper(executable) as keeper:
            extension_init(keeper, root, managed_payload, state, home, [str(home / 'approved')],
                           kind=3, identifier='b' * 64, expected=old)
            keeper.wait(lambda status: status[0] & 1)
            descriptor = os.open(root / '.change.lock', os.O_RDONLY)
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                keeper.send(2, new + struct.pack('<Q', 1))
                time.sleep(.1)
                keeper.drain()
                if keeper.captured or any(frame[0] & (2 | 8) for frame in keeper.frames):
                    raise AssertionError('candidate opened gate or failed while writer held root guard')
                (index / '0000000000000002.idx').write_bytes(new)
                fcntl.flock(descriptor, fcntl.LOCK_UN)
                result = keeper.finish()
                if result[0] & 8 or result[2] or keeper.captured != b'approved-home':
                    raise AssertionError(f'published candidate failed: {result!r}, {keeper.captured!r}')
            finally:
                os.close(descriptor)
    print('ok   extension-keeper lease, sandbox, host HOME, FIFO and publication gates', flush=True)


def build_fault(platform, folder, negative=None):
    """Compile private source copies; shipped supervisor files contain no fault switches."""
    def checked(command):
        result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=120)
        if result.returncode:
            raise AssertionError(f'fault build failed: {(result.stdout + result.stderr)[:4000]!r}')

    if platform == 'windows':
        spec = importlib.util.spec_from_file_location('rhun_windows_builder', ROOT / 'tools/build-windows.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
    owned = {'src/app/taskproc.s', 'src/app/taskhelper.s', 'src/app/taskposix.s',
             'src/app/taskauth.s', 'src/app/taskconfine.s', 'src/app/confine.s',
             'src/mac/taskproc.s', 'src/win/taskproc.s'}
    sources = ['src/app/taskproc.s', 'src/app/taskhelper.s', 'src/app/taskposix.s',
               'src/app/taskauth.s', 'src/app/taskconfine.s', 'tests/task_keeper_test.s']
    sources.append('src/app/confine.s')
    if platform != 'linux':
        sources.append('src/mac/taskproc.s' if platform == 'macos' else 'src/win/taskproc.s')
    objects = []
    for index, relative in enumerate(sources):
        text = (ROOT / relative).read_text()
        if relative == 'src/app/taskproc.s':
            text += '\n.globl kp_slots\n'
            if negative == 'erase-known-exit':
                marker = '    test dword ptr [rbx + KX_flags], KP_EXIT_KNOWN\n    jnz .Lkp_poll_result\n'
                if text.count(marker) != 1:
                    raise AssertionError('known exit negative control no longer matches')
                text = text.replace(marker, '    and dword ptr [rbx + KX_flags], -33\n')
        if relative == 'src/app/taskposix.s' and platform != 'windows':
            if 'SYS SYS_wait4' not in text:
                raise AssertionError('private reap fault no longer matches')
            text = text.replace('SYS SYS_wait4', 'call tkp_fault_wait4')
            if negative == 'lose-interrupted-reap':
                marker = '    cmp rax, -4\n    je .Lkp_target_poll_ok\n    test rax, rax\n    jz .Lkp_target_poll_ok\n'
                if text.count(marker) != 1:
                    raise AssertionError('reap negative control no longer matches')
                text = text.replace(marker, '')
                marker = '.Lkp_target_wait_lost:\n    cmp rax, -4\n    je .Lkp_target_poll_ok\n'
                if text.count(marker) != 1:
                    raise AssertionError('reap-loss negative control no longer matches')
                text = text.replace(marker, '.Lkp_target_wait_lost:\n    mov qword ptr [rbx + KH_reaped], 1\n')
        if relative == 'src/win/taskproc.s':
            marker = 'FN kp_backend_recover\n'
            if text.count(marker) != 1:
                raise AssertionError('private recovery proof no longer matches')
            text = text.replace(marker, marker + '    cmp qword ptr [rdi + KX_no_target], 1\n    jne 991f\n    mov eax, 1\n    ret\n991:\n')
        source = folder / f'keeper-{index}.s'
        obj = source.with_suffix('.obj' if platform == 'windows' else '.o')
        source.write_text(text)
        definitions = ['TEST_KEEPER_FAULT'] if relative.startswith('tests/') else []
        if platform == 'macos':
            if relative.startswith('src/mac/'):
                checked(['as', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-I', ROOT / 'src/mac',
                         '-o', obj, source])
            else:
                translated = source.with_name(source.stem + '-a64.s')
                command = [sys.executable, ROOT / 'tools/arm64.py', '-I', ROOT / 'src', '-D', 'MACOS']
                for definition in definitions:
                    command.extend(('-D', definition))
                checked([*command, source, translated])
                checked(['as', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', obj, translated])
        elif platform == 'windows':
            source.write_text(re.sub(r'(?m)^\.section \.rodata$', '.section .rdata,"dr"', text))
            command = [builder.tool('llvm-mc'), '-triple=x86_64-pc-windows-msvc', '-filetype=obj',
                       '-defsym=WINDOWS=1', '-I', ROOT / 'src', '-I', ROOT / 'src/win']
            checked([*command, *('-defsym=' + d + '=1' for d in definitions), source, '-o', obj])
        else:
            command = ['as', '--64', '-I', ROOT / 'src']
            for definition in definitions:
                command.extend(('--defsym', definition + '=1'))
            checked([*command, '-o', obj, source])
        objects.append(obj)
    excluded = owned | {'src/main.s'}
    if platform != 'linux':
        excluded |= {'src/start.s', 'src/plat/wayland.s', 'src/plat/x11.s', 'src/plat/appearance.s'}
    for source in sorted((ROOT / 'src').rglob('*.s')):
        relative = source.relative_to(ROOT)
        path = relative.as_posix()
        if path in excluded or path.startswith('src/mac/') and platform != 'macos' or path.startswith('src/win/') and platform != 'windows':
            continue
        obj = ROOT / ('build/windows/' + '_'.join(relative.parts) + '.obj' if platform == 'windows'
                      else 'build/obj/' + path.replace('/', '_')[:-2] + '.o')
        if obj.is_file():
            objects.append(obj)
    objects.append(ROOT / ('build/windows/build_windows_assets.s.obj' if platform == 'windows'
                           else 'build/obj/build_assets.o'))
    exe = folder / ('task-keeper-fault.exe' if platform == 'windows' else 'task-keeper-fault')
    if platform == 'macos':
        command = ['clang', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', exe, *objects]
        for framework in ('AppKit', 'QuartzCore', 'IOSurface', 'CoreServices', 'Carbon'):
            command.extend(('-framework', framework))
    elif platform == 'windows':
        libraries = [ROOT / 'build/windows' / (source.stem + '.lib') for source in sorted((ROOT / 'src/win').glob('*.def'))]
        command = [builder.tool('lld-link'), '/nodefaultlib', '/entry:win_start', '/subsystem:console,6.02',
                   '/stack:33554432,33554432', '/dynamicbase', '/nxcompat', '/largeaddressaware',
                   '/out:' + str(exe), *objects, ROOT / 'build/windows/rhun.res', *libraries]
    else:
        command = ['ld', '-static', '-nostdlib', '--no-dynamic-linker', '-z', 'noexecstack', '-o', exe, *objects]
    checked(command)
    return exe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, default=ROOT / 'build/task_keeper_test')
    parser.add_argument('--wine', help='Wine command or wrapper for an x64 PE fixture')
    parser.add_argument('--extensions', action='store_true', help='verify native lease, sandbox and selection-gate bridge')
    parser.add_argument('--negative-controls', action='store_true', help='verify fault assertions reject deliberately regressed private source copies')
    parser.add_argument('--faults', action='store_true', help='build private interrupted-reap and known-exit recovery regressions')
    parser.add_argument('--deadlines', action='store_true', help='include the real ten-second startup expiry regression')
    args = parser.parse_args()
    executable = args.exe.resolve()
    if not executable.is_file():
        parser.error(f'build the native fixture first: {executable}')
    windows = executable.suffix.lower() == '.exe'
    if args.wine:
        command = [args.wine, 'Z:' + str(executable)]
    else:
        command = [str(executable)]
    expected = (ROOT / 'tests/data/task-keeper.expected').read_bytes()
    result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=120)
    if result.returncode or result.stdout + result.stderr != expected:
        raise AssertionError(f'keeper fixture exited {result.returncode}: {(result.stdout + result.stderr)[:4000]!r}')
    suffix = ['1', '1', '1', '1'] if windows else []
    cases = [('v2', '1'), ('v1', '0'), ('v1', '-1'), ('v1', '+1'),
             ('v1', '01'), ('v1', '9223372036854775808'), ('v1', '1x')]
    for version, nonce in cases:
        result = subprocess.run([*command, '--process-keeper', version, nonce, *suffix],
                                cwd=ROOT, capture_output=True, timeout=120)
        if result.returncode != 2 or result.stdout or result.stderr:
            raise AssertionError(f'helper accepted malformed {version} {nonce!r}: {result.returncode}, {(result.stdout + result.stderr)[:4000]!r}')
    print('ok   task-keeper native lifecycle and helper arguments', flush=True)
    if os.name == 'posix' and not args.wine:
        posix_lifecycle(executable, args.deadlines)
        if args.extensions:
            posix_extension_lifecycle(executable)
    if args.faults:
        platform = 'windows' if windows else 'macos' if sys.platform == 'darwin' else 'linux'
        with tempfile.TemporaryDirectory(prefix='rhun-task-keeper-') as temporary:
            fault = build_fault(platform, Path(temporary))
            fault_command = [args.wine, 'Z:' + str(fault)] if args.wine else [str(fault)]
            result = subprocess.run(fault_command, cwd=ROOT, capture_output=True, timeout=120)
            if result.returncode or result.stdout + result.stderr != expected:
                raise AssertionError(f'keeper fault fixture exited {result.returncode}: {(result.stdout + result.stderr)[:4000]!r}')
            print('ok   task-keeper interrupted reap and cumulative exit recovery', flush=True)
        if args.negative_controls:
            controls = ['erase-known-exit']
            if platform == 'macos':
                controls.append('lose-interrupted-reap')
            for control in controls:
                with tempfile.TemporaryDirectory(prefix='rhun-task-keeper-negative-') as temporary:
                    negative = build_fault(platform, Path(temporary), control)
                    command = [args.wine, 'Z:' + str(negative)] if args.wine else [str(negative)]
                    result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=120)
                    rejection = 70 if control == 'erase-known-exit' else 3
                    if result.returncode != rejection:
                        raise AssertionError(f'keeper negative control {control} did not reach its assertion: '
                                             f'{result.returncode}, {(result.stdout + result.stderr)[:4000]!r}')
                    print('ok   task-keeper rejects ' + control, flush=True)


if __name__ == '__main__':
    main()
