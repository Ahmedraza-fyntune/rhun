"""Focused validator fault links and optional isolated whole-tree bootstrap."""
import argparse
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def build(folder, windows=False, root_fixture=False, fixture_name=None, capture_bypass=False, image_read_bypass=False, source_role_bypass=False):
    folder.mkdir(parents=True, exist_ok=True)
    mac = sys.platform == 'darwin' and not windows
    replacements = {}
    for name, old, new in [
        ('src/mem.s', 'FN mem_alloc_try\n', 'FN evf_mem_alloc_try_real\n'),
        ('src/app/extpreparecapture.s', 'FN prep_owned_exec_stat\n', 'FN evf_owned_stat_real\n'),
        ('src/app/extprepareassets.s', 'FN prep_asset_plan\n', 'FN epf_plan_real\n'),
        ('src/app/extvalidatepath.s', 'FN ext_root_read\n', 'FN evf_ext_root_read_real\n'),
        ('src/app/extvalidatepath.s', 'FN ext_root_read_once\n', 'FN evf_once_real\n'),
        ('src/win/dirscan.s' if windows else 'src/dirscan.s',
         'FN win_dir_scan_handle_try\n' if windows else 'FN dir_scan_fd_try\n',
         'FN evf_scan_real\n'),
    ]:
        text = replacements.get(name, (ROOT / name).read_text())
        assert text.count(old) == 1, name
        replacements[name] = text.replace(old, new)
    capture = replacements['src/app/extpreparecapture.s']
    if capture_bypass:
        capture = capture.replace('FN prep_capture_compare\n', 'FN prep_capture_compare\n    xor eax, eax\n    ret\n', 1)
    if image_read_bypass:
        capture = capture.replace('FN prep_image_read\n', 'FN prep_image_read\n    jmp ext_root_read_once\n', 1)
    replacements['src/app/extpreparecapture.s'] = capture
    if source_role_bypass:
        name = 'src/app/extvalidatetree.s'
        text = (ROOT / name).read_text()
        assert text.count('evt_asset_role:\n') == 1
        replacements[name] = text.replace('evt_asset_role:\n', 'evt_asset_role:\n    xor eax, eax\n    ret\n', 1)
    for symbol, replacement in [('win_ext_root_stat'  if windows else 'ext_root_stat', 'evf_stat_real'),
                                ('win_ext_root_close' if windows else 'ext_root_close', 'evf_close_real')]:
        name = 'src/win/extvalidatepath.s' if windows else 'src/app/extvalidatepath.s'
        text = replacements.get(name, (ROOT / name).read_text())
        old = 'FN ' + symbol + '\n'
        assert text.count(old) == 1
        replacements[name] = text.replace(old, 'FN ' + replacement + '\n')
    fixture = (ROOT / (fixture_name or ('tests/ext_root_test.s' if root_fixture else 'tests/ext_validate_test.s'))).read_text()
    fixture += '\n' + (ROOT / 'tests/faults/ext_validate_faults.s').read_text()
    paths = [*replacements.items(), ('fixture.s', fixture)]
    objects = {}
    if windows:
        spec = importlib.util.spec_from_file_location('win_build', ROOT / 'tools/build-windows.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        mc, linker = module.tool('llvm-mc'), module.tool('lld-link')
    for relative, source in paths:
        path = folder / relative.replace('/', '_')
        obj = path.with_suffix('.obj' if windows else '.o')
        if windows:
            source = re.sub(r'(?m)^(\s*\.section) \.rodata[^\n]*', r'\1 .rdata,"dr"', source)
        path.write_text(source)
        if windows:
            command = [mc, '-triple=x86_64-pc-windows-msvc', '-filetype=obj', '-I', str(ROOT / 'src'),
                       '-I', str(ROOT / 'src/win'), '-defsym=WINDOWS=1', '-o', str(obj), str(path)]
        elif mac:
            translated = path.with_suffix('.a64.s')
            subprocess.run([sys.executable, str(ROOT / 'tools/arm64.py'), '-I', str(ROOT / 'src'),
                            '-D', 'MACOS', str(path), str(translated)], cwd=ROOT, check=True)
            command = ['as', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', str(obj), str(translated)]
        else:
            command = ['as', '--64', '-I', str(ROOT / 'src'), '-I', str(ROOT / 'build'), '-o', str(obj), str(path)]
        subprocess.run(command, cwd=ROOT, check=True)
        objects[relative] = obj
    excluded = {'src/main.s'}
    if mac or windows:
        excluded |= {'src/start.s', 'src/plat/wayland.s', 'src/plat/x11.s', 'src/plat/appearance.s'}
    inventory = [objects.pop('fixture.s')]
    for path in sorted((ROOT / 'src').rglob('*.s')):
        relative = path.relative_to(ROOT).as_posix()
        if relative in excluded or ('win' in path.parts and not windows) or ('mac' in path.parts and not mac):
            continue
        product = ROOT / ('build/windows' if windows else 'build/obj') / (
            relative.replace('/', '_') + '.obj' if windows else relative.replace('/', '_')[:-2] + '.o')
        inventory.append(objects.pop(relative, product))
    assert not objects, objects
    inventory.append(ROOT / ('build/windows/build_windows_assets.s.obj' if windows else 'build/obj/build_assets.o'))
    assert len(inventory) == len(set(inventory)) and all(p.is_file() for p in inventory), inventory
    executable = folder / ('ext_validate_fault_test.exe' if windows else 'ext_validate_fault_test')
    if windows:
        out = ROOT / 'build/windows'
        command = [linker, '/nodefaultlib', '/entry:win_start', '/subsystem:console,6.02',
                   '/stack:33554432,33554432', '/dynamicbase', '/nxcompat', '/largeaddressaware',
                   '/out:' + str(executable), *map(str, inventory), str(out / 'rhun.res'),
                   *[str(out / (p.stem + '.lib')) for p in sorted((ROOT / 'src/win').glob('*.def'))]]
    elif mac:
        command = ['clang', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-o', str(executable), *map(str, inventory)]
        for framework in ('AppKit', 'QuartzCore', 'IOSurface', 'CoreServices', 'Carbon'):
            command += ['-framework', framework]
    else:
        command = ['ld', '-static', '-nostdlib', '--no-dynamic-linker', '-z', 'noexecstack', '-o', str(executable), *map(str, inventory)]
    subprocess.run(command, cwd=ROOT, check=True)
    return executable


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--copy', type=Path)
    parser.add_argument('--integration-patch', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--windows', action='store_true')
    parser.add_argument('--root-fixture', action='store_true')
    args = parser.parse_args()
    if args.copy:
        destination = args.copy.resolve()
        assert destination != ROOT and not destination.exists(), destination
        shutil.copytree(ROOT, destination, ignore=shutil.ignore_patterns('.git', 'build', '__pycache__'))
        if args.integration_patch:
            subprocess.run(['git', 'apply', str(args.integration_patch.resolve())], cwd=destination, check=True)
        subprocess.run([sys.executable, 'tools/build-windows.py', 'test'] if args.windows else ['sh', 'build.sh', 'test'],
                       cwd=destination, check=True)
    else:
        assert args.output
        print(build(args.output.resolve(), args.windows, args.root_fixture))
