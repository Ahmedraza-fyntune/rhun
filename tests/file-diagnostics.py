#!/usr/bin/env python3
"""file-diagnostics (docs/extensions/v1.1.md): an extension's diagnostics for open documents and
files that are not open go into the Problems store; a new set replaces the target's; stale
versions and modified documents are refused; reset and stopping remove them; ids reach code
actions as DIAGS."""
import unittest

lang = __import__('langfeat-query')


def diag(l1, c1, l2, c2, sev, msg, extra=''):
    return f'{l1} {c1} {l2} {c2} {sev} {len(msg.encode())} {len(extra.encode())}\n{msg}{extra}'


def rec(name, body='', args=''):
    b = body.encode()
    return (f'{name} {args} {len(b)}' if args else f'{name} {len(b)}') + '\n' + body


def fdiag(target, version, diags):
    body = target + ''.join(diags)
    return f'file-diagnostics {version} {len(diags)} {len(target.encode())} {len(body.encode())}', body


class FileDiagnostics(lang.Lang):
    def setUp(self):
        super().setUp()
        (self.proj / 'other.rs').write_text('fn other() {}\nfn more() {}\n')

    def spec(self, run, hello='hello 1 file-diagnostics code-actions'):
        return {'hello': hello, 'run': run, 'answers': {'code-actions': {'body': '0\n'}}}

    def manifest(self, cmds):
        return '[commands]\n' + ''.join(f'{c} = {c}\n' for c in cmds)

    def problems(self, out):
        return [l for l in out if l.startswith('problem ')]

    def test_open_and_unopened_files(self):
        other = str(self.proj / 'other.rs')
        d1 = fdiag('#1', 0, [diag(2, 9, 2, 14, 'warning', 'unused total', rec('id', 'd1') + rec('code', 'W1') + rec('source', 'lint'))])
        d2 = fdiag(other, '-', [diag(1, 4, 1, 9, 'error', 'bad\nname')])
        root = self.provider(self.spec({'one': [list(d1)], 'two': [list(d2)]}), 'actions = *.rs\n',
                             extra=self.manifest(['one', 'two']))
        out = self.run_lang(root, ['cmd lang.one', 'cmd lang.two', 'wait 300', 'print-file-diagnostics', 'print-marks',
                                   'open ' + other, 'wait 300', 'print-state', 'print-marks'])
        p = self.problems(out)
        self.assertTrue(any('line=2 col=9 end=2:14 severity=warning code=lint(W1) source=fake/lang message=unused total' in l for l in p), out)
        self.assertTrue(any('other.rs line=1 col=4 end=1:9 severity=error' in l for l in p), out)
        marks = [l for l in out if l.startswith('2 9 2 14 warning') or l.startswith('1 4 1 9 error')]
        self.assertEqual(len(marks), 2, out)
        log = self.lang_log()
        self.assertIn('ok 1', log)
        self.assertIn('ok 2', log)

    def test_related_records_carry_a_path_and_a_message(self):
        other = str(self.proj / 'other.rs')
        rel = f'related 1 4 1 9 {len(other.encode())} 9\n{other}first use'
        d = fdiag('#1', 0, [diag(2, 9, 2, 14, 'warning', 'moved here', rel + rec('tag', '', 'unnecessary'))])
        root = self.provider(self.spec({'one': [list(d)]}), 'actions = *.rs\n', extra=self.manifest(['one']))
        out = self.run_lang(root, ['cmd lang.one', 'wait 300', 'print-file-diagnostics'])
        self.assertIn('ok 1', self.lang_log())
        self.assertTrue(any('message=moved here' in l for l in self.problems(out)), out)

    def test_a_new_set_replaces_and_reset_clears(self):
        a = fdiag('#1', 0, [diag(1, 1, 1, 3, 'error', 'first'), diag(2, 1, 2, 3, 'error', 'second')])
        b = fdiag('#1', 0, [diag(3, 1, 3, 3, 'info', 'third')])
        root = self.provider(self.spec({'a': [list(a)], 'b': [list(b)], 'reset': [['file-diagnostics-reset', '']]}),
                             'actions = *.rs\n', extra=self.manifest(['a', 'b', 'reset']))
        out = self.run_lang(root, ['cmd lang.a', 'wait 200', 'echo ---', 'print-file-diagnostics', 'cmd lang.b', 'wait 200',
                                   'echo ---', 'print-file-diagnostics', 'cmd lang.reset', 'wait 200', 'echo ---',
                                   'print-file-diagnostics', 'print-marks'])
        parts = '\n'.join(out).split('---')
        self.assertEqual(parts[1].count('problem '), 2, out)
        self.assertEqual(parts[2].count('problem '), 1, out)
        self.assertIn('message=third', parts[2])
        self.assertEqual(parts[3].count('problem '), 0, out)
        self.assertIn('errors=0 warnings=0', parts[3])

    def test_stale_versions_and_modified_documents_are_refused(self):
        a = fdiag('#1', 7, [diag(1, 1, 1, 3, 'error', 'x')])
        b = fdiag(str(self.proj / 'a.rs'), '-', [diag(1, 1, 1, 3, 'error', 'x')])
        bad = fdiag('#1', 0, [diag(1, 1, 1, 3, 'fatal', 'x')])
        root = self.provider(self.spec({'a': [list(a)], 'b': [list(b)], 'bad': [list(bad)]}), 'actions = *.rs\n',
                             extra=self.manifest(['a', 'b', 'bad']))
        out = self.run_lang(root, ['cmd lang.a', 'cmd lang.bad', 'wait 200', 'type x', 'cmd lang.b', 'wait 300',
                                   'print-file-diagnostics'])
        log = self.lang_log()
        self.assertIn('error 1 stale 0', log)
        self.assertTrue(any(l.startswith('error 2 syntax') for l in log), log)
        self.assertTrue(any(l.startswith('error 3 stale ') for l in log), log)
        self.assertEqual(self.problems(out), [])

    def test_a_file_outside_its_reach_needs_permission(self):
        outside = self.work / 'secret.rs'
        outside.write_text('x\n')
        a = fdiag(str(outside), '-', [diag(1, 1, 1, 2, 'error', 'x')])
        root = self.provider(self.spec({'a': [list(a)]}), 'actions = *.rs\n', extra=self.manifest(['a']))
        self.run_lang(root, ['cmd lang.a', 'wait 200'])
        self.assertTrue(any(l.startswith('error 1 needs') for l in self.lang_log()), self.lang_log())

    def test_stopping_removes_them_and_ids_reach_code_actions(self):
        a = fdiag('#1', 0, [diag(2, 9, 2, 14, 'warning', 'unused', rec('id', 'u-1')),
                            diag(3, 5, 3, 10, 'warning', 'other', rec('id', 'u-2'))])
        root = self.provider(self.spec({'a': [list(a)]}), 'actions = *.rs\n', extra=self.manifest(['a']))
        out = self.run_lang(root, ['cmd lang.a', 'wait 200', 'key ctrl+Home', 'key Down', 'cmd code_actions',
                                   'wait 300', 'key Escape', 'ext-set fake/lang stop', 'wait 300', 'print-file-diagnostics',
                                   'print-marks'])
        req = [l for l in self.lang_log() if ' code-actions ' in l and l[:2] != '0 ']
        self.assertEqual(req[0].split()[4:], ['2', '9', '2', '14', 'invoked', '-', 'u-1'], req)
        self.assertEqual(self.problems(out), [])
        self.assertIn('errors=0 warnings=0', out)

    def test_needs_the_feature(self):
        a = fdiag('#1', 0, [diag(1, 1, 1, 3, 'error', 'x')])
        root = self.provider(self.spec({'a': [list(a)]}, hello='hello 1 code-actions'), 'actions = *.rs\n',
                             extra=self.manifest(['a']))
        self.run_lang(root, ['cmd lang.a', 'wait 200'])
        self.assertIn('error 1 unknown', self.lang_log())


if __name__ == '__main__':
    unittest.main()
