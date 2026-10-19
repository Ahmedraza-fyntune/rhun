#!/usr/bin/env python3
"""Development installs (docs/guide.md, "Managing extensions"): Install from Folder copies a folder
holding extension.ini through the install job (links refused), Link a Folder leaves a stub with
only the install record and runs the extension from the folder (rebuild + Restart runs the new
program; Remove leaves the folder), Install from Archive takes a release .tar.gz and checks the
sha256sums.txt beside it when there is one, and a link over a GitHub install rolls back to it."""
import hashlib
import os
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
host = __import__('ext-host')
updates = __import__('ext-updates')
import extrel  # noqa: E402

SAYS = r'''import sys
out = sys.stdout
out.write('hello 1\n'); out.flush()
versions = {}
for line in sys.stdin:
    f = line.rstrip('\n').split(' ')
    if f[:2] in (['0', 'opened'], ['0', 'changed']):
        versions[f[2]] = f[3]
    elif f[:2] == ['0', 'run']:
        doc = f[3]
        out.write('1 insert %s %s 4\nWORD' % (doc, versions.get(doc, '0'))); out.flush()
    elif f[:2] == ['0', 'bye']:
        break
'''


def says(word):
    return SAYS.replace('4\\nWORD', '%d\\n%s' % (len(word), word))


