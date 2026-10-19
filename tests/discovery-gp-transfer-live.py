#!/usr/bin/env python3
"""Focused successful-L live release proof. This driver never invokes Q."""
import argparse
from pathlib import Path
import importlib.util
import os
import signal
import tempfile
import types

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def retained_close_mutation():
    return ('fixture.s', 'FN ext_root_close\n', '''FN ext_root_close
    cmp qword ptr [rip + xfer_lifetime], 1
    jne 981f
    cmp rdi, [rip + xfer_l_release_raw]
    jne 981f
    inc qword ptr [rip + xfer_l_omitted_close_count]
    xor eax, eax
    mov edx, 1
    ret
981:
''')


def controller_checks(driver):
    """Faithful finite boundary model for exceptional paths, not native proof."""
    killed = 1 if os.name == 'nt' else -signal.SIGKILL

    def run(scenario):
        state = types.SimpleNamespace(probes=0, sends=[], killed=0, collected=0, timeouts=[])

        class Process:
            returncode = None

            def poll(self):
                return self.returncode

            def kill(self):
                state.killed += 1
                self.returncode = 73 if scenario == 'natural73' else killed

        class Exchange:
            def __init__(self, command, **options):
                assert command == ['fixture', 'L', 'native']
                assert options == dict(timeout=60, output_bound=1024, error_bound=4096)
                self.process = Process()
                self.receipts = [b'R', b'V', b'F\x01']
                self.expired = False

            def _remaining(self):
                if self.expired:
                    raise TimeoutError('modeled child deadline')
                return 9.0

            def read(self, count):
                value = self.receipts.pop(0)
                assert len(value) == count
                return value

            def send(self, byte):
                self._remaining()
                state.sends.append(byte)

            def finish(self):
                state.collected += 1
                self._remaining()
                if scenario == 'pump':
                    raise AssertionError('modeled pump failure')
                return (b'extra' if scenario == 'stdout' else b'',
                        b'diagnostic' if scenario == 'stderr' else b'')

            def __enter__(self):
                state.child = self
                return self

            def __exit__(self, *unused):
                if self.process.poll() is None:
                    self.process.kill()
                return False

        def exchange(command, *, timeout, bound):
            assert command == ['fixture', 'P', 'native'] and bound == 1024
            assert 0 < timeout <= 9.0
            state.timeouts.append(timeout)
            state.probes += 1
            if state.probes == 3:
                if scenario == 'deadline':
                    state.child.expired = True
                if scenario == 'earlyexit':
                    state.child.process.returncode = 73
            return (0 if state.probes == 4 else 75), b'', b''

        corpus = types.SimpleNamespace(FixtureExchange=Exchange, exchange=exchange)
        observed = None
        try:
            driver.successful_lifetime(corpus, [], 'fixture', 'native', expected_intercepts=1)
        except driver.LiveReleaseRetained:
            observed = 'retained'
        except (AssertionError, TimeoutError):
            observed = 'generic'
        assert state.sends == [b'G', b'D'], state.sends
        if scenario == 'retained':
            assert observed == 'retained' and state.killed == 1 and state.collected == 1 and state.probes == 4
        else:
            assert observed == 'generic', (scenario, observed)
        print('L controller boundary', scenario, 'PASS', flush=True)

    for scenario in ('retained', 'stderr', 'stdout', 'natural73', 'pump', 'deadline', 'earlyexit'):
        run(scenario)


def run_native(driver, corpus, prefix, exe, control, wine_drive_root):
    if prefix:
        assert wine_drive_root is not None, 'Wine requires private --wine-drive-root'
    for name, program, expected in (('baseline', exe, 0), ('retained-control', control, 1)):
        with tempfile.TemporaryDirectory(prefix='gp-live-release-', dir=wine_drive_root) as directory:
            root = Path(directory).resolve()
            (root / 'lease').touch()
            native = 'C:/' + root.name if prefix else root.as_posix()
            rejected = False
            try:
                driver.successful_lifetime(corpus, prefix, program, native, expected_intercepts=expected)
            except driver.LiveReleaseRetained:
                rejected = True
            assert rejected == bool(expected), (name, rejected)
            print('native successful L', name, 'PASS', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime-root', type=Path)
    parser.add_argument('--windows', action='store_true', default=os.name == 'nt')
    parser.add_argument('--wine', type=Path)
    parser.add_argument('--wine-drive-root', type=Path)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--inspection-data', type=Path)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--prebuilt', type=Path)
    parser.add_argument('--control', type=Path)
    parser.add_argument('--controller-only', action='store_true')
    args = parser.parse_args()
    driver = load('gp_live_driver', ROOT / 'tests/discovery-gp-transfer.py')
    controller_checks(driver)
    if args.controller_only:
        return
    corpus = driver.module('gp_live_corpus', ROOT / 'tests/discovery-gp.py')
    temporary = None
    try:
        if args.prebuilt:
            assert args.control is not None
            exe, control = args.prebuilt, args.control
        else:
            if args.build_only and args.work is None:
                parser.error('--build-only requires --work')
            if args.work is None:
                temporary = tempfile.TemporaryDirectory(prefix='rhun-gp-live-build-')
            work = Path(args.work or temporary.name).resolve()
            if args.inspection_data is None:
                parser.error('focused build requires existing --inspection-data')
            cases, managed_count, _, _, _ = corpus.source_cases()
            products = corpus.decode_images(args.inspection_data.read_bytes(), cases, managed_count)
            builder = driver.module('gp_live_builder', ROOT / 'tests/faults/discovery_gp_transfer_build.py')
            folder = work / 'baseline'
            fixture = driver.fixture_input(corpus, folder, cases[:1], products[:1], managed_count)
            exe = builder.build(folder, fixture, args.windows, args.runtime_root, instrument=True)
            folder = work / 'retained-control'
            fixture = driver.fixture_input(corpus, folder, cases[:1], products[:1], managed_count)
            control = builder.build(folder, fixture, args.windows, args.runtime_root,
                                    instrument=True, mutation=retained_close_mutation())
            print('focused L fixtures BUILT', flush=True)
        if args.build_only:
            return
        run_native(driver, corpus, [args.wine] if args.wine else [], exe, control, args.wine_drive_root)
        print('successful-L live-before-exit proof PASS; Q not executed', flush=True)
    finally:
        if temporary is not None:
            temporary.cleanup()


if __name__ == '__main__':
    main()
