#!/usr/bin/env python3
"""Go to Symbol in Project (docs/extensions/v1.1.md, "workspace-symbols"): ctrl+t and "#" in Go to
File, the query asked 120 ms after typing stops, parts filling the list, and choosing a symbol."""
import unittest

lang = __import__('langfeat-query')


def sym(path, l1, c1, l2, c2, kind, name, detail=''):
    return (f'{l1} {c1} {l2} {c2} {kind} {{len:{path}}} {len(name.encode())} {len(detail.encode())}\n'
            f'{path}{name}{detail}')


B_RS = 'fn helper() {\n    let total = 2;\n}\n'
SYMS = '2\n' + sym('{project}/b.rs', 1, 4, 1, 10, 'function', 'helper') + sym('{project}/a.rs', 1, 4, 1, 8, 'function', 'main')


class WorkspaceSymbols(lang.Lang):
    def setUp(self):
        super().setUp()
        (self.proj / 'b.rs').write_text(B_RS, encoding='utf-8')

    def provider_for(self, answer):
        spec = {'hello': 'hello 1 workspace-symbols query-stream', 'bodied': ['workspace-symbols'],
                'answers': {'workspace-symbols': answer}}
        return self.provider(spec, 'workspace_symbols = *.rs\n')

    def rows(self, out):
        return [l for l in out if l.startswith('  ') or l.startswith('> ')]

    def asked(self):
        return [l for l in self.lang_log() if ' workspace-symbols ' in l or l.startswith('body ')]

    def test_ctrl_t_lists_and_choosing_opens(self):
        root = self.provider_for({'body': SYMS})
        out = self.run_lang(root, ['key ctrl+t', 'wait 300', 'print-palette', 'type help', 'wait 400',
                                   'print-palette', 'key Return', 'wait 100', 'print-state'])
        rows = self.rows(out)
        self.assertTrue(any(r[2:].startswith('helper') for r in rows), out)
        self.assertTrue(any(r[2:].startswith('main') for r in rows), out)
        log = self.lang_log()
        reqs = [l for l in log if ' workspace-symbols ' in l]
        self.assertTrue(reqs[0].endswith(' workspace-symbols 500 0'), log)
        self.assertTrue(reqs[-1].endswith(' workspace-symbols 500 4'), log)
        self.assertIn('body help', log)
        self.assertLessEqual(len(reqs), 3, log)     # typing quickly asks once for it
        state = [l for l in out if l.startswith('tabs=')][-1]
        self.assertIn('active=b.rs line=1 col=4', state)

    def test_hash_in_go_to_file_switches(self):
        root = self.provider_for({'body': SYMS})
        out = self.run_lang(root, ['key ctrl+p', 'type #', 'wait 300', 'print-palette'])
        self.assertIn('choose=Go to Symbol in Project', out)
        self.assertTrue(any(' workspace-symbols 500 0' in l for l in self.lang_log()), self.lang_log())

    def test_parts_fill_the_list(self):
        part = '1\n' + sym('{project}/b.rs', 1, 4, 1, 10, 'function', 'helper')
        root = self.provider_for({'parts': [[part, 0.05]], 'delay': 1.0,
                                  'body': '1\n' + sym('{project}/a.rs', 1, 4, 1, 8, 'function', 'main')})
        out = self.run_lang(root, ['key ctrl+t', 'wait 400', 'echo ---', 'print-palette', 'wait 1000', 'echo ---',
                                   'print-palette'])
        first, second = '\n'.join(out).split('---')[1:3]
        rows = lambda t: [l for l in t.split('\n') if l.startswith('  ') or l.startswith('> ')]
        self.assertEqual(len(rows(first)), 1, out)
        self.assertEqual(len(rows(second)), 2, out)


if __name__ == '__main__':
    unittest.main()
