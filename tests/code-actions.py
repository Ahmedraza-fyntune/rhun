#!/usr/bin/env python3
"""Code actions of protocol 1.1 (feature code-actions): kinds asked and filtered, the diagnostic
range rule, preferred quick fixes and Auto Fix, Organize Imports, disabled actions, resolve then
edit then command (command-args); v1 providers keep actions. Also navigation (declaration, type
definition, implementation) and range formatting (partial-format)."""
import unittest

lang = __import__('langfeat-query')


def rec(name, body='', args=''):
    b = body.encode()
    return (f'{name} {args} {len(b)}' if args else f'{name} {len(b)}') + '\n' + body


def edit(path_expr, version_expr, edits):
    """A workspace edit for one file with {len:...} lengths: edits are (l1, c1, l2, c2, text)."""
    out = f'1\n{{len:{path_expr}}} {version_expr} {len(edits)}\n{path_expr}'
    for l1, c1, l2, c2, text in edits:
        out += f'{l1} {c1} {l2} {c2} {len(text.encode())}\n{text}'
    return out


def action(kind, title, edit_body='', extra=''):
    # EDIT_LEN must count the bytes after {path}/{len:} expansion: use a placeholder the fake fills
    return f'{kind} {len(title.encode())} {{len:{edit_body}}} {len(extra.encode())}\n{title}{edit_body}{extra}'


FIX = edit('{path}', '{version}', [(1, 1, 1, 1, '// fixed\n')])
ORG = edit('{path}', '{version}', [(1, 1, 1, 1, '// organized\n')])


