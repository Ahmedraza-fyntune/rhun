#!/usr/bin/env python3
"""Write the winget manifests of a Windows release (package rhun.rhun, docs/windows-signing.md).

winget installs the release ZIP as a portable package and puts its rhun-VERSION folder on PATH
(ArchiveBinariesDependOnPath), so `rhun` finds rhun.com there as it does in an installer's folder,
and rhun.com finds rhun.exe beside it; a symlink in winget's Links folder would hide that folder.
usage: tools/winget-manifests.py ZIP OUT [--release-date YYYY-MM-DD] [--url URL]
(--url: where winget downloads the ZIP from in place of the release; tests/winget-install.py)
"""
import argparse
import datetime
import hashlib
import re
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent.parent
IDENTIFIER = 'rhun.rhun'
MANIFEST_VERSION = '1.10.0'


def scalar(value):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    text = str(value)
    # quoted when YAML would read it as something else
    if not text or text[0] in '!&*?|>%@`#,[]{}"\'-' or ': ' in text or ' #' in text or \
            text.lower() in ('yes', 'no', 'true', 'false', 'null', 'on', 'off') or re.fullmatch(r'[\d.]+', text) and text.count('.') < 2:
        return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'
    return text


def manifest(kind, fields):
    """A manifest's YAML: scalars, lists of scalars, lists of flat mappings, flat mappings"""
    lines = [f'# yaml-language-server: $schema=https://aka.ms/winget-manifest.{kind}.{MANIFEST_VERSION}.schema.json', '']
    for key, value in fields.items():
        if isinstance(value, list):
            lines.append(f'{key}:')
            for item in value:
                if isinstance(item, dict):
                    lines += [('- ' if i == 0 else '  ') + f'{k}: {scalar(v)}' for i, (k, v) in enumerate(item.items())]
                else:
                    lines.append(f'- {scalar(item)}')
        elif isinstance(value, dict):
            lines.append(f'{key}:')
            lines += [f'  {k}: {scalar(v)}' for k, v in value.items()]
        else:
            lines.append(f'{key}: {scalar(value)}')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('zip', type=Path)
    parser.add_argument('out', type=Path)
    parser.add_argument('--release-date', default=datetime.date.today().isoformat())
    parser.add_argument('--url')
    args = parser.parse_args()
    version = (ROOT / 'VERSION').read_text(encoding='utf-8').strip()
    asset = f'rhun-{version}-windows-x86_64.zip'
    if args.zip.name != asset:
        raise SystemExit(f'{args.zip} is not {asset}')
    folder = f'rhun-{version}'
    with zipfile.ZipFile(args.zip) as archive:
        names = set(archive.namelist())
    for name in ('rhun.com', 'rhun.exe'):
        if f'{folder}/{name}' not in names:
            raise SystemExit(f'{args.zip} has no {folder}/{name}')
    sha256 = hashlib.sha256(args.zip.read_bytes()).hexdigest().upper()
    common = {'PackageIdentifier': IDENTIFIER, 'PackageVersion': version}
    files = {
        f'{IDENTIFIER}.yaml': manifest('version', {
            **common, 'DefaultLocale': 'en-US', 'ManifestType': 'version', 'ManifestVersion': MANIFEST_VERSION}),
        f'{IDENTIFIER}.installer.yaml': manifest('installer', {
            **common,
            'InstallerLocale': 'en-US',
            'MinimumOSVersion': '10.0.17763.0',
            'InstallerType': 'zip',
            'NestedInstallerType': 'portable',
            # winget takes only an .exe here; with the folder on PATH, `rhun` is rhun.com all the same
            'NestedInstallerFiles': [{'RelativeFilePath': f'{folder}/rhun.exe'}],
            'ArchiveBinariesDependOnPath': True,
            # rhun.rhun-VERSION folders: an upgrade removes the previous one and its PATH entry
            'UpgradeBehavior': 'uninstallPrevious',
            'Commands': ['rhun'],
            'ReleaseDate': args.release_date,
            'Installers': [{
                'Architecture': 'x64',
                'InstallerUrl': args.url or f'https://github.com/vshvedov/rhun/releases/download/v{version}/{asset}',
                'InstallerSha256': sha256,
            }],
            'ManifestType': 'installer', 'ManifestVersion': MANIFEST_VERSION}),
        f'{IDENTIFIER}.locale.en-US.yaml': manifest('defaultLocale', {
            **common,
            'PackageLocale': 'en-US',
            'Publisher': 'rhun',
            'PublisherUrl': 'https://rhun.app/',
            'PublisherSupportUrl': 'https://github.com/vshvedov/rhun/issues',
            'PrivacyUrl': 'https://rhun.app/code-signing/#privacy',
            'Author': 'Vlad Shvedov',
            'PackageName': 'rhun',
            'PackageUrl': 'https://rhun.app/',
            'License': 'MIT',
            'LicenseUrl': 'https://github.com/vshvedov/rhun/blob/main/LICENSE',
            'Copyright': next(line for line in (ROOT / 'LICENSE').read_text(encoding='utf-8').splitlines()
                              if line.startswith('Copyright')),
            'ShortDescription': 'A small, fast code editor written in assembly.',
            'Description': ('A small, very fast code editor for Windows, Linux and macOS, written in assembly. '
                            'Tabs, syntax highlighting, a built-in terminal, Git history and diffs, fuzzy search, '
                            'Vim mode, extensions and an agents panel.'),
            'Moniker': 'rhun',
            'Tags': ['code-editor', 'editor', 'text-editor', 'assembly', 'git', 'terminal', 'vim'],
            'ReleaseNotesUrl': f'https://github.com/vshvedov/rhun/releases/tag/v{version}',
            'Documentations': [{'DocumentLabel': 'Guides', 'DocumentUrl': 'https://rhun.app/docs/'}],
            'ManifestType': 'defaultLocale', 'ManifestVersion': MANIFEST_VERSION}),
    }
    out = args.out / 'manifests' / IDENTIFIER[0] / Path(*IDENTIFIER.split('.')) / version
    out.mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        (out / name).write_text(text, encoding='utf-8', newline='\n')
    print(out)


if __name__ == '__main__':
    main()
