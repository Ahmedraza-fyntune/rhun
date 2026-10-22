"""Releases for the extension management tests: a tree laid out as GitHub's releases, and a local
HTTP server that answers as github.com does (tests/ext-updates.py, ext-browse.py, ...).

  /O/N/releases/latest                 302 to /O/N/releases/tag/TAG (the latest set for O/N)
  /O/N/releases/latest/download/F      302 to /O/N/releases/download/TAG/F
  /O/N/releases/download/TAG/F         the file
  a repository without releases        /O/N/releases/latest is 302 to /O/N/releases
  a moved repository                   /O/N/... is 301 to /NEW_O/NEW_N/...

The same tree works as a file:// base for exact tags (BASE/O/N/releases/download/TAG/F) and, after
publish(..., latest=True), for releases/latest/download too."""
import hashlib
import http.server
import io
import os
from pathlib import Path
import shutil
import sys
import tarfile
import threading
import urllib.parse

TARGET = 'windows-x64' if os.name == 'nt' else 'macos-arm64' if sys.platform == 'darwin' else 'linux-x86_64'
OTHER_TARGETS = [t for t in ('linux-x86_64', 'macos-arm64', 'windows-x64') if t != TARGET]


def archive(files, link=None, big=0):
    """A .tar.gz of {name: text or bytes}; link=(name, target) adds a symbolic link; big=N adds a
    file of N zero bytes (it compresses to almost nothing)."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w:gz') as tar:
        for name, text in files.items():
            data = text.encode() if isinstance(text, str) else text
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o755 if name.endswith(('.py', '.sh')) or '.' not in name else 0o644
            tar.addfile(info, io.BytesIO(data))
        if big:
            info = tarfile.TarInfo('big.bin')
            info.size = big
            info.mode = 0o644

            class Zeros(io.RawIOBase):
                left = big

                def readable(self):
                    return True

                def readinto(self, b):
                    n = min(len(b), self.left)
                    b[:n] = bytes(n)
                    self.left -= n
                    return n
            tar.addfile(info, io.BufferedReader(Zeros()))
        if link:
            info = tarfile.TarInfo(link[0])
            info.type = tarfile.SYMTYPE
            info.linkname = link[1]
            tar.addfile(info)
    return buf.getvalue()


def sha(data):
    return hashlib.sha256(data).hexdigest()


class Releases:
    """A release tree under root: publish() adds a tagged release of an extension."""

    def __init__(self, root):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.latest = {}            # 'o/n' -> tag
        self.moved = {}             # 'o/n' -> 'o2/n2'
        self.digests = {}           # ('o/n', tag) -> {target: sha256}

    def publish(self, owner, name, files, tag, latest=True, bad_sum=False, targets=None, link=None, big=0):
        """The release TAG of owner/name: an archive of files per target (this system's, unless
        targets names others), with sha256sums.txt. Returns this system's archive digest."""
        d = self.root / owner / name / 'releases/download' / tag
        d.mkdir(parents=True, exist_ok=True)
        sums, digests = [], {}
        for target in targets or [TARGET]:
            data = archive(files, link, big)
            asset = '%s-%s.tar.gz' % (name, target)
            (d / asset).write_bytes(data)
            digests[target] = sha(data)
            sums.append('%s  %s\n' % (sha(data + (b'x' if bad_sum else b'')), asset))
        (d / 'sha256sums.txt').write_text(''.join(sums), encoding='utf-8')
        self.digests[(owner + '/' + name, tag)] = digests
        if latest:
            self.set_latest(owner, name, tag)
        return digests.get(TARGET)

    def set_latest(self, owner, name, tag):
        """tag becomes the latest release (also copied to releases/latest/download for file://)."""
        self.latest[owner + '/' + name] = tag
        src = self.root / owner / name / 'releases/download' / tag
        dst = self.root / owner / name / 'releases/latest/download'
        if dst.exists():
            shutil.rmtree(dst)
        if src.exists():
            shutil.copytree(src, dst)

    def tamper(self, owner, name, tag, target=TARGET):
        """The archive changes after the index pinned it; its sums are rewritten to match."""
        d = self.root / owner / name / 'releases/download' / tag
        asset = '%s-%s.tar.gz' % (name, target)
        with tarfile.open(fileobj=io.BytesIO((d / asset).read_bytes()), mode='r:gz') as tar:
            files = {m.name: tar.extractfile(m).read() for m in tar.getmembers() if m.isfile()}
        files['tampered.txt'] = b'changed after review\n'
        data = archive(files)
        (d / asset).write_bytes(data)
        (d / 'sha256sums.txt').write_text('%s  %s\n' % (sha(data), asset), encoding='utf-8')
        if self.latest.get(owner + '/' + name) == tag:
            self.set_latest(owner, name, tag)

    def index(self, entries, tag='v1', fmt=1, sums_ok=True):
        """rhun-editor/extensions' release: index.ini from {'o/n': {key: value}} and its sums."""
        lines = ['# rhun extension index, generated for the tests; do not edit', 'format = %d' % fmt,
                 'generated = 2026-10-19T08:00:00Z', '']
        for full, keys in entries.items():
            lines.append('[%s]' % full)
            lines += ['%s = %s' % kv for kv in keys.items()]
            lines.append('')
        data = '\n'.join(lines).encode()
        d = self.root / 'rhun-editor/extensions/releases/download' / tag
        d.mkdir(parents=True, exist_ok=True)
        (d / 'index.ini').write_bytes(data)
        (d / 'sha256sums.txt').write_text('%s  index.ini\n' % sha(data + (b'' if sums_ok else b'x')),
                                          encoding='utf-8')
        self.set_latest('rhun-editor', 'extensions', tag)
        return data

    def entry(self, owner, name, tag, title, version=None, needs='', **more):
        """An index entry pinning owner/name at tag, with the digests publish() recorded."""
        e = {'title': title, 'description': more.pop('description', title + ' for the tests.'),
             'version': version or tag.lstrip('v'), 'tag': tag}
        for target, digest in self.digests.get((owner + '/' + name, tag), {}).items():
            e['sha256.' + target] = digest
        if needs:
            e['needs'] = needs
        e.update(more)
        return e


