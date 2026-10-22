#!/usr/bin/env python3
"""The Results panel tab (docs/extensions/v1.1.md, "navigation" and "hierarchy"): Find All
References grouped by file with F4 and shift+F4, parts growing the set, the kept sets, and call
and type hierarchies whose rows ask their provider for their children (feature hierarchy)."""
import unittest

lang = __import__('langfeat-query')
loc = lang.loc


def item(kind, rng, sel, path, name, detail='', data='', sites=None):
    """A hierarchy item (or a call, with sites) with {len:...} so paths of any length fit."""
    head = (f'{kind} {rng[0]} {rng[1]} {rng[2]} {rng[3]} {sel[0]} {sel[1]} {sel[2]} {sel[3]} '
            f'{{len:{path}}} {len(name.encode())} {len(detail.encode())} {len(data.encode())}')
    if sites is not None:
        head += f' {len(sites)}'
    return (head + '\n' + path + name + detail + data
            + ''.join(f'{a} {b} {c} {d}\n' for a, b, c, d in (sites or [])))


B_RS = 'fn helper() {\n    let total = 2;\n}\n'


class Results(lang.Lang):
    def setUp(self):
        super().setUp()
        (self.proj / 'b.rs').write_text(B_RS, encoding='utf-8')

    def rows(self, out):
        return [l for l in out if l.startswith('row ')]

    def label(self, row):
        rest = row.split(' label=', 1)[1]
        for cut in (' desc=', ' badge=', ' icon='):
            rest = rest.split(cut)[0]
        return rest

    def at_total(self):
        return ['key ctrl+Home', 'key Down', 'key Home', 'key ctrl+Right', 'key Right']

    def test_references_fill_the_panel_by_file_and_f4_walks_them(self):
        body = ('3\n' + loc('{path}', 2, 9, 2, 14, 'let total = 1;') + loc('{path}', 3, 5, 3, 10, 'total + 1')
                + loc('{project}/b.rs', 2, 9, 2, 14, 'let total = 2;'))
        root = self.provider({'hello': 'hello 1 references', 'answers': {'references': {'body': body}}},
                             'references = *.rs\n')
        out = self.run_lang(root, self.at_total() + ['cmd references', 'wait 400', 'print-results', 'key F4',
                                                     'print-state', 'key F4', 'print-state', 'key F4', 'print-state',
                                                     'key F4', 'key shift+F4', 'key shift+F4', 'print-state',
                                                     'print-results'])
        head = [l for l in out if l.startswith('set=')]
        self.assertTrue(head[0].startswith('set=1/1 kind=references cur=-1 title=3 references to total'), head)
        labels = [self.label(r) for r in self.rows(out)[:5]]
        self.assertEqual(labels, ['a.rs', '2:9  let total = 1;', '3:5  total + 1', 'b.rs', '2:9  let total = 2;'], out)
        states = [l for l in out if l.startswith('tabs=')]
        self.assertIn('active=a.rs line=2 col=14 sel=5', states[0])
        self.assertIn('active=a.rs line=3 col=10 sel=5', states[1])
        self.assertIn('active=b.rs line=2 col=14 sel=5', states[2])
        self.assertIn('active=a.rs line=3 col=10 sel=5', states[3])    # wrapped to the first, then back twice
        self.assertIn('cur=1 ', head[1])
        self.assertIn(' cur id=', self.rows(out)[7])                      # the tree's cursor follows

    def test_parts_show_at_once_and_the_set_keeps_growing(self):
        root = self.provider({'hello': 'hello 1 references query-stream', 'answers': {
            'references': {'parts': [['1\n' + loc('{path}', 1, 4, 1, 8, 'fn main() {'), 0.05]],
                           'delay': 1.2, 'body': '1\n' + loc('{project}/b.rs', 2, 9, 2, 14, 'let total = 2;')}}},
            'references = *.rs\n')
        out = self.run_lang(root, self.at_total() + ['cmd references', 'wait 500', 'print-results', 'wait 1200',
                                                     'print-results'])
        head = [l for l in out if l.startswith('set=')]
        self.assertIn('title=1 reference to total  (searching...)', head[0])
        self.assertIn('title=2 references to total', head[1])
        self.assertNotIn('searching', head[1])
        self.assertTrue(all(l.startswith('set=1/1') for l in head), head)

    def test_progress_shows_in_the_title_and_cancel_keeps_what_came(self):
        root = self.provider({'hello': 'hello 1 references query-stream', 'answers': {
            'references': {'progress': [[45, 'Indexing', 0.05]],
                           'parts': [['1\n' + loc('{path}', 1, 4, 1, 8, 'fn main() {'), 0.05]],
                           'delay': 3.0, 'body': '0\n'}}}, 'references = *.rs\n')
        out = self.run_lang(root, self.at_total() + ['cmd references', 'wait 500', 'print-results',
                                                     'cmd cancel_query', 'wait 200', 'print-results',
                                                     'print-langstats fake/lang'])
        head = [l for l in out if l.startswith('set=')]
        self.assertIn('title=1 reference to total  (searching...) fake/lang 45% Indexing', head[0])
        self.assertTrue(head[1].endswith('title=1 reference to total'), head)
        self.assertEqual(self.stats(out, 'references')['cancelled'], '1', out)

    def test_find_in_files_moves_its_results_here(self):
        root = self.provider({'hello': 'hello 1'}, 'definition = *.go\n')
        out = self.run_lang(root, ['key ctrl+shift+f', 'type total', 'wait-grep', 'wait 100', 'key ctrl+Return',
                                   'wait 100', 'print-results', 'key F4', 'print-state'])
        head = [l for l in out if l.startswith('set=')]
        self.assertTrue(head and 'kind=find' in head[0] and 'title=3 results for total' in head[0], out)
        state = [l for l in out if l.startswith('tabs=')][-1]
        self.assertIn('line=2 col=14 sel=5', state)

    def test_sets_are_kept_and_dropped(self):
        root = self.provider({'hello': 'hello 1 references', 'answers': {
            'references': {'body': '1\n' + loc('{path}', 1, 4, 1, 8, 'fn main() {')}}}, 'references = *.rs\n')
        out = self.run_lang(root, ['cmd references', 'wait 300', 'key Escape', 'cmd references', 'wait 300',
                                   'print-results', 'cmd results_back', 'print-results', 'cmd results_drop',
                                   'print-results', 'cmd results_drop', 'print-results'])
        head = [l for l in out if l.startswith('set=') or l.startswith('results=')]
        self.assertEqual([h.split()[0] for h in head], ['set=2/2', 'set=1/2', 'set=1/1', 'results=none'], head)

    def test_a_streaming_set_is_found_where_the_user_left_it(self):
        root = self.provider({'hello': 'hello 1 references query-stream', 'answers': {
            'references': {'parts': [['1\n' + loc('{path}', 1, 4, 1, 8, 'fn main() {'), 0.05]],
                           'delay': 1.2, 'body': '1\n' + loc('{path}', 3, 5, 3, 10, 'total + 1')}}},
            'references = *.rs\n')
        out = self.run_lang(root, ['cmd references', 'wait 1600', 'key Escape', 'cmd references', 'wait 400',
                                   'cmd results_back', 'wait 1300', 'print-results'])
        head = [l for l in out if l.startswith('set=')]
        self.assertTrue(head[0].startswith('set=1/2 '), out)

    def calls_spec(self):
        main = item('function', (1, 1, 4, 2), (1, 4, 1, 8), '{path}', 'main', 'fn()', 'D-MAIN')
        caller = item('function', (1, 1, 3, 2), (1, 4, 1, 10), '{project}/b.rs', 'helper', 'fn()', 'D-HELPER',
                      sites=[(2, 5, 2, 9), (2, 13, 2, 17)])
        callee = item('function', (1, 1, 3, 2), (1, 4, 1, 10), '{project}/b.rs', 'helper', 'fn()', 'D-HELPER',
                      sites=[(3, 5, 3, 10)])
        return {'hello': 'hello 1 hierarchy query-stream', 'bodied': ['calls-in', 'calls-out'], 'answers': {
            'call-hierarchy': {'body': '1\n' + main},
            'calls-in': {'body': '1\n' + caller, 'match': {'D-HELPER': {'body': '0\n'}}},
            'calls-out': {'body': '1\n' + callee}}}

    def test_call_hierarchy_asks_for_children_and_turns_around(self):
        root = self.provider(self.calls_spec(), 'call_hierarchy = *.rs\n')
        out = self.run_lang(root, ['key shift+alt+h', 'wait 300', 'wait 300', 'print-results', 'key Down',
                                   'key Return', 'wait 100', 'print-state', 'cmd results_flip', 'wait 300',
                                   'wait 300', 'print-results'])
        head = [l for l in out if l.startswith('set=')]
        self.assertIn('kind=calls-in', head[0])
        self.assertIn('title=Incoming calls of main', head[0])
        first = self.rows(out)[:2]
        self.assertEqual([self.label(r) for r in first], ['main', 'helper'], out)
        self.assertIn('desc=fn()  b.rs:1  (2 calls)', first[1])
        log = self.lang_log()
        self.assertTrue(any(' call-hierarchy 1 0 1 1 invoked -' in l for l in log), log)
        self.assertIn('body D-MAIN', log)
        state = [l for l in out if l.startswith('tabs=')][0]
        self.assertIn('active=b.rs line=2 col=9 sel=4', state)   # the first call site, in the caller's file
        self.assertIn('kind=calls-out', head[1])
        self.assertTrue(any(' calls-out 6' in l for l in log), log)

    def test_a_failed_row_shows_an_error_row(self):
        spec = self.calls_spec()
        spec['answers']['calls-in'] = {'error': 'failed no index'}
        root = self.provider(spec, 'call_hierarchy = *.rs\n')
        out = self.run_lang(root, ['key shift+alt+h', 'wait 300', 'wait 300', 'print-results'])
        rows = self.rows(out)
        self.assertTrue(rows[1].endswith(' error'), rows)

    def test_type_hierarchy_supertypes(self):
        shape = item('struct', (1, 1, 4, 2), (1, 4, 1, 8), '{path}', 'Shape')
        base = item('interface', (1, 1, 3, 2), (1, 4, 1, 10), '{project}/b.rs', 'Base', 'trait')
        root = self.provider({'hello': 'hello 1 hierarchy', 'bodied': ['supertypes', 'subtypes'], 'answers': {
            'type-hierarchy': {'body': '1\n' + shape}, 'supertypes': {'body': '1\n' + base},
            'subtypes': {'body': '0\n'}}}, 'type_hierarchy = *.rs\n')
        out = self.run_lang(root, ['cmd type_hierarchy', 'wait 300', 'wait 300', 'print-results'])
        head = [l for l in out if l.startswith('set=')]
        self.assertIn('kind=supertypes title=Supertypes of Shape', head[0].replace(' cur=-1', ''))
        self.assertEqual([self.label(r) for r in self.rows(out)[:2]], ['Shape', 'Base'], out)

    def test_no_provider_says_so(self):
        out = self.run_lang(self.provider({'hello': 'hello 1'}, 'definition = *.rs\n'),
                            ['key shift+alt+h', 'wait 100', 'print-toast'])
        self.assertIn('No call hierarchy', out[-1])