class Actions(lang.Lang):
    def spec(self, answers, hello='hello 1 code-actions command-args', **more):
        return dict({'hello': hello, 'bodied': ['code-action-resolve'], 'answers': answers}, **more)

    def run_actions(self, spec, actions, provides='actions = *.rs\n', extra=''):
        root = self.provider(spec, provides, extra=extra)
        return self.run_lang(root, actions)

    def requests(self, verb):
        return [l for l in self.lang_log() if l[:1].isdigit() and f' {verb} ' in l]

    def doc_lines(self, out):
        i = len(out) - 1 - out[::-1].index('===')
        return out[i + 1:out.index('<eod>', i)]

    def test_kinds_are_asked_and_a_lone_organize_imports_is_applied(self):
        spec = self.spec({'code-actions': {'body': '1\n' + action('source.organizeImports', 'Organize', ORG)}})
        out = self.run_actions(spec, ['cmd organize_imports', 'wait 400', 'echo ===', 'print-doc'])
        req = self.requests('code-actions')
        self.assertTrue(req and req[0].split()[2:] == ['1', '0', '1', '1', '1', '1', 'invoked', 'source.organizeImports', '-'], req)
        self.assertEqual(self.doc_lines(out)[0], '// organized', out)

    def test_auto_fix_applies_the_preferred_quick_fix_and_filters_kinds(self):
        body = ('3\n' + action('quickfix', 'Other fix', FIX) + action('quickfix', 'Best fix', ORG, rec('preferred'))
                + action('refactor.extract', 'Extract', FIX))
        spec = self.spec({'code-actions': {'body': body}})
        out = self.run_actions(spec, ['cmd quick_fix_auto', 'wait 400', 'echo ===', 'print-doc'])
        self.assertEqual(self.doc_lines(out)[0], '// organized', out)

    def test_the_list_orders_kinds_and_puts_disabled_last(self):
        body = ('4\n' + action('refactor', 'Refactor it', FIX)
                + action('quickfix', 'Cannot', '', rec('disabled', 'Nothing to fix here') + rec('command', 'x', 'fix 1'))
                + action('source', 'Source it', FIX) + action('quickfix', 'Fix it', FIX))
        spec = self.spec({'code-actions': {'body': body}})
        out = self.run_actions(spec, ['cmd code_actions', 'wait 400', 'print-palette', 'type Cannot', 'key Return',
                                      'print-toast'])
        rows = [l[2:] for l in out if l.startswith('  ') or l.startswith('> ')]
        self.assertEqual(rows[:4], ['Fix it', 'Refactor it', 'Source it', 'Cannot'], out)
        self.assertIn('Nothing to fix here', out[-1])

    def test_without_a_selection_the_range_is_the_diagnostic_at_the_cursor(self):
        diag = '2 9 2 14 error unused\n3 5 3 10 warning other\n'
        spec = self.spec({'code-actions': {'body': '0\n'}},
                         run={'diag': [[f'diagnostics 1 0 2 {len(diag)}', diag]]})
        self.run_actions(spec, ['cmd lang.diag', 'wait 200', 'key ctrl+Home', 'key Down', 'key End',
                                'cmd code_actions', 'wait 300', 'key Escape', 'key Down', 'key Home',
                                'cmd code_actions', 'wait 300'],
                         extra='[commands]\ndiag = Diagnose\n')
        req = [r for r in self.requests('code-actions') if ' invoked ' in r]     # not the lightbulb's
        self.assertEqual(req[0].split()[4:8], ['2', '9', '2', '14'], req)
        self.assertEqual(req[1].split()[4:8], ['3', '5', '3', '10'], req)

    def test_resolve_then_edit_then_command(self):
        body = '1\n' + action('quickfix', 'Resolve me', '', rec('resolve', 'R-DATA'))
        cmd = rec('command', 'ARGS', 'fix')
        resolved = '{len:' + FIX + '} ' + str(len(cmd)) + '\n' + FIX + cmd
        spec = self.spec({'code-actions': {'body': body}, 'code-action-resolve': {'body': resolved}})
        out = self.run_actions(spec, ['cmd code_actions', 'wait 400', 'key Return', 'wait 400', 'echo ===',
                                      'print-doc'], extra='[commands]\nfix = Fix\n')
        self.assertEqual(self.doc_lines(out)[0], '// fixed', out)
        log = self.lang_log()
        self.assertTrue(any(' code-action-resolve 1 0 6' in l for l in log), log)
        self.assertIn('body R-DATA', log)
        self.assertTrue(any(l.startswith('0 run lang.fix 1 ref 4') for l in log), log)

    def test_an_action_with_an_edit_and_a_command_runs_both(self):
        body = '1\n' + action('quickfix', 'Both', FIX, rec('command', 'XY', 'fix'))
        spec = self.spec({'code-actions': {'body': body}})
        out = self.run_actions(spec, ['cmd code_actions', 'wait 400', 'key Return', 'wait 300', 'echo ===',
                                      'print-doc'], extra='[commands]\nfix = Fix\n')
        self.assertEqual(self.doc_lines(out)[0], '// fixed', out)
        self.assertTrue(any(l.startswith('0 run lang.fix 1 ref 2') for l in self.lang_log()), self.lang_log())

    def test_the_lightbulb_shows_only_on_lines_with_diagnostics(self):
        diag = '2 9 2 14 error unused\n'
        body = '2\n' + action('quickfix', 'Fix it', FIX, rec('preferred')) + action('quickfix', 'No', '', rec('disabled', 'x'))
        spec = self.spec({'code-actions': {'body': body}}, run={'diag': [[f'diagnostics 1 0 1 {len(diag)}', diag]]})
        out = self.run_actions(spec, ['cmd lang.diag', 'wait 200', 'key ctrl+Home', 'wait 400', 'print-lightbulb',
                                      'key Down', 'wait 500', 'print-lightbulb', 'key Down', 'wait 400',
                                      'print-lightbulb', 'cmd quick_fix', 'wait 300', 'print-palette'],
                               extra='[commands]\ndiag = Diagnose\n')
        bulbs = [l for l in out if l.startswith('lightbulb')]
        self.assertEqual(bulbs, ['lightbulb=none', 'lightbulb line=2 count=1 preferred=1', 'lightbulb=none'], out)
        req = self.requests('code-actions')
        self.assertEqual(req[0].split()[8:10], ['auto', 'quickfix'], req)
        self.assertEqual(len([r for r in req if ' auto ' in r]), 1, req)      # lines without diagnostics: nothing
        self.assertTrue(any(l.endswith('Fix it') or 'Fix it' in l for l in out if l.startswith('> ')), out)

    def test_a_resolve_out_goes_when_another_query_starts(self):
        body = '1\n' + action('quickfix', 'Resolve me', '', rec('resolve', 'R-DATA'))
        resolved = '0 ' + str(len(rec('command', 'ARGS', 'fix'))) + '\n' + rec('command', 'ARGS', 'fix')
        spec = self.spec({'code-actions': {'body': body}, 'code-action-resolve': {'body': resolved, 'delay': 0.8},
                          'references': {'body': '0\n'}}, hello='hello 1 code-actions command-args references')
        self.run_actions(spec, ['cmd code_actions', 'wait 400', 'key Return', 'wait 100', 'cmd references',
                                'wait 1300'], provides='actions = *.rs\nreferences = *.rs\n',
                         extra='[commands]\nfix = Fix\n')
        log = self.lang_log()
        rid = [l.split()[0] for l in log if ' code-action-resolve ' in l][0]
        self.assertIn('0 cancel ' + rid, log)
        self.assertFalse(any(l.startswith('0 run lang.fix') for l in log), log)

    def test_an_action_command_runs_after_its_edit_is_confirmed(self):
        (self.proj / 'b.rs').write_text('fn helper() {}\n', encoding='utf-8')
        other = edit('{project}/b.rs', '-', [(1, 1, 1, 1, '// fixed\n')])
        body = '1\n' + action('quickfix', 'Elsewhere', other, rec('command', 'XY', 'fix'))
        spec = self.spec({'code-actions': {'body': body}}, hello='hello 1 code-actions command-args workspace-edits')
        out = self.run_actions(spec, ['cmd code_actions', 'wait 400', 'key Return', 'wait 300', 'print-palette',
                                      'key Return', 'wait 400', 'print-toast'], extra='[commands]\nfix = Fix\n')
        self.assertTrue(any(l.startswith('choose=') for l in out), (out, self.lang_log(), (self.proj / 'b.rs').read_text()))
        self.assertTrue((self.proj / 'b.rs').read_text().startswith('// fixed'))
        self.assertTrue(any(l.startswith('0 run lang.fix 1 ref 2') for l in self.lang_log()), self.lang_log())

    def test_diagnostic_ids_follow_the_text(self):
        fd = 'file-diagnostics 0 1 2 {}'
        rec_ = '2 9 2 14 error unused 0'
        d = f'2 9 2 14 error 6 {len(rec("id", "d1"))}\nunused' + rec('id', 'd1')
        body = '#1' + d
        spec = self.spec({'code-actions': {'body': '0\n'}}, hello='hello 1 code-actions file-diagnostics',
                         run={'diag': [[f'file-diagnostics 0 1 2 {len(body)}', body]]})
        self.run_actions(spec, ['cmd lang.diag', 'wait 200', 'key ctrl+Home', 'key Return', 'key Down',
                                'key End', 'cmd code_actions', 'wait 300'], extra='[commands]\ndiag = Diagnose\n')
        req = [r for r in self.requests('code-actions') if ' invoked ' in r]
        self.assertEqual(req[0].split()[4:8], ['3', '9', '3', '14'], req)
        self.assertEqual(req[0].split()[-1], 'd1', req)

    def test_v1_providers_keep_actions_and_get_no_kinds(self):
        spec = self.spec({'actions': {'body': '0\n'}}, hello='hello 1 actions')
        self.run_actions(spec, ['cmd code_actions', 'wait 300', 'cmd organize_imports', 'wait 300'])
        self.assertEqual(len(self.requests('actions')), 1, self.lang_log())
        self.assertEqual(self.requests('code-actions'), [])


