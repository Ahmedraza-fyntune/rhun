#!/usr/bin/env python3
"""Variables (docs/guide.md "Debugging"): many indexed children come in chunks of 100 ([0..99]), asked
for by start and count when they open (bigger arrays nest chunks); Set Value (F2, setVariable) and
its errors; values that changed since the last stop stand out."""
import unittest
import debughost


class Variables(debughost.DebugHost):
    def paused(self, locals_, extra, steps=None):
        a = self.src.as_posix()
        self.scenario(steps or [{'file': a, 'line': 6, 'function': 'main', 'locals': locals_}])
        self.launch_ini('[Run]\ntype = fake\nprogram = scenario.json\nstopOnEntry = yes\n')
        return self.run_editor([*self.start(), 'wait-debug paused', 'wait 200', *extra])

    def vars(self, out):
        return [l for l in out if l.startswith('  ') and (' = ' in l or l.strip().startswith('['))]

    def requests_of(self, word):
        return [l for l in self.dap_log() if l.startswith(word)]

    def test_chunks_of_a_long_list(self):
        out = self.paused({'items': list(range(250)), 'n': 1},
                          ['debug-expand Locals/items', 'wait 300', 'debug-expand Locals/items/[100..199]',
                           'wait 300', 'print-vars'])
        names = [l.strip().split(' =')[0] for l in self.vars(out)]
        self.assertEqual(names[:5], ['items', '[0..99]', '[100..199]', '[100]', '[101]'], out)
        self.assertIn('      [150] = 150 : int', out)
        self.assertIn('[200..249]', names)
        reqs = self.requests_of('VARIABLES')
        self.assertIn('VARIABLES filter=named start=None count=None', reqs)
        self.assertIn('VARIABLES filter=indexed start=100 count=100', reqs)

    def test_nested_chunks_of_a_huge_list(self):
        # 25000 items: chunks of 10000, each of 100 chunks of 100 (asked for only at the last level)
        out = self.paused({'items': list(range(25000))},
                          ['debug-expand Locals/items', 'wait 300', 'debug-expand Locals/items/[10000..19999]',
                           'wait 200', 'debug-expand Locals/items/[10000..19999]/[11100..11199]', 'wait 300',
                           'print-vars'])
        names = [l.strip().split(' =')[0] for l in self.vars(out)]
        for name in ('[0..9999]', '[20000..24999]', '[10000..10099]', '[19900..19999]', '[11100..11199]', '[11150]'):
            self.assertIn(name, names)
        reqs = self.requests_of('VARIABLES')
        self.assertEqual(reqs[-1], 'VARIABLES filter=indexed start=11100 count=100', reqs)
        self.assertEqual(len([r for r in reqs if 'indexed' in r]), 1, reqs)    # the big chunks ask nothing

    def test_set_value(self):
        out = self.paused({'total': 0, 'i': 2}, ['debug-set Locals/total 42', 'wait 300', 'print-vars',
                                                 'print-vars-changed', 'debug-set Locals/i bad', 'wait 300',
                                                 'print-console'])
        self.assertIn('  total = 42 : int', out)
        self.assertIn('Locals/total', out)
        self.assertTrue([l for l in self.dap_log() if l.startswith('SETVARIABLE ') and l.endswith(' total 42')],
                        self.dap_log())
        self.assertIn('error cannot set i to bad', out)

    def test_set_value_with_f2(self):
        out = self.paused({'total': 0}, ['view-focus debug.variables', 'key Down', 'key Down', 'key F2',
                                         'print-palette', 'key ctrl+a', 'type 7', 'key Return', 'wait 300',
                                         'print-vars'])
        self.assertTrue(any(l.startswith('prompt=New value') for l in out), out)
        self.assertIn('field=0', out)
        self.assertIn('  total = 7 : int', out)

    def test_a_list_set_to_a_number_loses_its_elements(self):
        # review: the answer has no variablesReference; the old elements stayed under 42
        out = self.paused({'items': [5, 6, 7]}, ['debug-expand Locals/items', 'wait 300', 'print-vars', 'echo --',
                                                 'debug-set Locals/items 42', 'wait 300', 'print-vars'])
        first, second = out[:out.index('--')], out[out.index('--') + 1:]
        self.assertIn('    [1] = 6 : int', first)
        self.assertIn('  items = 42 : int', second)
        self.assertFalse([l for l in second if l.strip().startswith('[')], second)

    def test_nested_chunks_stay_open_across_stops(self):
        # review: a range inside a range closed at the next stop
        a = self.src.as_posix()
        step = {'file': a, 'line': 6, 'function': 'main', 'locals': {'items': list(range(25000))}}
        out = self.paused(None, ['debug-expand Locals/items', 'wait 300', 'debug-expand Locals/items/[10000..19999]',
                                 'wait 200', 'debug-expand Locals/items/[10000..19999]/[11100..11199]', 'wait 300',
                                 'debug-step over', 'wait-debug paused', 'wait 500', 'print-vars'],
                          steps=[step, dict(step, line=7)])
        names = [l.strip().split(' =')[0] for l in self.vars(out)]
        self.assertIn('[11150]', names, out)

    def test_changed_values_stand_out(self):
        a = self.src.as_posix()
        steps = [{'file': a, 'line': 6, 'function': 'main', 'locals': {'total': 0, 'i': 0}},
                 {'file': a, 'line': 7, 'function': 'main', 'locals': {'total': 0, 'i': 1}}]
        out = self.paused(None, ['print-vars-changed', 'echo --', 'debug-step over', 'wait-debug paused', 'wait 300',
                                 'print-vars-changed'], steps=steps)
        first, second = out[:out.index('--')], out[out.index('--') + 1:]
        self.assertFalse([l for l in first if l.startswith('Locals/')], first)
        self.assertEqual([l for l in second if l.startswith('Locals/')], ['Locals/i'], second)


if __name__ == '__main__':
    unittest.main()
