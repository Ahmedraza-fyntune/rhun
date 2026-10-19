#!/usr/bin/env python3
"""URIs and virtual documents (resources group): open with a URI of a scheme an extension
provides, the content request and its answer (language, title, text), read-only tabs, opened
events only to extensions that agreed uris, content-changed reloads that keep the cursor,
errors, timeouts and Reload File, content-closed, a provider that starts on demand, file: URIs,
unknown and reserved schemes. The fake extension is tests/ext/res.py."""
import os
from pathlib import Path
import re
import shutil
import unittest

lifecycle = __import__('ext-lifecycle')
RES = lifecycle.RES

URI = 'res-gen:/x/hello.txt'


class Vdoc(lifecycle.Base):
    def setUp(self):
        super().setUp()
        self.root = self.work / 'exts'

    def ext(self, name, features='uris', extra='', on='command', schemes='res-gen'):
        folder = self.root / 'rt' / name
        folder.mkdir(parents=True, exist_ok=True)
        provides = f'[provides]\nschemes = {schemes}\n' if schemes else ''
        (folder / 'extension.ini').write_text(
            f'name = {name}\nowner = rt\ntitle = {name.title()}\nversion = 1\nprotocol = 1\n'
            f'runtime = python3\nrun = {RES.as_posix()}\non = {on}\n{extra}'
            '[commands]\nrequest = Request\nbatch = Batch\nping = Ping\n'
            f'[needs]\nrun = python3\ndocuments = read\nproject = read\n{provides}'
            '[subscribe]\nopened = *\n', encoding='utf-8')
        state = self.work / f'state/rhun/extensions/rt--{name}'
        state.mkdir(parents=True, exist_ok=True)
        return state

    def run_res(self, name, lines, actions, features='uris', env=None, files=('a.txt',)):
        """RES_ARGS lines for the extension `name`; its features; then the actions"""
        state = self.work / f'state/rhun/extensions/rt--{name}'
        (state / 'args.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
        self.env['RES_ARGS'] = '{state}/args.txt'
        self.env['RES_LOG'] = '{state}/res.log'
        self.env['RES_FEATURES'] = features
        self.env.update(env or {})
        return self.run_editor(actions, exts=self.root, files=files)

    def reslog(self, name):
        p = self.work / f'state/rhun/extensions/rt--{name}/res.log'
        return p.read_text(errors='replace').splitlines() if p.exists() else []

    def vdocs(self, out):
        return [dict(x.split('=', 1) for x in l.split()[1:]) for l in out if l.startswith('vdoc ')]

    def test_open_a_uri(self):
        self.ext('gen')
        out = self.run_res('gen', [f'open 3 2 {URI}'], [
            'cmd rt/gen.request', 'wait-ext gen running', 'wait 400', 'print-vdocs', 'print-tabs',
            'print-state', 'print-doc', 'type zz', 'key ctrl+End', 'print-state'])
        v = self.vdocs(out)
        self.assertEqual(len(v), 1, out)
        self.assertEqual(v[0]['uri'], URI)
        self.assertEqual(v[0]['state'], 'loaded')
        self.assertEqual(v[0]['provider'], 'rt/gen')
        self.assertEqual(v[0]['name'], 'hello.txt')
        self.assertTrue(any(l.startswith('tabs=') and '*hello.txt' in l for l in out), out)
        self.assertIn('content 1 of res-gen:/x/hello.txt', '\n'.join(out))
        self.assertTrue(any(' dirty=0' in l for l in out if l.startswith('tabs=') or 'dirty=' in l))
        log = self.reslog('gen')
        self.assertTrue(any(re.fullmatch(r'\d+ content res-gen:/x/hello\.txt', x) for x in log), log)
        doc = v[0]['doc']
        self.assertTrue(any(re.fullmatch(rf'ok 1 {doc}', x) for x in log), log)
        self.assertTrue(any(re.fullmatch(rf'0 opened {doc} \d+ \S+ res-gen:/x/hello\.txt', x) for x in log), log)

    def test_language_title_and_readonly(self):
        self.ext('gen')
        out = self.run_res('gen', [f'open 0 0 {URI}'], [
            'cmd rt/gen.request', 'wait-ext gen running', 'wait 400', 'print-vdocs', 'print-state'],
            env={'RES_VDOC': 'Go|main.go-HEAD'})
        v = self.vdocs(out)
        self.assertEqual(v[0]['name'], 'main.go-HEAD')
        self.assertIn('lang=Go', '\n'.join(out))

    def test_opened_only_to_uris_peers(self):
        self.ext('gen')
        self.ext('plain', schemes='')
        self.env['RES_FEATURES_plain'] = ''
        out = self.run_res('gen', [f'open 0 0 {URI}'], [
            'cmd rt/plain.ping', 'wait-ext plain running', 'cmd rt/gen.request', 'wait-ext gen running',
            'wait 500', 'print-vdocs'])
        doc = self.vdocs(out)[0]['doc']
        plain = self.reslog('plain')
        self.assertFalse(any(x.startswith(f'0 opened {doc} ') for x in plain), plain)
        self.assertTrue(any(x.startswith('0 opened ') for x in plain), plain)   # a.txt it sees

    def test_content_changed_reloads_and_keeps_the_cursor(self):
        self.ext('gen')
        out = self.run_res('gen', [f'open 2 3 {URI}', f'content-changed {URI}'], [
            'cmd rt/gen.request', 'wait-ext gen running', 'wait 400', 'print-state',
            'cmd rt/gen.request', 'wait 400', 'print-state', 'print-doc'])
        states = [l for l in out if ' line=' in l]
        self.assertIn('line=2 col=3', states[0])
        self.assertIn('line=2 col=3', states[1])
        self.assertIn('content 2 of res-gen:/x/hello.txt', '\n'.join(out))

    def test_errors_and_reload_file(self):
        self.ext('gen')
        out = self.run_res('gen', [f'open 0 0 {URI}'], [
            'cmd rt/gen.request', 'wait-ext gen running', 'wait 400', 'print-vdocs', 'print-doc'],
            env={'RES_VDOC_MODE': 'error'})
        self.assertEqual(self.vdocs(out)[0]['state'], 'error')
        self.assertIn('This document could not be read from rt/gen: nofile no such revision.',
                      '\n'.join(out))
        out = self.run_res('gen', [f'open 0 0 {URI}'], [
            'cmd rt/gen.request', 'wait-ext gen running', 'wait 400', 'print-vdocs'],
            env={'RES_VDOC_MODE': 'bad'})
        self.assertEqual(self.vdocs(out)[0]['state'], 'error')

    def test_timeout_then_reload_file(self):
        self.ext('gen')
        out = self.run_res('gen', [f'open 0 0 {URI}'], [
            'cmd rt/gen.request', 'wait-ext gen running', 'wait 300', 'print-vdocs', 'wait 5500',
            'print-vdocs', 'print-doc', 'cmd reload_file', 'wait 300', 'print-vdocs'],
            env={'RES_VDOC_MODE': 'slow'})
        states = [v['state'] for v in self.vdocs(out)]
        self.assertEqual(states, ['loading', 'error', 'loading'], out)
        self.assertIn('no answer within 5 seconds', '\n'.join(out))
        log = self.reslog('gen')
        self.assertTrue(any(x.startswith('0 cancel ') for x in log), log)
        self.assertEqual(sum(1 for x in log if ' content res-gen:' in x), 2, log)

    def test_closing_the_tab_says_content_closed(self):
        self.ext('gen')
        self.run_res('gen', [f'open 0 0 {URI}'], [
            'cmd rt/gen.request', 'wait-ext gen running', 'wait 400', 'cmd close_tab', 'wait 300'])
        self.assertIn(f'0 content-closed {URI}', self.reslog('gen'))

    def test_a_provider_starts_on_demand(self):
        self.ext('gen', features='uris')                  # provides res-gen, not started
        self.ext('opener', schemes='')
        out = self.run_res('opener', [f'open 0 0 {URI}'], [
            'cmd rt/opener.request', 'wait-ext opener running', 'wait 1500', 'print-vdocs',
            'print-extensions'])
        v = self.vdocs(out)
        self.assertEqual(v[0]['state'], 'loaded', out)
        self.assertEqual(v[0]['provider'], 'rt/gen')
        self.assertTrue(any(l.startswith('rt/gen state=running') for l in out), out)

    def test_file_uris_unknown_and_reserved_schemes(self):
        self.ext('gen')
        path = (self.proj / 'b.go').as_posix()
        lines = [f'open 1 1 file://{path}', 'open 0 0 nope-x:/a', 'open 0 0 http://example.com/a',
                 'open 0 0 file://otherhost/x', 'open 0 0 C:x']
        out = self.run_res('gen', lines, ['cmd rt/gen.batch', 'wait-ext gen running', 'wait 500',
                                          'print-tabs', 'print-vdocs'])
        log = [x for x in self.reslog('gen') if x.startswith(('ok ', 'error '))]
        self.assertTrue(re.fullmatch(r'ok 1 \d+', log[0]), log)
        self.assertEqual(log[1], 'error 2 nofile no such file')
        self.assertEqual(log[2], 'error 3 nofile no such file')
        self.assertEqual(log[3], 'error 4 nofile no such file')
        self.assertTrue(log[4].startswith('error 5 '), log)
        self.assertTrue(any('b.go' in l for l in out if l.startswith('tabs=')), out)
        self.assertEqual(self.vdocs(out), [])

    def test_without_uris_a_uri_is_a_relative_path(self):
        self.ext('gen', features='')
        self.run_res('gen', [f'open 0 0 {URI}'], ['cmd rt/gen.request', 'wait-ext gen running',
                                                  'wait 300'], features='')
        self.assertIn('error 1 nofile no such file', self.reslog('gen'))

    def test_visual(self):
        self.ext('gen')
        shot = self.work / 'vdoc.ppm'
        self.run_res('gen', [f'open 0 0 {URI}'], ['cmd rt/gen.request', 'wait-ext gen running',
                                                  'wait 400', f'shot {shot.as_posix()}'],
                     env={'RES_VDOC': 'Go|main.go @ HEAD'})
        if os.environ.get('RES_SHOTS'):
            shutil.copy(shot, os.environ['RES_SHOTS'] + '/vdoc.ppm')


if __name__ == '__main__':
    unittest.main()
