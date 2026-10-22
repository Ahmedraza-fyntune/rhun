#!/usr/bin/env python3
"""Settings per workspace, folder and language (resources group, feature scoped-settings): the window
value a workspace's .rhun/extensions.ini sets, keys a project file may not set, values clamped,
setting-get's order (folder@LANG, folder, workspace@LANG, workspace, user@LANG, user, default),
"0 setting" and "0 setting-changed" when the file changes, the page's override line, and errors.
The fake extension is tests/ext/res.py."""
import subprocess
import time
import unittest

lifecycle = __import__('ext-lifecycle')
host = __import__('ext-host')
RES = lifecycle.RES

SETTINGS = ('[settings]\nstyle.type = choice\nstyle.options = gofmt goimports gofumpt\nstyle.default = gofmt\n'
            'style.scope = folder\nstyle.languages = yes\n'
            'tabs.type = int\ntabs.default = 4\ntabs.min = 1\ntabs.max = 16\ntabs.scope = workspace\n'
            'server.type = string\nserver.default = gopls\n')


class Scoped(lifecycle.Base):
    def setUp(self):
        super().setUp()
        self.root = self.work / 'exts'
        folder = self.root / 'rt' / 'set'
        folder.mkdir(parents=True)
        (folder / 'extension.ini').write_text(
            'name = set\nowner = rt\ntitle = Set\nversion = 1\nprotocol = 1\n'
            f'runtime = python3\nrun = {RES.as_posix()}\non = command\n'
            '[commands]\nrequest = Request\nbatch = Batch\n[needs]\nrun = python3\n' + SETTINGS, encoding='utf-8')
        self.state = self.work / 'state/rhun/extensions/rt--set'
        self.state.mkdir(parents=True)
        self.env['RES_ARGS'] = '{state}/args.txt'
        self.env['RES_LOG'] = '{state}/res.log'
        self.env['RES_FEATURES'] = 'scoped-settings'
        self.wsfile = self.proj / '.rhun/extensions.ini'
        self.wsfile.parent.mkdir()

    def user(self, text):
        (self.work / 'config/rhun/extensions.ini').write_text(text, encoding='utf-8')

    def ws(self, text):
        self.wsfile.write_text(text, encoding='utf-8')

    def run_set(self, lines, actions=(), cmd='batch', wait=800):
        (self.state / 'args.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
        log = self.state / 'res.log'
        if log.exists():
            log.unlink()
        return self.run_editor([f'cmd rt/set.{cmd}', 'wait-ext set running', f'wait {wait}', *actions],
                               exts=self.root, files=())

    def reslog(self):
        p = self.state / 'res.log'
        return p.read_text(errors='replace').splitlines() if p.exists() else []

    def settings(self):
        return [l for l in self.reslog() if l.startswith('0 setting ')]

    def gets(self):
        """the bodies of the setting-get answers, in order (None for an error)"""
        out = []
        lines = self.reslog()
        for i, l in enumerate(lines):
            if l.startswith('error '):
                out.append(l)
            elif l.startswith('ok ') and len(l.split(' ')) == 3:
                n = int(l.split(' ')[2])
                out.append(lines[i + 1][5:] if n else '')
        return out

    def test_the_workspace_sets_the_window_value(self):
        self.ws('[rt/set]\nsetting.style = goimports\nsetting.tabs = 99\nsetting.server = evil --run\n'
                '[rt/other]\nsetting.x = 1\n')
        out = self.run_set([], ['print-ext-setting rt/set server', 'print-ext-setting rt/set tabs'], cmd='request')
        s = self.settings()
        self.assertIn('0 setting style goimports', s)
        self.assertIn('0 setting tabs 16', s)           # clamped
        self.assertIn('0 setting server gopls', s)      # a user-scoped key: the project cannot set it
        self.assertIn('value=gopls window=gopls ignored=2', out)
        self.assertIn('value=16 window=16 ignored=2', out)

    def test_setting_get_order(self):
        self.user('[rt/set]\nsetting.style@Go = gofumpt\nsetting.tabs = 8\nsetting.server@Go = nope\n')
        self.run_set(['setting-get style 0 Go', 'setting-get style 0 -', 'setting-get style 1 Python',
                      'setting-get tabs 1 Go', 'setting-get server 0 Go'])
        self.assertEqual(self.gets(), ['gofumpt', 'gofmt', 'gofmt', '8', 'gopls'])
        self.ws('[rt/set]\nsetting.style@Go = goimports\nsetting.tabs = 2\n')
        self.run_set(['setting-get style 1 Go', 'setting-get style 1 -', 'setting-get style 1 Rust',
                      'setting-get tabs 0 -'])
        self.assertEqual(self.gets(), ['goimports', 'gofmt', 'gofmt', '2'])
        self.assertIn('0 setting tabs 2', self.settings())

    def test_errors_and_the_feature(self):
        self.run_set(['setting-get nope 0 -', 'setting-get style 7 -', 'setting-get style x -',
                      'setting-get style 0'])
        g = self.gets()
        self.assertEqual(g[0], 'error 1 refused not a setting of this extension')
        self.assertEqual(g[1], 'error 2 nofile no such folder')
        self.assertTrue(g[2].startswith('error 3 syntax') and g[3].startswith('error 4 syntax'), g)
        self.env['RES_FEATURES'] = ''
        self.run_set(['setting-get style 0 -'], cmd='request')
        self.assertEqual(self.gets(), ['error 1 unknown no such request'])

    def test_a_changed_file_is_told(self):
        self.ws('[rt/set]\nsetting.style = goimports\n')
        (self.state / 'args.txt').write_text('\n')
        script = self.work / 'a.rsc'
        script.write_text('\n'.join(['wait 100', 'cmd rt/set.request', 'wait-ext set running', 'wait 3500',
                                     'quit']) + '\n')
        p = subprocess.Popen([str(host.EXE), self.proj.as_posix(), '--headless', '1000x600', '--extensions',
                              str(self.root), '--script', str(script)], env=self.env, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE)
        end = time.time() + 10
        while time.time() < end and '0 setting style goimports' not in self.reslog():
            time.sleep(0.05)
        time.sleep(0.3)
        self.ws('[rt/set]\nsetting.style = gofumpt\nsetting.style@Go = goimports\n')
        p.communicate(timeout=30)
        log = self.reslog()
        self.assertIn('0 setting style gofumpt', log)
        i = log.index('0 setting style gofumpt')
        self.assertIn('0 setting-changed style', log[i:])
        self.assertNotIn('0 setting-changed tabs', log)

    def test_the_page_shows_the_override(self):
        self.ws('[rt/set]\nsetting.style = goimports\n')
        out = self.run_editor(['wait 300', 'ext-page rt/set', 'wait 200', 'print-ext-page'], exts=self.root,
                              files=())
        page = '\n'.join(out)
        self.assertIn('This workspace sets goimports (.rhun/extensions.ini)', page)


if __name__ == '__main__':
    unittest.main()
