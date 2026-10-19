#!/usr/bin/env python3
"""Native Windows test gate. --wine runs the compatible subset on Linux for development."""
import argparse
import ctypes
from ctypes import wintypes
import os
import json
from pathlib import Path
import re
import shutil
import subprocess
import struct
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--wine', metavar='WINE64')
parser.add_argument('--metadata-prebuilt', type=Path, help='complete prebuilt metadata matrix artifact')
parser.add_argument('--catalog-prebuilt', type=Path, help='complete prebuilt registry matrix artifact')
args = parser.parse_args()
if os.name != 'nt' and not args.wine:
    parser.error('run on Windows, or supply --wine for the compatibility checks')
runner = [args.wine] if args.wine else []
OUT = ROOT / 'build/windows'
failures = []


def winpath(path):
    value = os.path.abspath(path).replace('\\', '/')
    return 'Z:' + value if args.wine else value


def command(exe, *arguments):
    return [*runner, str(OUT / exe), *map(str, arguments)]


def run(exe, *arguments, env=None, success=True, timeout=30):
    result = subprocess.run(command(exe, *arguments), stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, env=env, timeout=timeout)
    if success and result.returncode:
        raise AssertionError(f'{exe} exited {result.returncode}: {result.stdout.decode(errors="replace")}')
    return result


def check(name, fn):
    try:
        fn()
        print('ok   ' + name, flush=True)
    except Exception as error:
        failures.append(name)
        print(f'FAIL {name}: {error}', flush=True)


def equal(actual, expected):
    if actual != expected:
        raise AssertionError(f'expected {expected[:500]!r}, got {actual[:500]!r}')


def same_folder(line, folder):
    # print-project's line names the folder; a file opened by itself brings its folder in as the
    # project (the home folder as ~). TEMP can be an 8.3 short path while rhun reports the long one.
    assert line.startswith(b'project='), line
    value = line[len(b'project='):].strip().decode('utf-8')
    assert value and Path(value).expanduser().resolve() == Path(folder).resolve(), (value, folder)


