#!/usr/bin/env python3
"""Check recoverable clipboard duplication failure after task output conversion succeeds."""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def checked(command):
    result = subprocess.run(list(map(str, command)), cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=120)
    if result.returncode:
        raise AssertionError(f'{command[0]} exited {result.returncode}: {result.stdout.decode(errors="replace")[:4000]}')


def build(platform, folder):
    spec = importlib.util.spec_from_file_location('task_core_test_driver', ROOT / 'tests/task-core.py')
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    objects = []
    if platform == 'windows':
        spec = importlib.util.spec_from_file_location('rhun_windows_builder', ROOT / 'tools/build-windows.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
    for relative, name in [('src/app/editor.s', 'editor'), ('src/memtry.s', 'memory'),
                           ('tests/task_clipboard_test.s', 'test')]:
        text = (ROOT / relative).read_text()
        if name == 'editor':
            begin = text.index('FN ed_clip_set_metadata\n')
            end = text.index('\n# Copy callers share', begin)
            body = text[begin:end]
            if body.count('call mem_dup_try') != 1 or 'jz .Lclip_invalid' not in body:
                raise AssertionError('ed_clip_set_metadata must use checked mem_dup_try before this task Copy gate')
            text = text[:begin] + body.replace('call mem_dup_try', 'call tcpt_dup') + text[end:]
        path = folder / (name + '.s')
        if platform == 'windows':
            text = re.sub(r'(?m)^\.section \.rodata$', '.section .rdata,"dr"', text)
        path.write_text(text)
        obj = folder / (name + ('.obj' if platform == 'windows' else '.o'))
        if platform == 'macos':
            translated = folder / (name + '-a64.s')
            checked([sys.executable, ROOT / 'tools/arm64.py', '-I', ROOT / 'src', '-D', 'MACOS',
                     '-D', 'TEST_TASK_CLIPBOARD_FAULT', path, translated])
            checked(['as', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', obj, translated])
        elif platform == 'windows':
            checked([builder.tool('llvm-mc'), '-triple=x86_64-pc-windows-msvc', '-filetype=obj',
                     '-defsym=WINDOWS=1', '-defsym=TEST_TASK_CLIPBOARD_FAULT=1', '-I', ROOT / 'src',
                     '-I', ROOT / 'src/win', path, '-o', obj])
        else:
            checked(['as', '--64', '-I', ROOT / 'src', '--defsym', 'TEST_TASK_CLIPBOARD_FAULT=1',
                     '-o', obj, path])
        objects.append(obj)
    editor_name = 'src_app_editor.s.obj' if platform == 'windows' else 'src_app_editor.o'
    objects.extend(obj for obj in driver.runtime_objects(platform) if obj.name != editor_name)
    # This driver replaces editor/memtry only. Keep the real core for any built task view.
    core_object = ROOT / ('build/windows/src_app_taskcore.s.obj' if platform == 'windows'
                          else 'build/obj/src_app_taskcore.o')
    if core_object.is_file():
        objects.append(core_object)
    exe = folder / ('task-clipboard.exe' if platform == 'windows' else 'task-clipboard')
    if platform == 'macos':
        command = ['clang', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', exe, *objects]
        for framework in ('AppKit', 'QuartzCore', 'IOSurface', 'CoreServices', 'Carbon', 'Security'):
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
    parser.add_argument('--wine')
    args = parser.parse_args()
    platform = 'windows' if args.wine or os.name == 'nt' else 'macos' if sys.platform == 'darwin' else 'linux'
    with tempfile.TemporaryDirectory(prefix='rhun-task-clipboard-') as temporary:
        exe = build(platform, Path(temporary))
        command = [str(exe)] if not args.wine else [args.wine, 'Z:' + exe.resolve().as_posix()]
        result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        expected = (ROOT / 'tests/data/task-clipboard.expected').read_bytes()
        if result.returncode or result.stdout != expected:
            raise AssertionError(f'task clipboard: exit {result.returncode}, output {result.stdout!r}')
    print('ok   task clipboard allocation failure')


if __name__ == '__main__':
    main()