class Navigation(lang.Lang):
    def test_declaration_type_definition_and_implementation(self):
        loc = lang.loc
        spec = {'hello': 'hello 1 navigation', 'answers': {
            'declaration': {'body': '1\n' + loc('{path}', 1, 4, 1, 8, 'main')},
            'type-definition': {'body': '1\n' + loc('{path}', 2, 9, 2, 14, 'total')},
            'implementation': {'body': '2\n' + loc('{path}', 1, 4, 1, 8, 'a') + loc('{path}', 3, 5, 3, 10, 'b')}}}
        root = self.provider(spec, 'declaration = *.rs\ntype_definition = *.rs\nimplementation = *.rs\n')
        out = self.run_lang(root, ['cmd declaration', 'wait 300', 'print-state', 'cmd type_definition', 'wait 300',
                                   'print-state', 'key ctrl+F12', 'wait 300', 'print-palette'])
        states = [l for l in out if l.startswith('tabs=')]
        self.assertIn('line=1 col=8', states[0])
        self.assertIn('line=2 col=14', states[1])
        rows = [l for l in out if l.startswith('  ') or l.startswith('> ')]
        self.assertEqual(len(rows), 2, out)


class RangeFormat(lang.Lang):
    def test_format_selection_sends_the_range_and_the_files_options(self):
        fmt = '1\n{len:{path}} {version} 1\n{path}2 1 2 5 0\n'
        spec = {'hello': 'hello 1 format partial-format', 'answers': {'range-format': {'body': fmt}}}
        root = self.provider(spec, 'format = *.rs\nrange_format = *.rs\n')
        (self.work / 'config/rhun/config').write_text(lang.host.CONFIG + '[files]\ntrim_trailing_whitespace = true\n')
        out = self.run_lang(root, ['key ctrl+Home', 'key Down', 'key shift+End', 'key shift+alt+f', 'wait 400',
                                   'echo ===', 'print-doc'])
        req = [l for l in self.lang_log() if ' range-format ' in l]
        self.assertTrue(req and req[0].split()[4:] == ['2', '1', '2', '19', '4', 'yes', 'yes', 'yes'], req)
        i = out.index('===')
        self.assertEqual(out[i + 2], 'let total = 1;', out)


if __name__ == '__main__':
    unittest.main()