with tempfile.TemporaryDirectory(prefix='rhun-windows-', dir=OUT) as temporary:
    temp = Path(temporary)

    def environment(name):
        env = dict(os.environ)
        home = temp / name / 'home'
        home.mkdir(parents=True, exist_ok=True)
        env.update(XDG_CONFIG_HOME=winpath(temp / name / 'config'),
                   XDG_STATE_HOME=winpath(temp / name / 'state'),
                   XCOMPOSEFILE=winpath(ROOT / 'tests/data/compose.txt'),
                   XCURSOR_PATH='tests/data/icons', XCURSOR_THEME='child',
                   WINEDEBUG='-all')
        if not args.wine:
            env['HOME'] = winpath(home)
        return env

    def golden(name, exe, arguments=()):
        env = environment(name)
        if name == 'grammars':
            env['XDG_CONFIG_HOME'] = winpath(ROOT / 'tests/data/config')
        if name == 'config':
            env['XDG_CONFIG_HOME'] = winpath(ROOT / 'tests/data/config-reload')
        if name == 'ext-settings-target':
            env['XDG_CONFIG_HOME'] = winpath(ROOT / 'tests/data/ext-settings-target')
        equal(run(exe + '.exe', *arguments, env=env).stdout,
              (ROOT / 'tests/data' / (name + '.expected')).read_bytes())

    check('installer-unicode', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/installer-unicode.py')], check=True))
    check('ext-settings-target', lambda: golden('ext-settings-target', 'ext_settings_target_test'))
    check('ext-index', lambda: golden('ext-index', 'ext_index_test'))
    check('ext-enqueue', lambda: golden('ext-enqueue', 'ext_enqueue_test'))
    check('ext-settings-queue', lambda: golden('ext-settings-queue', 'ext_settingsqueue_test'))
    check('ext-settings-ack', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-settings-ack.py'), '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-settings-queue-hash', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-settings-queue-hash.py'), '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    for driver in ('ext-enqueue', 'ext-flush', 'ext-settings-queue', 'ext-settings-wire'):
        check(driver, lambda driver=driver: subprocess.run(
            [sys.executable, str(ROOT / ('tests/' + driver + '.py')),
             *(['--faults'] if driver == 'ext-enqueue' else []),
             *(['--wine', args.wine] if args.wine else [])], check=True))
    for driver in ('ext-pending-commands', 'ext-pending-owner', 'ext-runtime-owner'):
        check(driver, lambda driver=driver: subprocess.run(
            [sys.executable, str(ROOT / ('tests/' + driver + '.py')),
             *(['--wine', args.wine] if args.wine else [])], check=True))
    for driver, extra in [('command-generation', []), ('command-generation-owner', ['--negative-controls']),
                          ('command-generation-build', ['--negative-controls']),
                          ('command-generation-defaults', ['--negative-controls']), ('command-generation-defaults', ['--limits']),
                          ('keyline-snapshot', ['--negative-controls']), ('command-key-copy', ['--negative-controls'])]:
        check(driver, lambda driver=driver, extra=extra: subprocess.run(
            [sys.executable, str(ROOT / ('tests/' + driver + '.py')), *extra,
             *(['--wine', args.wine] if args.wine else [])], check=True))
    for driver, extra in [('ext-launch-scratch', ['--negative-controls']),
                          ('ext-launch-scratch', ['--optional-environment', '--negative-controls']),
                          ('ext-launch-scratch-unit', ['--negative-controls']),
                          ('ext-launch-scratch-faults', [])]:
        check(driver + ('-optional' if '--optional-environment' in extra else ''),
              lambda driver=driver, extra=extra: subprocess.run(
                  [sys.executable, str(ROOT / ('tests/' + driver + '.py')), *extra,
                   *(['--wine', args.wine] if args.wine else [])], check=True))
    def metadata_platform_gate():
        command = [sys.executable, str(ROOT / 'tests/metadata-platform-gates.py')]
        wine_arguments = ['--wine', args.wine, '--wine-drive-root',
                          str(Path(os.environ.get('WINEPREFIX', str(Path.home() / '.wine'))) / 'drive_c')] if args.wine else []
        if args.metadata_prebuilt:
            subprocess.run([*command, '--prebuilt', str(args.metadata_prebuilt), *wine_arguments], check=True)
        elif args.wine:
            with tempfile.TemporaryDirectory(prefix='rhun-metadata-platform-') as folder:
                subprocess.run([*command, '--build-only', folder], check=True)
                subprocess.run([*command, '--prebuilt', folder, *wine_arguments], check=True)
        else:
            subprocess.run(command, check=True)
    check('metadata-platform', metadata_platform_gate)
    for driver, artifact, single in [('catalog-foundation-faults', 'foundation', False),
                                     ('catalog-map-faults', 'map', False),
                                     ('catalog-merge-faults', 'merge', False),
                                     ('catalog-limits', 'limits.exe', True),
                                     ('catalog-admission-faults', 'admission', False),
                                     ('catalog-retire', 'retire', False),
                                     ('catalog-capacity', 'capacity', False)]:
        def catalog_gate(driver=driver, artifact=artifact, single=single):
            command = [sys.executable, str(ROOT / ('tests/' + driver + '.py'))]
            wine_arguments = ['--wine', args.wine] if args.wine else []
            if args.catalog_prebuilt:
                subprocess.run([*command, '--exe' if single else '--prebuilt',
                                str(args.catalog_prebuilt / artifact), *wine_arguments], check=True)
            elif args.wine:
                with tempfile.TemporaryDirectory(prefix='rhun-catalog-platform-') as folder:
                    target = Path(folder) / artifact
                    subprocess.run([*command, '--windows', '--build-only', str(target)], check=True)
                    subprocess.run([*command, '--exe' if single else '--prebuilt',
                                    str(target), *wine_arguments], check=True)
            else:
                # Each driver chooses windows=True on native Windows, with no GNU-as path.
                subprocess.run(command, check=True)
        check(driver, catalog_gate)
    check('ext-keeper-host', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-keeper-host.py'),
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('key-combo', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/key-combo.py'), '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-events', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-events.py'), '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('windows-nonblock', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/windows-nonblock.py'),
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('doc-language', lambda: golden('doc-language', 'doc_language_test'))
    check('doc-language-choice', lambda: golden('doc-language-choice', 'doc_language_choice_test'))
    check('file-read-limited', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/file-read-limited.py'),
         '--exe', str(OUT / 'file_read_limited_test.exe'),
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('sha256', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/sha256.py'),
         '--exe', str(OUT / 'sha256_test.exe'),
         *(['--wine', args.wine] if args.wine else [])], check=True))
    rooted_arguments = ['--wine', args.wine, '--wine-drive-root',
                        str(Path(os.environ.get('WINEPREFIX', str(Path.home() / '.wine'))) / 'drive_c')] if args.wine else []
    check('ext-root', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-root.py'), '--exe', str(OUT / 'ext_root_test.exe'),
         *rooted_arguments], check=True))
    check('ext-store', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-store.py'),
         *(['--wine', args.wine] if args.wine else [])], check=True))
    for driver in ('ext-store-read', 'ext-store-guards', 'ext-store-write', 'ext-store-faults', 'ext-store-job', 'ext-store-job-faults', 'ext-store-job-legacy', 'ext-store-job-legacy-real', 'ext-store-job-legacy-faults', 'ext-store-job-legacy-native-faults', 'ext-store-job-legacy-context-faults', 'ext-store-job-legacy-stream-faults', 'ext-discovery', 'ext-discovery-faults', 'native-cleanup', 'native-cleanup-launch', 'native-cleanup-start', 'native-cleanup-unpack-job'):
        check(driver, lambda driver=driver: subprocess.run(
            [sys.executable, str(ROOT / ('tests/' + driver + '.py')), *rooted_arguments], check=True))
    def settings_snapshot_gate():
        command = [sys.executable, str(ROOT / 'tests/ext-settings-snapshot.py')]
        if args.wine:
            fixture = OUT / 'settings-snapshot-gate.exe'
            subprocess.run([*command, '--build-only', '--exe', str(fixture)], check=True)
            command += ['--exe', str(fixture), '--wine', args.wine]
        subprocess.run(command, check=True)
    check('ext-settings-snapshot', settings_snapshot_gate)
    check('ext-settings-request', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-settings-request.py'), '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    for driver in ('ext-settings-service', 'ext-settings-service-source'):
        check(driver, lambda driver=driver: subprocess.run(
            [sys.executable, str(ROOT / ('tests/' + driver + '.py')),
             *(['--wine', args.wine] if args.wine else [])], check=True))
    def settings_service_worker_gate():
        command = [sys.executable, str(ROOT / 'tests/ext-settings-service-worker.py')]
        if not args.wine:
            subprocess.run(command, check=True)
            subprocess.run([*command, '--negative-controls'], check=True)
            return
        drive = Path(os.environ.get('WINEPREFIX', str(Path.home() / '.wine'))) / 'drive_c'
        with tempfile.TemporaryDirectory(prefix='rhun-svc-', dir=drive) as native:
            native = Path(native)
            for mutation in (None, 'finish-cadence', 'read-abort', 'postcommit-retry',
                             'read-close-expiry', 'read-close-eligibility'):
                extra = ['--mutation', mutation] if mutation else []
                name = 'service-worker-' + (mutation or 'baseline') + '.exe'
                fixture = OUT / name
                subprocess.run([*command, *extra, '--build-only', '--exe', str(fixture)], check=True)
                shutil.copyfile(fixture, native / name)
                subprocess.run([*command, *extra, '--exe', 'C:/' + native.name + '/' + name,
                                '--wine', args.wine, '--temp-root', str(native),
                                '--virtual-root', 'C:/' + native.name], check=True)
    check('ext-settings-service-worker', settings_service_worker_gate)
    def settings_adoption_gate(driver, mutations):
        command = [sys.executable, str(ROOT / ('tests/' + driver + '.py'))]
        if not args.wine:
            subprocess.run(command, check=True)
            if mutations:
                subprocess.run([*command, '--negative-controls'], check=True)
            return
        drive = Path(os.environ.get('WINEPREFIX', str(Path.home() / '.wine'))) / 'drive_c'
        with tempfile.TemporaryDirectory(prefix='rhun-sap-', dir=drive) as native:
            native = Path(native)
            for mutation in (None, *mutations):
                extra = ['--mutation', mutation] if mutation else []
                name = driver + '-' + (mutation or 'baseline') + '.exe'
                fixture = OUT / name
                subprocess.run([*command, *extra, '--build-only', '--exe', str(fixture)], check=True)
                shutil.copyfile(fixture, native / name)
                subprocess.run([*command, *extra, '--exe', 'C:/' + native.name + '/' + name,
                                '--wine', args.wine, '--temp-root', str(native),
                                '--virtual-root', 'C:/' + native.name], check=True)
    for driver, mutations in (
        ('ext-settings-service-initial', ('replacement-epoch', 'source-token', 'future-source', 'source-overflow', 'pure-publication')),
        ('ext-settings-adoption-empty', ('ack-missing', 'source-missing', 'ticket-missing', 'gc-one', 'pure-publication', 'ack-newer')),
        ('ext-settings-adoption-unchanged', ('unchanged-epoch', 'source-swap')),
        ('ext-settings-adoption-sparse', ()),
        ('ext-settings-adoption-max', ()),
        ('ext-settings-adoption-service', ('unusable-grant', 'ready-ack', 'cancel-grant', 'stale-bound', 'debt-phase', 'debt-refs')),
        ('ext-settings-adoption-read', ('allocation-sticky', 'serial-atomic', 'retire-first')),
        ('ext-settings-adoption-native', ('oldmodel-release', 'retired-charge', 'early-charge')),
        ('ext-settings-adoption-constructor', ('svc-retain', 'model-retain', 'source-retain', 'source-overflow', 'gc-one')),
    ):
        check(driver, lambda driver=driver, mutations=mutations:
              settings_adoption_gate(driver, mutations))
    check('ext-settings-view', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-settings-view.py'), '--faults', '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-settings-catalog', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-settings-catalog.py'), '--faults', '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-settings-active', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-settings-active.py'), '--faults', '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-settings-editor', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-settings-editor.py'), '--real-metadata', '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-settings-prompt', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-settings-prompt.py'), '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-settings-effective', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-settings-effective.py'), '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-settings-release', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-settings-release.py'), '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-settings-retire', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-settings-retire.py'), '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    for settings_kind in ('job', 'memory', 'receipts', 'faults', 'pipe'):
        def settings_job_gate(kind=settings_kind):
            command = [sys.executable, str(ROOT / 'tests/ext-settings-job.py'), '--kind', kind]
            if args.wine:
                fixture = OUT / ('settings-parent-' + kind + '.exe')
                subprocess.run([*command, '--build-only', '--exe', str(fixture)], check=True)
                drive = Path(os.environ.get('WINEPREFIX', str(Path.home() / '.wine'))) / 'drive_c'
                command += ['--exe', str(fixture), '--wine', args.wine,
                            '--temp-root', str(drive), '--virtual-root', 'C:/']
            subprocess.run(command, check=True)
        check('ext-settings-job-' + settings_kind, settings_job_gate)
    for driver in ('theme-capture', 'theme-capture-build', 'theme-capture-cleanup', 'theme-capture-faults', 'theme-capture-file-cleanup', 'theme-capture-file-faults', 'theme-capture-files', 'theme-capture-job', 'theme-capture-omarchy', 'theme-capture-omarchy-faults', 'theme-capture-omarchy-files', 'theme-capture-proof-faults', 'theme-capture-proof-mutations', 'theme-capture-startup', 'theme-capture-worker'):
        check(driver, lambda driver=driver: subprocess.run(
            [sys.executable, str(ROOT / ('tests/' + driver + '.py')), *rooted_arguments], check=True))
    for driver in ('theme-capture-candidate', 'theme-capture-candidate-purity', 'theme-capture-job-faults', 'theme-capture-job-owners', 'theme-capture-native', 'theme-capture-native-poison', 'theme-capture-result', 'theme-capture-result-decode', 'theme-capture-result-faults', 'theme-capture-startup-faults', 'theme-capture-timeout', 'theme-intent', 'theme-intent-faults', 'theme-intent-migration', 'theme-intent-migration-faults', 'theme-intent-reduce', 'theme-intent-reduce-faults'):
        check(driver, lambda driver=driver: subprocess.run(
            [sys.executable, str(ROOT / ('tests/' + driver + '.py')),
             *(['--wine', args.wine] if args.wine else [])], check=True))
    check('theme-capture-native-negative', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/theme-capture-native-poison.py'), '--negative-control',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    for driver in ('ext-settings-native', 'ext-settings-native-faults'):
        check(driver, lambda driver=driver: subprocess.run(
            [sys.executable, str(ROOT / ('tests/' + driver + '.py')),
             *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-validate', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-validate.py'), '--exe', str(OUT / 'ext_validate_test.exe'),
         '--helper', str(OUT / 'rhun.exe'), '--resource', *rooted_arguments], check=True))
    check('ext-validate-faults', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-validate-faults.py'), *rooted_arguments], check=True))
    check('ext-prepare', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-prepare.py'), '--exe', str(OUT / 'ext_prepare_owner_test.exe'),
         '--grammar-exe', str(OUT / 'grammar_prepare_test.exe'),
         '--theme-exe', str(OUT / 'theme_prepare_test.exe'), *rooted_arguments], check=True))
    check('ext-prepare-products', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-prepare-products.py'), '--exe', str(OUT / 'ext_prepare_test.exe'),
         '--probe', str(OUT / 'ext_validate_probe_test.exe'), *rooted_arguments], check=True))
    def host_native_gate():
        faults = temp / 'host-native-faults'
        subprocess.run([sys.executable, str(ROOT / 'tests/faults/ext_host_native_build.py'),
                        '--windows', '--out', str(faults)], check=True)
        subprocess.run([sys.executable, str(ROOT / 'tests/ext-host-native.py'), '--dir', str(OUT),
                        '--fault-exe', str(faults / 'host-native-fault.exe'),
                        *(['--wine', args.wine] if args.wine else [])], check=True)
    check('ext-host-native', host_native_gate)
    check('ext-activation-owner', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-activation-owner.py'), '--dir', str(OUT),
         *rooted_arguments], check=True))
    check('ext-int31', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-int31.py'), '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-prepare-retire', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-prepare-retire.py'), '--dir', str(OUT), *rooted_arguments], check=True))
    check('custom-retire-capacity', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/custom-retire-capacity.py'), '--negative-controls',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    check('ext-legacy-parsers', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-legacy-parsers.py'), '--dir', str(OUT), *rooted_arguments], check=True))
    check('ext-prepare-legacy', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-prepare-legacy.py'), '--exe', str(OUT / 'ext_prepare_legacy_test.exe'),
         '--probe', str(OUT / 'ext_validate_probe_test.exe'), *rooted_arguments], check=True))
    check('ext-legacy-snapshot', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-legacy-snapshot.py'), '--producer', str(OUT / 'ext_legacy_snapshot_test.exe'),
         '--importer', str(OUT / 'ext_prepare_legacy_import_test.exe'),
         '--probe', str(OUT / 'ext_validate_probe_test.exe'), *rooted_arguments], check=True))
    check('ext-legacy-faults', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-legacy-faults.py'), '--probe', str(OUT / 'ext_validate_probe_test.exe'),
         *rooted_arguments], check=True))
    check('ext-validate-wire', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-validate-wire.py'), '--exe', str(OUT / 'ext_validate_wire_test.exe'),
         '--helper', str(OUT / 'rhun.exe'), *rooted_arguments], check=True))
    check('ext-prepare-faults', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-prepare-faults.py'), '--probe', str(OUT / 'ext_validate_probe_test.exe'),
         *rooted_arguments], check=True))
    check('ext-choices-disk', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/ext-choices-disk.py'), *rooted_arguments], check=True))
    check('extension-keeper', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/extension-keeper.py'),
         *(['--wine', args.wine, '--drive', str(Path(os.environ.get('WINEPREFIX', str(Path.home() / '.wine'))) / 'drive_c')] if args.wine else [])], check=True))
    check('task-keeper', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/task-keeper.py'), '--exe', str(OUT / 'task_keeper_test.exe'), '--extensions', '--faults',
         *(['--wine', args.wine] if args.wine else [])], check=True))
    for driver in ('keeper-cleanup', 'keeper-cleanup-launch', 'keeper-cleanup-terminal',
                   'keeper-cleanup-status', 'keeper-cleanup-cancel', 'keeper-cleanup-active',
                   'keeper-cleanup-backend', 'keeper-cleanup-win-producers'):
        check(driver, lambda driver=driver: subprocess.run(
            [sys.executable, str(ROOT / ('tests/' + driver + '.py')),
             *(['--wine', args.wine] if args.wine else [])], check=True))
    check('keeper-cleanup-live', lambda: subprocess.run(
        [sys.executable, str(ROOT / 'tests/keeper-cleanup-live.py'), *rooted_arguments], check=True))
    if not args.wine:
        check('ext-settings-worker', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/ext-settings-worker.py'), '--deadlines'], check=True))
        check('ext-settings-worker-faults', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/ext-settings-worker.py'), '--faults'], check=True))
        check('mem-try', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/mem-try.py')], check=True))
        check('mem-uninit', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/mem-uninit.py'), '--negative-controls'], check=True))
        check('discovery-alloc', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/discovery-alloc.py'), '--negative-controls'], check=True))
        check('discovery-gp', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/discovery-gp.py'), '--controls'], check=True))
        check('discovery-gp-transfer', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/discovery-gp-transfer.py'), '--controls'], check=True))
        check('runtime-service-table', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-service-table.py'), '--all'], check=True))
        check('runtime-service-session', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-service-session.py'), '--negative-controls'], check=True))
        check('runtime-channel', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-channel.py'), '--negative-controls'], check=True))
        check('runtime-channel-native', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-channel-native.py'), '--negative-controls'], check=True))
        check('runtime-channel-compact', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-channel-compact.py'), '--negative-controls'], check=True))
        check('runtime-ticket', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-ticket.py'), '--negative-controls'], check=True))
        check('runtime-admission', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-admission.py'), '--negative-controls'], check=True))
        check('runtime-reply', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-reply.py'), '--negative-controls'], check=True))
        check('runtime-reply-native', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-reply-native.py'), '--negative-controls'], check=True))
        check('runtime-remove', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-remove.py'), '--negative-controls'], check=True))
        check('runtime-debt-timer', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-debt-timer.py'), '--negative-controls'], check=True))
        check('runtime-session-clock', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/runtime-session-clock.py'), '--negative-controls'], check=True))
        check('ext-activation-eo-audit', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/ext-activation-eo-audit.py'), '--negative-controls'], check=True))
        check('mem-helpers', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/mem-helpers.py')], check=True))
        check('file-read-try', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/file-read-try.py')], check=True))
        check('file-ops', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/file-ops.py')], check=True))
        check('dir-scan', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/dir-scan.py')], check=True))
    check('windows-package', lambda: subprocess.run([sys.executable, str(ROOT / 'tests/windows-package.py')], check=True))
    for driver in ('task-core', 'task-view', 'task-clipboard', 'ext-watch-native', 'ext-choices'):
        check(driver, lambda driver=driver: subprocess.run(
            [sys.executable, str(ROOT / ('tests/' + driver + '.py')),
             *(['--faults'] if driver in ('task-core', 'task-view', 'ext-choices') else []),
             *(['--wine', args.wine] if args.wine else [])], check=True))

    for name, exe in [('ext-send', 'ext_send'), ('cpu', 'cpu'), ('doc', 'doc'), ('doc-selections', 'doc_selections'), ('doc-multi-edit', 'doc_multi_edit'), ('doc-batch', 'doc_batch'), ('doc-batch-guard', 'doc_batch_guard'), ('editor-multi-type', 'editor_multi_type'), ('editor-multi-newline', 'editor_multi_newline'), ('editor-multi-delete', 'editor_multi_delete'), ('editor-multi-tab', 'editor_multi_tab'), ('clipboard-write', 'clipboard_write'), ('clipboard-wire', 'clipboard_wire'), ('clipboard-metadata', 'clipboard_metadata'), ('clipboard-context', 'clipboard_context'), ('clipboard-paste-queue', 'clipboard_paste_queue'), ('editor-clipboard', 'editor_clipboard'), ('editor-paste', 'editor_paste'), ('snippet', 'snippet'), ('snippet-choice', 'snippet_choice'), ('snippet-unicode', 'snippet_unicode'), ('snippet-regex', 'snippet_regex'), ('snippet-regex-state', 'snippet_regex_state'), ('snippet-regex-scope', 'snippet_regex_scope'), ('snippet-regex-match', 'snippet_regex_match'), ('snippet-regex-limits', 'snippet_regex_limits'), ('snippet-replacement', 'snippet_replacement'), ('snippet-case', 'snippet_case'), ('snippet-case-api', 'snippet_case_api'), ('snippet-transform', 'snippet_transform'), ('snippet-transform-api', 'snippet_transform_api'), ('snippet-transform-indent', 'snippet_transform_indent'), ('snippet-transform-payload', 'snippet_transform_payload'), ('snippet-indent-capture', 'snippet_indent_capture'), ('snippet-transform-leave', 'snippet_transform_leave'), ('snippet-base64', 'snippet_base64'), ('syntax', 'syntax'), ('themes', 'theme'),
                      ('term', 'term'), ('diff', 'diff'), ('cols', 'cols'), ('config', 'config'),
                      ('textarea', 'textarea'), ('ui-clip', 'ui_clip'), ('fill', 'fill'), ('memmove', 'memmove'), ('keys', 'keys'),
                      ('config-strings', 'config_strings')]:
        check(name, lambda name=name, exe=exe: golden(name, exe + '_test'))
    for name, exe, file in [('strfind', 'str', 'strfind'), ('versions', 'update', 'versions'),
                            ('keymap-names-us-ru', 'xkb', 'keymap-names-us-ru'),
                            ('keymap-gnome-us', 'xkb', 'keymap-gnome-us'),
                            ('keymap-pl-intl', 'xkb', 'keymap-pl-intl')]:
        check(name, lambda name=name, exe=exe, file=file:
              golden(name, exe + '_test', ['tests/data/' + file + '.txt']))
    check('images', lambda: golden('images', 'image_test',
                                  sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / 'tests/data/images').iterdir())))
    check('grammars', lambda: golden('grammars', 'grammar_test',
                                     ['tests/data/detect.txt', 'tests/data/samples']))
    check('prefix-tag', lambda: golden('prefix-tag', 'grammar_test',
                                       ['--try', 'tests/data/prefix-tag.syn', 'tests/data/prefix-tag.txt']))
    check('version', lambda: equal(run('rhun.com', '--version').stdout,
                                  b'rhun ' + (ROOT / 'VERSION').read_bytes().strip() + b'\n'))
    check('input/right-alt-and-altgr', lambda: run('input_test.exe'))
    check('input/wheel-and-touchpad-steps', lambda: run('wheel_test.exe'))
    check('clipboard/bounded-read', lambda: golden('windows-clipboard-read', 'clipboard_read_test'))
    if not args.wine or os.environ.get('DISPLAY'):
        check('clipboard/native-metadata', lambda: golden('windows-clipboard-metadata', 'clipboard_native_metadata_test'))
        check('clipboard/owner-reentry', lambda: run('clipboard_reentry_test.exe'))
    if not args.wine:
        # Wine's MapVirtualKeyW gives VK_NUMPAD0 no character
        check('input/keypad-zoom', lambda: run('keypad_test.exe'))
    if not args.wine:
        check('files/long-paths', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/windows-longpaths.py')], check=True))
        check('clipboard/contention-copy-and-paste', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/windows-clipboard.py')], check=True))
        check('clipboard/native-failures', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/windows-clipboard-faults.py')], check=True))
        for name in ('settings-ui', 'appearance', 'editor-matrix', 'stress', 'splitter', 'scroll-sensitivity',
                     'file-launch', 'readonly-save', 'field-blink', 'window-focus',
                     'new-tab', 'tab-view', 'tab-drag', 'tab-pin', 'settings-search'):
            check('ui/' + name, lambda name=name: subprocess.run(
                [sys.executable, str(ROOT / ('tests/' + name + '.py'))], check=True,
                env=dict(os.environ, RHUN_TEST_EXE=str(OUT / 'rhun.com'))))
        check('desktop/startup', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/desktop-ux.py')], check=True,
            env=dict(os.environ, RHUN_TEST_EXE=str(OUT / 'rhun.com'))))
        check('ui/palette-scroll', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/palette-scroll.py')], check=True,
            env=dict(os.environ, RHUN_TEST_EXE=str(OUT / 'rhun.com'))))
        check('ui/commit-wrap', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/commit-wrap.py')], check=True,
            env=dict(os.environ, RHUN_TEST_EXE=str(OUT / 'rhun.com'))))
        check('git/untracked-refresh', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/git-untracked.py')], check=True,
            env=dict(os.environ, RHUN_TEST_EXE=str(OUT / 'rhun.com'))))
        check('ui/terminal-tabs', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/terminal-tabs.py')], check=True,
            env=dict(os.environ, RHUN_TEST_EXE=str(OUT / 'rhun.com'))))
        check('ui/focused-zoom', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/focused-zoom.py')], check=True,
            env=dict(os.environ, RHUN_TEST_EXE=str(OUT / 'rhun.com'))))
        check('agents/metadata', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/agents.py')], check=True,
            env=dict(os.environ, RHUN_TEST_EXE=str(OUT / 'rhun.com'))))
        check('explorer/create', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/explorer-create.py')], check=True,
            env=dict(os.environ, RHUN_TEST_EXE=str(OUT / 'rhun.com'))))
        check('explorer/tabs-follow-deletes-and-renames', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/explorer-tabs.py')], check=True,
            env=dict(os.environ, RHUN_TEST_EXE=str(OUT / 'rhun.com'))))
        # extensions: the host with the Python test extension, the title bar and page with installs
        # from a local release tree, and the showcase installed from GitHub (its Windows build)
        for name in ('save', 'save-actions', 'snippets', 'snippet-choices', 'snippet-variants', 'snippet-transforms', 'snippet-final', 'snippet-context', 'ext-host', 'ext-commands', 'ext-snapshots', 'ext-providers', 'ext-language', 'ext-scheduling', 'ext-watch', 'ext-boundaries', 'ext-ui', 'ext-showcase'):
            check('extensions/' + name, lambda name=name: subprocess.run(
                [sys.executable, str(ROOT / ('tests/' + name + '.py'))], check=True,
                env=dict(os.environ, RHUN_TEST_EXE=str(OUT / 'rhun.com'))))

    def ui(name):
        result = run('rhun.com', winpath(ROOT), '--headless', '1400x860', '--script',
                     'tests/scripts/' + name + '.rsc', env=environment('ui-' + name))
        equal(result.stdout, (ROOT / 'tests/data' / (name + '.ui.expected')).read_bytes())

    for name in ['editing', 'clipboard', 'movelines', 'find', 'findcase', 'replace', 'tabs', 'reopen', 'vim', 'wrap', 'togglecomment',
                 'highlight', 'image', 'mouse', 'cursor', 'compose', 'contextmenu',
                 'titlebar', 'titlebar-tap']:
        check('ui/' + name, lambda name=name: ui(name))

    def roots():
        source = temp / 'paths.txt'
        paths = ['C:/', 'C:/a/../', 'C:/a/../../b', r'C:\a\..\b',
                 '//server/share/', '//server/share/a/../../b', '//server/share/a/../',
                 'C:/a//./b/../c', 'relative/../path']
        source.write_text('\n'.join(paths) + '\n', encoding='utf-8', newline='\n')
        equal(run('path_test.exe', winpath(source)).stdout,
              b'C:/\nC:/\nC:/b\nC:/b\n//server/share/\n//server/share/b\n//server/share/\nC:/a/c\nrelative/../path\n')
    check('paths/drive-and-unc', roots)

    def links():
        # rhun://file/ links name a drive as /C:/ (as vscode://file/c:/), which is the path C:/; a UNC
        # path (//server/share) is refused, as a page would have Windows reach a server it names
        source = temp / 'links.txt'
        links = ['rhun://file/C:/work/app/main.c:10:2', 'rhun://file/c:/Program%20Files/a.txt',
                 'rhun://file//server/share/a.txt:3', 'rhun://file/%5C%5Cserver/share/a.txt',
                 'rhun://file/C:', 'rhun://other/C:/a']
        source.write_text('\n'.join(links) + '\n', encoding='utf-8', newline='\n')
        equal(run('url_test.exe', winpath(source)).stdout,
              b'C:/work/app/main.c 10 2\nc:/Program Files/a.txt 0 0\nbad\nbad\nC: 0 0\nbad\n')
    check('paths/rhun-links', links)

    def files():
        folder = temp / 'spaces café 日本'
        folder.mkdir()
        file = folder / 'file café 日本.txt'
        file.write_bytes(b'original\n')
        run('file_test.exe', 'write', winpath(file))
        equal(file.read_bytes(), b'saved\n')
        run('file_test.exe', 'write', winpath(folder / 'new.txt'))
        equal((folder / 'new.txt').read_bytes(), b'saved\n')
        result = run('file_test.exe', 'write', winpath(folder), success=False)
        assert result.returncode != 0 and folder.is_dir()
        equal(run('file_test.exe', 'error', winpath(folder)).stdout, b'21\n')
        equal(run('file_test.exe', 'error', winpath(folder / 'missing')).stdout, b'2\n')
        source = folder / 'crlf.txt'
        replacement = folder / 'replacement.txt'
        source.write_bytes(b'before\r\n')
        replacement.write_bytes(b'a\rb\r\nc\r\n')
        equal(run('file_test.exe', 'reload', winpath(source), winpath(replacement)).stdout, b'a\rb\nc\n')
        equal(source.read_bytes(), replacement.read_bytes())
        source.write_bytes(b'before\r\n')
        replacement.write_bytes(b'binary\0data\r\n')
        equal(run('file_test.exe', 'reload-binary', winpath(source), winpath(replacement)).stdout, b'before\n')
        equal(source.read_bytes(), replacement.read_bytes())
        long_file = folder / ('x' * 251 + '.txt')
        # Access the fixture independently of the runner's LongPathsEnabled policy.
        # The editor still receives the ordinary path and must handle its length.
        fixture_path = long_file if args.wine else Path('\\\\?\\' + str(long_file.resolve()))
        try:
            fixture_path.write_bytes(b'original\n')
            run('file_test.exe', 'write', winpath(long_file))
            equal(fixture_path.read_bytes(), b'saved\n')
        finally:
            fixture_path.unlink(missing_ok=True)
        assert not list(folder.glob('.rhun-backup-*')), 'recovery directory left after successful save'
        assert not list(folder.glob('.rhun-*.tmp')), 'temporary file left after save'
    check('files/unicode-crlf-replacement', files)

    def readonly():
        file = temp / 'readonly.txt'
        file.write_bytes(b'original\n')
        os.chmod(file, 0o444)
        try:
            assert run('file_test.exe', 'write', winpath(file), success=False).returncode != 0
            equal(file.read_bytes(), b'original\n')
        finally:
            os.chmod(file, 0o666)
    if not args.wine:
        check('files/readonly', readonly)

    def sharing():
        file = temp / 'locked.txt'
        file.write_bytes(b'original\n')
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                      ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        kernel.CreateFileW.restype = wintypes.HANDLE
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel.CreateFileW(str(file), 0x80000000, 1, None, 3, 0, None)
        assert handle != ctypes.c_void_p(-1).value
        try:
            assert run('file_test.exe', 'write', winpath(file), success=False).returncode != 0
            equal(file.read_bytes(), b'original\n')
        finally:
            kernel.CloseHandle(handle)
        assert not list(temp.glob('.rhun-backup-*'))
    if not args.wine:
        check('files/sharing-violation', sharing)

    def symlinks():
        target = temp / 'link-target.txt'
        target.write_bytes(b'original\n')
        link = temp / 'link.txt'
        os.symlink(target, link)
        equal(run('platform_test.exe', 'link', winpath(link)).stdout, (winpath(target) + '\n').encode())
        run('file_test.exe', 'write', winpath(link))
        assert link.is_symlink(), 'saving replaced the symlink itself'
        equal(target.read_bytes(), b'saved\n')
        dangling = temp / 'dangling.txt'
        os.symlink(temp / 'absent-target.txt', dangling)
        assert run('platform_test.exe', 'link', winpath(dangling), success=False).returncode != 0, 'dangling symlink unexpectedly resolved'
        assert run('file_test.exe', 'write', winpath(dangling), success=False).returncode != 0, 'saving a dangling symlink succeeded'
        assert dangling.is_symlink(), 'saving replaced the dangling symlink itself'
    if not args.wine:
        check('files/symlinks', symlinks)

    check('process/arguments-and-environment', lambda: equal(
        run('platform_test.exe', 'spawn', env=environment('process')).stdout,
        '\ntwo words\na\\"b\\\ncafé 日本\nspace and é\n'.encode()))

    def fonts():
        # A collection stores sfnt directories at an offset, but table offsets remain file-relative.
        ttf = bytearray((ROOT / 'assets/fonts/IosevkaFixed-Regular.ttf').read_bytes())
        count = struct.unpack_from('>H', ttf, 4)[0]
        for index in range(count):
            position = 12 + index * 16 + 8
            offset = struct.unpack_from('>I', ttf, position)[0]
            struct.pack_into('>I', ttf, position, offset + 16)
        ttc = temp / 'collection.ttc'
        ttc.write_bytes(b'ttcf' + struct.pack('>III', 0x10000, 1, 16) + ttf)
        run('platform_test.exe', 'font', winpath(ttc))
        ttc.write_bytes(b'ttcf' + struct.pack('>III', 0x10000, 1, 0xffffffff))
        assert run('platform_test.exe', 'font', winpath(ttc), success=False).returncode != 0
        if not args.wine:
            for name in ['msgothic.ttc', 'msyh.ttc']:
                path = Path(os.environ['SystemRoot']) / 'Fonts' / name
                if path.exists():
                    run('platform_test.exe', 'font', path, 'cjk')
    check('fonts/collection-and-invalid-offset', fonts)

    def terminal(mode, marker):
        # The helper allows 30s for the prompt, then 10s each for command output and exit.
        result = run('platform_test.exe', mode, env=environment('terminal-' + mode), timeout=60)
        assert marker in result.stdout, result.stdout
    if not args.wine:
        check('terminal/conpty-cmd-create-resize-output-close', lambda: terminal('pty', b'RHUN_CONPTY_OK'))
        check('terminal/conpty-powershell-input-output-close', lambda: terminal('pty-input', b'RHUN_INPUT_OK'))
        check('terminal/conpty-powershell-slow-start', lambda: terminal('pty-input-slow-start', b'RHUN_INPUT_OK'))

    def script_file(name, text):
        path = temp / (name + '.rsc')
        path.write_text(text, encoding='utf-8', newline='\n')
        return winpath(path)

    def cls_keeps_prompt():
        # The pseudoconsole is created at 80x24 and resized to the panel before its first output;
        # if that resize is lost, cls repaints 24 rows into the smaller grid and the prompt scrolls away.
        project = temp / 'cls'
        project.mkdir()
        env = environment('cls')
        config = temp / 'cls' / 'config' / 'rhun' / 'config'
        config.parent.mkdir(parents=True)
        config.write_text('[terminal]\nshell = C:/Windows/System32/cmd.exe\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
        script = script_file('cls', 'cmd new_terminal\nwait 3000\ntype echo before\nkey Return\nwait 1500\n'
                                    'type cls\nkey Return\nwait 3000\nprint-term\nquit\n')
        out = run('rhun.com', winpath(project), '--headless', '1000x700', '--script', script, env=env).stdout
        screen = out.decode('utf-8', 'replace').splitlines()
        assert b'before' not in out, out
        assert any(line.rstrip().endswith('>') for line in screen[:3]), out
    if not args.wine:
        check('terminal/cls-keeps-prompt', cls_keeps_prompt)

    def session():
        project = temp / 'project space % café'
        project.mkdir()
        file = project / 'hello.txt'
        file.write_bytes(b'hello\r\n')
        env = environment('session')
        first = script_file('session-save', 'key End\ntype !\ncmd save\nprint-state\nquit\n')
        run('rhun.com', winpath(project), winpath(file), '--headless', '1000x700', '--script', first, env=env)
        equal(file.read_bytes(), b'hello!\r\n')
        second = script_file('session-restore', 'print-state\nprint-doc\nquit\n')
        out = run('rhun.com', winpath(project), '--headless', '1000x700', '--script', second, env=env).stdout
        assert b'active=hello.txt' in out and b'hello!\n' in out, out
    check('session/drive-unicode-percent-roundtrip', session)

    def path_prompts():
        project = temp / 'path prompts'
        project.mkdir()
        file = project / 'nested' / 'café.txt'
        windows_path = winpath(file).replace('/', '\\')
        script = script_file('path-prompts',
            f'cmd new_file\ntype saved Ω\ncmd save_as\nkey ctrl+a\ntype {windows_path}\nkey Return\n'
            f'cmd close_tab\ncmd open_file\nkey ctrl+a\ntype {windows_path}\nkey Return\nprint-doc\nquit\n')
        output = run('rhun.com', winpath(project), '--headless', '1000x700', '--script', script,
                     env=environment('prompts')).stdout
        equal(file.read_bytes(), 'saved Ω\n'.encode())
        assert 'saved Ω'.encode() in output, output
    check('paths/backslash-save-as-and-open', path_prompts)

    def shift_wheel():
        # Shift turns the editor's wheel sideways, as in other Windows apps (discussion 67)
        project = temp / 'shift wheel'
        project.mkdir()
        wide = project / 'wide.txt'
        wide.write_text(''.join(f'line {i:02d} ' + 'wide ' * 60 + '\n' for i in range(80)),
                        encoding='utf-8', newline='\n')
        script = script_file('shift-wheel', 'move 500 350\nscroll 120 shift\nwait 50\nprint-scroll\n'
                                            'scroll 120\nwait 50\nprint-scroll\nquit\n')
        output = run('rhun.com', winpath(project), winpath(wide), '--headless', '1000x700', '--script',
                     script, env=environment('shift-wheel')).stdout.decode()
        sideways, down = [line.split()[:2] for line in output.splitlines() if line.startswith('x=')]
        assert sideways == ['x=120', 'y=0'], output
        assert down[0] == 'x=120' and down[1] != 'y=0', output
    check('wheel/shift-scrolls-sideways', shift_wheel)

    def control():
        result = run('rhun.com', '--headless', '800x600', '--control', winpath(temp / 'control'), success=False,
                     env=environment('control'))
        assert result.returncode != 0 and b'--script' in result.stdout, result.stdout
    check('control/explicit-unsupported-error', control)

    def crlf_script():
        script = temp / 'crlf-script.rsc'
        script.write_bytes(b'cmd new_file\r\ntype Windows script\r\nprint-doc\r\nquit\r\n')
        output = run('rhun.com', '--headless', '800x600', '--script', winpath(script),
                     env=environment('crlf-script')).stdout
        equal(output, b'Windows script\n<eod>\n')
    check('script/crlf-line-endings', crlf_script)

    def watcher():
        project = temp / 'watched project'
        project.mkdir()
        file = project / 'watched.txt'
        file.write_bytes(b'before\n')
        script = script_file('watch', f'open {winpath(file).upper()}\nprint-state\nwait 1600\nprint-doc\nquit\n')
        process = subprocess.Popen(command('rhun.com', winpath(project), winpath(file), '--headless',
                                           '1000x700', '--script', script), stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, env=environment('watch'))
        try:
            # The first state line is emitted after the document and its watch are installed.
            first = []
            reader = threading.Thread(target=lambda: first.append(process.stdout.readline()), daemon=True)
            reader.start()
            reader.join(timeout=10)
            assert first and b'tabs=1 active=' in first[0], 'duplicate tab or document did not become ready'
            replacement = project / 'replacement.txt'
            replacement.write_bytes('after café\n'.encode())
            os.replace(replacement, file)
            output = process.communicate(timeout=15)[0]
            assert process.returncode == 0 and b'after caf' in output, output
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    check('watch/mixed-case-dedup-and-atomic-replacement', watcher)

    def follow(name, open_path, steps):
        """Opens open_path, then runs each step (a function) once the editor shows what the step before
        it expects; each step returns the text it should then show."""
        project = temp / name
        script = script_file(name, f'open {winpath(open_path)}\nprint-state\n' +
                             'wait 150\nprint-doc\n' * 120 + 'quit\n')
        process = subprocess.Popen(command('rhun.com', winpath(project), winpath(open_path), '--headless',
                                           '1000x700', '--script', script), stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, env=environment(name))

        def documents():
            text = b''
            for line in process.stdout:
                line = line.replace(b'\r\n', b'\n')
                if line == b'<eod>\n':
                    yield text.removesuffix(b'\n')
                    text = b''
                else:
                    text += line
        try:
            first = process.stdout.readline()
            assert b'tabs=1 active=' in first, first
            shown = documents()
            for step in steps:
                expected = step()
                last = None
                for last in shown:
                    if last == expected:
                        break
                else:
                    raise AssertionError(f'never showed {expected!r}, last {last!r}')
        finally:
            process.kill()
            process.wait()

    def folder_made_again():
        sub = temp / 'remade' / 'sub' / 'deeper'
        sub.mkdir(parents=True)
        note = sub / 'note.txt'
        note.write_bytes(b'before\n')

        def remade():
            note.unlink()
            sub.rmdir()
            sub.mkdir()
            note.write_bytes(b'after\n')
            return b'after\n'

        def written():
            note.write_bytes(b'again\n')
            return b'again\n'

        def both_levels():
            shutil.rmtree(temp / 'remade' / 'sub')
            time.sleep(0.5)
            (temp / 'remade' / 'sub').mkdir()
            time.sleep(0.5)
            sub.mkdir()
            time.sleep(0.5)
            note.write_bytes(b'third\n')
            return b'third\n'
        follow('remade', note, [remade, written, both_levels])
    check('watch/folder-made-again', folder_made_again)

    def symlink_elsewhere():
        project = temp / 'linked'
        elsewhere = temp / 'linked-elsewhere'
        project.mkdir()
        elsewhere.mkdir()
        real = elsewhere / 'real.txt'
        real.write_bytes(b'before\n')
        link = project / 'link.txt'
        os.symlink(real, link)

        def written():
            real.write_bytes(b'written\n')
            return b'written\n'

        def replaced():
            replacement = elsewhere / 'replacement.tmp'
            replacement.write_bytes(b'replaced\n')
            os.replace(replacement, real)
            return b'replaced\n'
        def link_on_the_way():
            # link -> hop -> real: the symlink on the way pointed to a file in a folder not watched yet,
            # so only the hop's folder tells
            other = temp / 'linked-other' / 'other.txt'
            other.parent.mkdir()
            other.write_bytes(b'other\n')
            time.sleep(0.5)
            hop.unlink()
            os.symlink(other, hop)
            return b'other\n'
        hop = temp / 'linked-hops' / 'hop.txt'
        hop.parent.mkdir()
        os.symlink(real, hop)
        os.unlink(link)
        os.symlink(hop, link)
        follow('linked', link, [written, replaced, link_on_the_way])

    def file_becomes_symlink():
        project = temp / 'relinked'
        project.mkdir()
        plain = project / 'plain.txt'
        plain.write_bytes(b'plain\n')
        real = temp / 'relinked-elsewhere' / 'real.txt'
        real.parent.mkdir()
        real.write_bytes(b'real\n')

        def relinked():
            plain.unlink()
            os.symlink(real, plain)
            return b'real\n'

        def written():
            real.write_bytes(b'real changed\n')
            return b'real changed\n'
        follow('relinked', plain, [relinked, written])
    if not args.wine:
        check('watch/symlink-to-another-folder', symlink_elsewhere)
        check('watch/file-replaced-by-symlink', file_becomes_symlink)

    def agents():
        env = environment('agents')
        home = Path(env['HOME'])
        project = temp / 'agent project'
        project.mkdir()
        slug = re.sub('[^A-Za-z0-9]', '-', winpath(project))
        claude = home / '.claude/projects' / slug / 's1.jsonl'
        codex = home / '.codex/sessions/2026/09/26/rollout-c1.jsonl'
        for path in [claude, codex]:
            path.parent.mkdir(parents=True, exist_ok=True)
        claude.write_text((ROOT / 'tests/data/agents/claude.jsonl').read_text(encoding='utf-8').replace('@PROJECT@', winpath(project)), encoding='utf-8')
        spelling = winpath(project).replace('/', '\\').upper()
        codex.write_text((ROOT / 'tests/data/agents/codex.jsonl').read_text(encoding='utf-8').replace('@PROJECT@', json.dumps(spelling)[1:-1]), encoding='utf-8')
        os.utime(claude, (1700000000, 1700000000))
        os.utime(codex, (1700000100, 1700000100))
        # Grok Build names the cwd in summary.json, here in the backslash spelling
        grok = home / '.grok/sessions/project/01a11c1e-808b-7263-a007-7a09593740c9'
        grok.mkdir(parents=True)
        (grok / 'updates.jsonl').write_text((ROOT / 'tests/data/agents/grok.jsonl').read_text(encoding='utf-8').replace('@PROJECT@', winpath(project)), encoding='utf-8')
        (grok / 'summary.json').write_text((ROOT / 'tests/data/agents/grok.json').read_text(encoding='utf-8').replace('@PROJECT@', json.dumps(winpath(project).replace('/', '\\'))[1:-1]), encoding='utf-8')
        os.utime(grok / 'updates.jsonl', (1699999900, 1699999900))
        env.pop('GROK_HOME', None)
        output = run('rhun.com', winpath(project), '--headless', '1400x860', '--script',
                     'tests/scripts/agents.rsc', env=env).stdout
        equal(output, (ROOT / 'tests/data/agents.ui.expected').read_bytes())

    def git():
        project = temp / 'git project café'
        project.mkdir()
        def command(*arguments):
            subprocess.run(['git', '-C', str(project), *arguments], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        command('init', '-b', 'main')
        command('config', 'user.name', 'Test')
        command('config', 'user.email', 'test@example.invalid')
        command('config', 'core.autocrlf', 'false')
        file = project / 'a.txt'
        file.write_bytes(b'before\n')
        command('add', 'a.txt')
        command('commit', '-m', 'Initial')
        file.write_bytes(b'after\n')
        script = script_file('git', 'wait-git\nprint-git\ncmd git_changes\nwait-git\nprint-doc\nquit\n')
        output = run('rhun.com', winpath(project), winpath(file), '--headless', '1000x700', '--script', script,
                     env=environment('git')).stdout
        assert b'git on branch=main\nM a.txt' in output and b'before\nafter\n' in output, output
    if not args.wine:
        check('agents/windows-session-paths', agents)
        check('git/status-and-diff', git)

    def commit_ai(provider, cancel=False):
        name = 'commit-ai-' + provider + ('-cancel' if cancel else '')
        project = temp / (name + " 'quoted $; café")
        project.mkdir()
        for arguments in [('init', '-b', 'main'), ('config', 'user.name', 'Test'),
                          ('config', 'user.email', 'test@example.invalid')]:
            subprocess.run(['git', '-C', str(project), *arguments], check=True, capture_output=True)
        (project / 'new.txt').write_text('new content\n', encoding='utf-8')
        env = environment(name)
        config = temp / name / 'config/rhun'
        config.mkdir(parents=True)
        (config / 'config').write_text('[git]\ncommit_ai = ' + provider + '\n', encoding='utf-8')
        bindir = temp / name / 'bin'
        bindir.mkdir()
        shutil.copy2(OUT / 'ai_cli_test.exe', bindir / (provider + '.exe'))
        env['PATH'] = str(bindir.resolve()) + ';' + env['PATH']
        env['OPENAI_API_KEY'] = 'must-not-be-used'
        lines = 'wait-git\nwait-ai\ncmd git_generate_message\n'
        if cancel:
            env['RHUN_AI_TEST_DELAY'] = '1'
            lines += 'wait 500\ncmd ai_cancel\n'
        lines += 'wait-ai\nprint-scm\nprint-ai\n'
        output = run('rhun.com', winpath(project), '--headless', '1400x860', '--script',
                     script_file(name, lines), env=env, timeout=40).stdout
        if cancel:
            assert b'Describe Windows changes' not in output and b'Cancelled' in output, output
        else:
            assert b'message=Describe Windows changes' in output, output

    if not args.wine:
        for provider in ('claude', 'codex'):
            check('ai/' + provider + '-subscription-cli', lambda provider=provider: commit_ai(provider))
        check('ai/cancel', lambda: commit_ai('claude', cancel=True))
        check('ai/local-model-protocol', lambda: subprocess.run(
            [sys.executable, str(ROOT / 'tests/commit-ai-windows.py')], check=True))

    def native_user():
        user = ctypes.WinDLL('user32', use_last_error=True)
        callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        user.EnumWindows.argtypes = [callback_type, wintypes.LPARAM]
        user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
        user.GetWindowThreadProcessId.restype = wintypes.DWORD
        user.GetForegroundWindow.argtypes = []
        user.GetForegroundWindow.restype = wintypes.HWND
        user.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
        user.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
        user.IsWindowVisible.argtypes = [wintypes.HWND]
        user.IsIconic.argtypes = [wintypes.HWND]
        user.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
        user.SendMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
        user.SendMessageW.restype = wintypes.LPARAM
        user.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
        return user, callback_type

    def native_title(user, window):
        title = ctypes.create_unicode_buffer(1024)
        user.GetWindowTextW(window, title, len(title))
        return title.value

    def native_find_window(user, callback_type, *, pid=None, name=None, timeout=10):
        found = []
        @callback_type
        def enum(window, unused):
            owner = wintypes.DWORD()
            user.GetWindowThreadProcessId(window, ctypes.byref(owner))
            if pid is not None and owner.value != pid:
                return True
            classname = ctypes.create_unicode_buffer(80)
            user.GetClassNameW(window, classname, len(classname))
            if classname.value == 'rhunWindow' and (name is None or native_title(user, window).startswith(name)):
                found.append((window, owner.value))
            return True
        deadline = time.monotonic() + timeout
        while not found and time.monotonic() < deadline:
            user.EnumWindows(enum, 0)
            if not found:
                time.sleep(0.03)
        assert found, 'native editor window did not appear'
        assert len(found) == 1, f'expected one editor window, found {found}'
        return found[0]

    def native_assert_foreground(user, window):
        deadline = time.monotonic() + 2
        while user.GetForegroundWindow() != window and time.monotonic() < deadline:
            time.sleep(0.03)
        assert user.IsWindowVisible(window), 'editor window stayed hidden'
        assert not user.IsIconic(window), 'editor window stayed minimized'
        foreground = user.GetForegroundWindow()
        assert foreground == window, f'editor HWND {window} is not foreground HWND {foreground}'

    def native_file_launch(show):
        name = 'native-file-' + str(show)
        project = temp / name / 'previous project'
        project.mkdir(parents=True)
        previous = project / 'previous.txt'
        previous.write_bytes(b'previous\n')
        file = temp / name / 'standalone café.rb'
        file.write_bytes(b'puts :standalone\n')
        env = environment(name)
        config = Path(env['XDG_CONFIG_HOME']) / 'rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
        run('rhun.com', winpath(project), winpath(previous), '--headless', '1000x700',
            '--script', script_file(name + '-seed', 'quit\n'), env=env)
        marker = Path(env['XDG_STATE_HOME']) / 'rhun/last-project'
        remembered = marker.read_bytes()
        # a file launch is a quick edit: no explorer or agents panel; CI keeps the window's picture
        shot = ''
        if os.environ.get('RHUN_TEST_ARTIFACTS'):
            visual = Path(os.environ['RHUN_TEST_ARTIFACTS']).resolve() / 'visual'
            visual.mkdir(parents=True, exist_ok=True)
            shot = 'shot ' + (visual / (name + '.ppm')).as_posix() + '\n'
        script = script_file(name, 'print-project\nprint-state\nprint-panels\nwait 5000\n' + shot +
                             'cmd next_tab\nprint-state\nquit\n')
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = show
        process = subprocess.Popen(command('rhun.exe', winpath(file), '--script', script),
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   env=env, startupinfo=startup)
        user, callback_type = native_user()
        try:
            first = []
            reader = threading.Thread(target=lambda: first.extend(
                [process.stdout.readline() for _ in range(3)]), daemon=True)
            reader.start()
            reader.join(timeout=10)
            assert len(first) == 3, first
            same_folder(first[0], file.parent)
            assert b'tabs=1 active=' + file.name.encode() in first[1], first
            assert first[2].strip() == b'explorer=0 agents=0 term=0', first
            window, _ = native_find_window(user, callback_type, pid=process.pid)
            native_assert_foreground(user, window)
            output = process.communicate(timeout=10)[0]
            assert process.returncode == 0, output
            assert b'tabs=1 active=' + file.name.encode() in output, output
            equal(marker.read_bytes(), remembered)
            equal(file.read_bytes(), b'puts :standalone\n')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    def native_cli_file_launch():
        name = 'native-cli-file'
        project = temp / name / 'previous project'
        project.mkdir(parents=True)
        previous = project / 'previous.txt'
        previous.write_bytes(b'previous\n')
        file = temp / name / 'standalone cli café.rb'
        file.write_bytes(b'puts :cli\n')
        env = environment(name)
        config = Path(env['XDG_CONFIG_HOME']) / 'rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
        run('rhun.com', winpath(project), winpath(previous), '--headless', '1000x700',
            '--script', script_file(name + '-seed', 'quit\n'), env=env)
        marker = Path(env['XDG_STATE_HOME']) / 'rhun/last-project'
        remembered = marker.read_bytes()
        user, callback_type = native_user()
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 7  # keep the temporary console minimized and inactive
        process = subprocess.Popen(command('rhun.com', winpath(file)), env=env,
                                   startupinfo=startup, creationflags=subprocess.CREATE_NEW_CONSOLE)
        window = None
        try:
            # No --script or --wait: the console entry must exit after spawning the GUI sibling.
            assert process.wait(timeout=10) == 0, 'console launcher failed'
            window, gui_pid = native_find_window(user, callback_type, name=file.name)
            assert gui_pid != process.pid, 'console entry did not respawn the GUI'
            title = native_title(user, window)
            assert title.endswith(file.parent.name) and project.name not in title, title
            native_assert_foreground(user, window)
            user.PostMessageW(window, 0x10, 0, 0)  # WM_CLOSE
            deadline = time.monotonic() + 5
            while user.IsWindowVisible(window) and time.monotonic() < deadline:
                time.sleep(0.03)
            assert not user.IsWindowVisible(window), 'standalone editor did not close'
            equal(marker.read_bytes(), remembered)
            equal(file.read_bytes(), b'puts :cli\n')
        finally:
            if window is not None:
                user.PostMessageW(window, 0x10, 0, 0)
            if process.poll() is None:
                process.kill()
                process.wait()

    def native_window(preserve=False):
        name = 'window-preserve' if preserve else 'window'
        project = temp / ('native ' + name)
        project.mkdir()
        file = project / 'input.txt'
        file.write_bytes(b'native\n')
        screenshot = temp / (name + '.ppm')
        script = script_file(name, f'print-state\nwait {7000 if preserve else 2500}\ncmd select_all\ncmd copy\n'
                             'key ctrl+End\ncmd paste\ncmd save\n'
                             f'shot {winpath(screenshot)}\nprint-doc\nquit\n')
        env = environment(name)
        config = Path(env['XDG_CONFIG_HOME']) / 'rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
        process = subprocess.Popen(command('rhun.exe', winpath(project), winpath(file), '--script', script),
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
        user, callback_type = native_user()
        try:
            first = []
            reader = threading.Thread(target=lambda: first.append(process.stdout.readline()), daemon=True)
            reader.start()
            reader.join(timeout=10)
            assert first and b'active=input.txt' in first[0], 'document did not become ready'
            window, _ = native_find_window(user, callback_type, pid=process.pid, timeout=2)
            # Input goes through the real window procedure and UTF-16 surrogate handling.
            for code in [ord('Ω'), 0xD83D, 0xDE00]:
                user.SendMessageW(window, 0x102, code, 0)
            if preserve:
                user.ShowWindow(window, 6)  # minimize the project while its changes are unsaved
                assert user.IsIconic(window), 'project window did not minimize'
                standalone = temp / 'preserve standalone café.rb'
                standalone.write_bytes(b'puts :separate\n')
                child_script = script_file('preserve-file', 'print-project\nprint-state\nwait 3000\nquit\n')
                child = subprocess.Popen(command('rhun.exe', winpath(standalone), '--script', child_script),
                                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
                try:
                    child_window, _ = native_find_window(user, callback_type, pid=child.pid,
                                                        name=standalone.name)
                    native_assert_foreground(user, child_window)
                    assert user.IsIconic(window), 'file launch restored the other project window'
                    equal(file.read_bytes(), b'native\n')
                    child_output = child.communicate(timeout=10)[0]
                    assert child.returncode == 0, child_output
                    lines = child_output.split(b'\n')
                    same_folder(lines[0], standalone.parent)
                    assert lines[1].startswith(b'tabs=1 active=' + standalone.name.encode()), child_output
                finally:
                    if child.poll() is None:
                        child.kill()
                        child.wait()
            output = process.communicate(timeout=15)[0]
            assert process.returncode == 0, output
            equal(file.read_bytes(), 'Ω😀native\nΩ😀native\n'.encode())
            pixels = screenshot.read_bytes()
            assert pixels.startswith(b'P6\n') and len(set(pixels[100:])) > 16, 'window did not render'
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    def native_issue_pictures():
        """In a real window: find ignoring case beyond ASCII, and the question before a read-only file is
        replaced; CI keeps their pictures"""
        name = 'native-issues'
        project = temp / name
        project.mkdir()
        # below the find bar, which covers the first lines of a narrow editor
        (project / 'case.txt').write_bytes('\n\n\n\nÉté été ÉTÉ\nПривет ПРИВЕТ яблоко ЯБЛОКО\n'.encode())
        readonly = project / 'readonly.txt'
        readonly.write_bytes(b'This file is read-only.\n')
        os.chmod(readonly, 0o444)
        env = environment(name)
        config = Path(env['XDG_CONFIG_HOME']) / 'rhun/config'
        config.parent.mkdir(parents=True)
        config.write_text('[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
        visual = temp / name / 'shots'
        if os.environ.get('RHUN_TEST_ARTIFACTS'):
            visual = Path(os.environ['RHUN_TEST_ARTIFACTS']).resolve() / 'visual'
        visual.mkdir(parents=True, exist_ok=True)
        find_shot, readonly_shot = visual / 'native-find.ppm', visual / 'native-readonly.ppm'
        script = script_file(name, f'wait 1500\nopen {winpath(project / "case.txt")}\nkey ctrl+f\ntype été\n'
                                   f'wait 300\nprint-state\nshot {find_shot.as_posix()}\nkey Escape\n'
                                   f'open {winpath(readonly)}\nkey End\ntype  typed\nkey ctrl+s\nwait 300\n'
                                   f'print-state\nshot {readonly_shot.as_posix()}\nkey Escape\nquit\n')
        try:
            output = run('rhun.exe', winpath(project), '--script', script, env=env).stdout
            lines = output.decode('utf-8', 'replace').splitlines()
            assert 'active=case.txt line=5 col=4 sel=5' in lines[0], output
            assert 'active=readonly.txt' in lines[1] and 'focus=5' in lines[1], output
            equal(readonly.read_bytes(), b'This file is read-only.\n')
            for shot in (find_shot, readonly_shot):
                pixels = shot.read_bytes()
                assert pixels.startswith(b'P6\n') and len(set(pixels[100:])) > 16, shot
        finally:
            os.chmod(readonly, 0o644)

    if not args.wine:
        check('window/issue-pictures-find-and-readonly', native_issue_pictures)
        check('window/file-only-background-start-foreground', lambda: native_file_launch(4))
        check('window/file-only-minimized-start-foreground', lambda: native_file_launch(7))
        check('window/file-only-cli-respawn-foreground', native_cli_file_launch)
        check('window/file-launch-preserves-minimized-unsaved-project', lambda: native_window(preserve=True))
        check('window/unicode-input-clipboard-save-and-render', native_window)
    else:
        print('skip native readonly, sharing, symlinks, ConPTY and desktop tests under Wine', flush=True)

if failures:
    print('Failed: ' + ', '.join(failures), file=sys.stderr)
    raise SystemExit(1)