class DevInstall(updates.Updates):
    def folder(self, version='0.2.0', word='one', link=False):
        d = self.work / 'dev hello'
        d.mkdir(exist_ok=True)
        for name, text in updates.files(version, main=says(word)).items():
            (d / name).write_text(text, encoding='utf-8')
        if link:
            os.symlink('/etc/hosts', d / 'evil')
        return d

    def test_a_copied_folder_is_installed_like_a_release(self):
        d = self.folder()
        out = self.ui(['ext-install-folder %s copy' % d.as_posix(), 'wait-install', 'print-dialog', 'dialog yes',
                       'wait-ext hello running', 'print-ext-versions demo/hello'])
        self.assertEqual(out[1], 'dialog=Add “Hello”?')
        self.assertEqual(out[2], 'text=Version 0.2.0 from the folder %s. It can read and change the files you have '
                                 'open.' % d.as_posix())
        self.assertIn('version=0.2.0 source=folder tag=- previous=- link=no fresh=0', out)
        self.assertTrue((self.exts / 'demo/hello/main.py').exists())
        rec = self.record()
        self.assertEqual(rec['path'], d.as_posix())
        self.assertEqual(len(rec['sha256']), 64)

    def test_a_folder_with_a_link_is_refused(self):
        if os.name == 'nt':
            self.skipTest('symbolic links need privileges on Windows')
        d = self.folder(link=True)
        out = self.ui(['ext-install-folder %s' % d.as_posix(), 'wait-install', 'print-toast'])
        self.assertEqual(out[0], 'install=failed')
        self.assertEqual(out[1], 'toast=Could not install dev hello: the folder holds links or devices')

    def test_a_linked_folder_runs_from_there_and_restart_runs_the_rebuilt_program(self):
        d = self.folder(word='one')
        out = self.ui(['ext-install-folder %s link' % d.as_posix(), 'wait-install', 'print-dialog', 'dialog yes',
                       'wait-ext hello running', 'print-ext-versions demo/hello', 'cmd hello.say', 'wait 300',
                       'wait 300', 'print-doc'])
        self.assertEqual(out[2], 'text=Version 0.2.0, linked to the folder %s (development). It can read and change '
                                 'the files you have open.' % d.as_posix())
        self.assertIn('version=0.2.0 source=folder tag=- previous=- link=yes fresh=0', out)
        self.assertTrue(any(l.startswith('onehello') for l in out), out)
        self.assertEqual(sorted(p.name for p in (self.exts / 'demo/hello').iterdir()), ['.rhun-install'])
        (d / 'main.py').write_text(says('two'), encoding='utf-8')
        out = self.ui(['wait-ext hello running', 'ext-set hello restart', 'wait-ext hello running', 'cmd hello.say',
                       'wait 300', 'wait 300', 'print-doc'])
        self.assertTrue(any(l.startswith('twohello') for l in out), out)
        out = self.ui(['ext-remove hello', 'print-dialog', 'dialog yes'])
        self.assertIn('text=Its settings and the data it saved go too. Its folder %s stays.' % d.as_posix(), out)
        self.assertFalse((self.exts / 'demo/hello').exists())
        self.assertTrue((d / 'main.py').exists())

    def test_an_archive_installs_with_and_without_its_sums(self):
        d = self.work / 'dist'
        d.mkdir()
        data = extrel.archive(updates.files('0.3.0'))
        (d / 'hello.tar.gz').write_bytes(data)
        out = self.ui(['ext-install-archive %s' % (d / 'hello.tar.gz').as_posix(), 'wait-install', 'print-dialog',
                       'dialog yes', 'wait-ext hello running', 'print-ext-versions demo/hello'])
        self.assertEqual(out[2], 'text=Version 0.3.0 from the archive %s. It can read and change the files you have '
                                 'open.' % (d / 'hello.tar.gz').as_posix())
        self.assertIn('version=0.3.0 source=archive tag=- previous=- link=no fresh=0', out)
        self.assertEqual(self.record()['sha256'], hashlib.sha256(data).hexdigest())
        (d / 'sha256sums.txt').write_text('%s  hello.tar.gz\n' % ('0' * 64), encoding='utf-8')
        out = self.ui(['ext-install-archive %s' % (d / 'hello.tar.gz').as_posix(), 'wait-install', 'print-toast'])
        self.assertEqual(out[1], 'toast=Could not install hello.tar.gz: the download does not match its checksum')
        (d / 'sha256sums.txt').write_text('%s  other.tar.gz\n' % ('0' * 64), encoding='utf-8')
        out = self.ui(['ext-install-archive %s' % (d / 'hello.tar.gz').as_posix(), 'wait-install', 'print-toast'])
        self.assertEqual(out[1], 'toast=Could not install hello.tar.gz: the sha256sums.txt beside it does not list '
                                 'hello.tar.gz')
        (d / 'sha256sums.txt').write_text('%s  hello.tar.gz\n' % hashlib.sha256(data).hexdigest(), encoding='utf-8')
        out = self.ui(['ext-install-archive ~/dist/hello.tar.gz', 'wait-install', 'print-dialog', 'dialog no'])
        self.assertEqual(out[0], 'install=asking')

    def test_a_link_over_a_github_install_rolls_back_to_the_release(self):
        self.rel.publish('demo', 'hello', updates.files('0.1.0'), 'v0.1.0')
        self.install('demo/hello@0.1.0')
        d = self.folder()
        out = self.ui(['ext-install-folder %s link' % d.as_posix(), 'wait-install', 'dialog yes',
                       'wait-ext hello running', 'print-ext-versions demo/hello', 'ext-rollback demo/hello',
                       'wait-ext hello running', 'print-ext-versions demo/hello'])
        self.assertIn('version=0.2.0 source=folder tag=- previous=0.1.0 link=yes fresh=0', out)
        self.assertIn('version=0.1.0 source=github tag=v0.1.0 previous=0.2.0 link=no fresh=0', out)
        out = self.ui(['wait-ext hello running', 'ext-rollback demo/hello', 'wait-ext hello running',
                       'print-ext-versions demo/hello'])
        self.assertIn('version=0.2.0 source=folder tag=- previous=0.1.0 link=yes fresh=0', out)


for _name in dir(host.Host):
    if _name.startswith('test_'):
        setattr(DevInstall, _name, None)
for _name in dir(updates.Updates):
    if _name.startswith('test_'):
        setattr(DevInstall, _name, None)

if __name__ == '__main__':
    unittest.main()
