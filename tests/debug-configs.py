#!/usr/bin/env python3
"""Choosing a launch configuration (Debug: Select Configuration, then F5 starts it) and adding one from
a debugger's templates (Debug: Add Configuration appends the section to launch.ini and opens it)."""
import unittest
import debughost


class Configs(debughost.DebugHost):
    def test_select_configuration(self):
        self.scenario()
        self.launch_ini('[A]\ntype = fake\nprogram = scenario.json\n[B]\ntype = fake\nprogram = scenario.json\n')
        out = self.run_editor(['cmd debug_select_configuration', 'print-palette', 'type B', 'key Return',
                               'key F5', 'dialog yes', 'wait-debug ended', 'print-debug'])
        self.assertIn('choose=Debug configuration', out)
        self.assertEqual([l for l in out if l.strip() in ('A', 'B', '> A', '> B')], ['> A', '  B'])
        self.assertEqual(self.field(self.debug_lines(out)[-1], 'name'), 'B', out)

    def test_add_configuration_from_a_template(self):
        self.scenario()
        out = self.run_editor(['cmd debug_add_configuration', 'print-palette', 'type attach', 'key Return',
                               'wait 200', 'print-tabs'])
        items = [l.strip().lstrip('> ') for l in out if 'Fake' in l and ':' in l]
        self.assertIn('Fake Debugger: Fake launch', items)
        self.assertIn('Fake Debugger: Fake attach', items)
        ini = (self.proj / '.rhun/launch.ini').read_text()
        self.assertTrue(ini.startswith('# Launch configurations'), ini)
        self.assertIn('[Fake attach]\ntype = fake\nrequest = attach\nprogram = ${project}/scenario.json\n', ini)
        self.assertNotIn('[Fake launch]', ini)
        self.assertIn('launch.ini', [l for l in out if l.startswith('tabs=')][0])

    def test_add_configuration_appends(self):
        self.scenario()
        self.launch_ini('[Mine]\ntype = fake\nprogram = scenario.json')       # no final newline
        out = self.run_editor(['cmd debug_add_configuration', 'type launch', 'key Return', 'wait 200',
                               'print-configs'])
        ini = (self.proj / '.rhun/launch.ini').read_text()
        self.assertTrue(ini.startswith('[Mine]\ntype = fake\nprogram = scenario.json\n\n[Fake launch]\n'), ini)
        self.assertEqual([l for l in out if l.startswith('config=')], ['config=Mine', 'config=Fake launch'])


if __name__ == '__main__':
    unittest.main()