class Server:
    """GitHub's answers for a Releases tree, on 127.0.0.1 (use as a context manager)."""

    def __init__(self, releases):
        self.releases = releases
        rel = releases

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_HEAD(self):
                self.do_GET(body=False)

            def do_GET(self, body=True):
                path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
                parts = [p for p in path.split('/') if p]
                base = 'http://%s:%d' % self.server.server_address[:2]
                if len(parts) >= 2:
                    full = parts[0] + '/' + parts[1]
                    if full in rel.moved:
                        return self.redirect(301, base + '/' + rel.moved[full] + '/' + '/'.join(parts[2:]))
                    if parts[2:4] == ['releases', 'latest']:
                        tag = rel.latest.get(full)
                        if tag is None:
                            return self.redirect(302, base + '/' + full + '/releases')
                        if len(parts) == 4:
                            return self.redirect(302, base + '/' + full + '/releases/tag/' + tag)
                        if parts[4] == 'download' and len(parts) == 6:
                            return self.redirect(302, base + '/' + full + '/releases/download/' + tag + '/' + parts[5])
                    if parts[2:4] == ['releases', 'download'] and len(parts) == 6:
                        f = rel.root.joinpath(*parts)
                        if f.is_file():
                            data = f.read_bytes()
                            self.send_response(200)
                            self.send_header('Content-Length', str(len(data)))
                            self.end_headers()
                            if body:
                                self.wfile.write(data)
                            return
                    if parts[2:] in (['releases'],) or (parts[2:3] == ['releases'] and parts[3:4] == ['tag']):
                        self.send_response(200)
                        self.send_header('Content-Length', '0')
                        self.end_headers()
                        return
                self.send_response(404)
                self.send_header('Content-Length', '0')
                self.end_headers()

            def redirect(self, code, location):
                self.send_response(code)
                self.send_header('Location', location)
                self.send_header('Content-Length', '0')
                self.end_headers()

        self.httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)

    @property
    def url(self):
        return 'http://127.0.0.1:%d' % self.httpd.server_address[1]

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.httpd.shutdown()
        self.httpd.server_close()
