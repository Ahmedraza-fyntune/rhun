"""Shared harness of the contributions and commands tests (when.py, ext-command-args.py, ...):
fake extensions built from tests/ext/contrib.py with a manifest and per-command actions, run
headlessly with an isolated HOME (ext-host.py's Host)."""
import json
from pathlib import Path

host = __import__('ext-host')

ROOT = Path(__file__).resolve().parents[1]
PROGRAM = (ROOT / 'tests/ext/contrib.py').read_text(encoding='utf-8')


class Contrib(host.Host):
    def make_ext(self, root, owner='alice', name='demo', hello='hello 1', actions=None,
                 commands=('ping = Ping',), extra=''):
        """An extension folder ROOT/OWNER/NAME running tests/ext/contrib.py."""
        folder = root / owner / name
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'extension.ini').write_text(
            f'name = {name}\nowner = {owner}\ntitle = Demo\nversion = 1\nprotocol = 1\n'
            'runtime = python3\nrun = main.py\non = command\n[commands]\n' +
            ''.join(c + '\n' for c in commands) + extra, encoding='utf-8')
        header = 'HELLO = ' + json.dumps(hello) + '\nACTIONS = ' + repr(actions or {}) + '\n'
        (folder / 'main.py').write_text(header + PROGRAM, encoding='utf-8')
        return folder

    def contrib_log(self, owner='alice', name='demo'):
        path = self.work / f'state/rhun/extensions/{owner}--{name}/contrib.log'
        return path.read_text(encoding='utf-8').splitlines() if path.exists() else []


# the inherited Host tests are not run again here
for _name in dir(host.Host):
    if _name.startswith('test_'):
        setattr(Contrib, _name, None)