def sym(l1, c1, l2, c2, kind, depth, name, detail=''):
    return f'{l1} {c1} {l2} {c2} {kind} {depth} {len(name.encode())} {len(detail.encode())}\n{name}{detail}'


class Outline(lang.Lang):
    SYMS = '3\n' + sym(1, 1, 4, 2, 'function', 0, 'main', 'fn()') + sym(2, 9, 2, 14, 'variable', 1, 'total') + \
        sym(3, 5, 3, 10, 'variable', 1, 'total')

    def rows(self, out):
        return [l for l in out if l.startswith('row ')]

    def test_the_section_lists_symbols_follows_the_cursor_and_asks_again_after_edits(self):
        root = self.provider({'hello': 'hello 1 symbols', 'answers': {'symbols': {'body': self.SYMS}}},
                             'symbols = *.rs\n')
        out = self.run_lang(root, ['print-outline', 'cmd focus_outline', 'wait 300', 'print-outline', 'key Escape',
                                   'key ctrl+Home', 'key Down', 'key Home', 'key ctrl+Right', 'key Right',
                                   'key Right', 'wait 50', 'print-outline', 'type x',
                                   'wait 800', 'cmd focus_outline', 'key Up', 'key Return', 'print-state'])
        heads = [l for l in out if l.startswith('outline')]
        self.assertEqual(heads[0], 'outline doc=0 symbols=0 visible=0', out)   # made, collapsed, not asked
        self.assertTrue(heads[1].startswith('outline doc=1 symbols=3'), heads)
        rows = self.rows(out)
        self.assertIn(' d=0 open ', rows[0])
        self.assertIn('label=main desc=fn()', rows[0])
        self.assertIn(' d=1 leaf ', rows[1])
        self.assertIn(' id=\x01main\x01total#1 ', rows[2])     # a second "total" keeps its own id
        self.assertIn(' cur ', rows[4])                          # the cursor on line 2: its "total"
        asked = [l for l in self.lang_log() if ' symbols 1 ' in l]
        self.assertEqual(len(asked), 2, self.lang_log())         # and again after typing
        state = [l for l in out if l.startswith('tabs=')][-1]
        self.assertIn('line=1 col=1 sel=0', state)               # Up to "main", Enter: its start

    def test_a_hidden_section_keeps_no_deadline(self):
        root = self.provider({'hello': 'hello 1 symbols', 'answers': {'symbols': {'body': self.SYMS}}},
                             'symbols = *.rs\n')
        out = self.run_lang(root, ['cmd focus_outline', 'wait 300', 'key Escape', 'type x', 'cmd toggle_sidebar',
                                   'wait 800', 'print-langfeat-waits'])
        self.assertTrue(out[-1].startswith('outline=-1 '), out)

    def test_another_document_drops_the_rows_at_once(self):
        (self.proj / 'b.rs').write_text('fn b() {}\n', encoding='utf-8')
        root = self.provider({'hello': 'hello 1 symbols', 'answers': {'symbols': {'body': self.SYMS, 'delay': 0.6}}},
                             'symbols = *.rs\n')
        out = self.run_lang(root, ['cmd focus_outline', 'wait 1000', 'print-outline', 'key Escape',
                                   'open ' + str(self.proj / 'b.rs'), 'wait 100', 'print-outline'])
        heads = [l for l in out if l.startswith('outline')]
        self.assertIn('symbols=3', heads[0])
        self.assertIn('symbols=0', heads[1], out)

    def test_the_cursor_moving_along_a_line_moves_the_row(self):
        (self.proj / 'c.rs').write_text('fn foo() {} fn bar() {}\n', encoding='utf-8')
        syms = '2\n' + sym(1, 1, 1, 12, 'function', 0, 'foo') + sym(1, 13, 1, 24, 'function', 0, 'bar')
        root = self.provider({'hello': 'hello 1 symbols', 'answers': {'symbols': {'body': syms}}}, 'symbols = *.rs\n')
        out = self.run_lang(root, ['cmd focus_outline', 'wait 300', 'key Escape', 'key ctrl+Home', 'wait 50',
                                   'print-outline', 'key End', 'wait 50', 'print-outline'], files=('c.rs',))
        rows = self.rows(out)
        self.assertIn(' cur ', rows[0])
        self.assertIn(' cur ', rows[3], out)        # the second dump: "bar"

    def test_no_provider_no_section(self):
        out = self.run_lang(self.provider({'hello': 'hello 1'}, 'definition = *.rs\n'),
                            ['print-outline', 'cmd focus_outline', 'wait 200', 'print-outline'])
        self.assertEqual(out[1], 'outline=none', out)
        self.assertIn('outline doc=1 symbols=0 visible=1', out)


if __name__ == '__main__':
    unittest.main()
