#!/usr/bin/env python3
"""Launch configurations (PROJECT/.rhun/launch.ini, src/app/debugcfg.s): the debugger's declared
types (bool, int, list, map, path, choice), dotted keys building objects and arrays, the variables
(${project} ... ${selection}, ${env:NAME}, $$), and the errors that name the line. The launch
arguments are what the fake adapter (tests/dap/fakedap.py) received."""
import json
import unittest
import debughost


class Config(debughost.DebugHost):
    def args_for(self, body, name='Run', files=('a.c',), extra=()):
        self.scenario()
        self.launch_ini('[%s]\ntype = fake\nprogram = scenario.json\n%s' % (name, body))
        out = self.run_editor([*extra, *self.start(name), 'wait-debug ended', 'print-console'], files=files)
        return self.args_sent(), out

    def test_types(self):
        args, out = self.args_for('stopOnEntry = no\ncount = -12\nargs = one "two words" \'it\'\'s\'\n'
                                  'args = three\nenv.LOG_LEVEL = debug\nenv.A.B = dotted\nmode = test\n')
        self.assertIs(args['stopOnEntry'], False)
        self.assertEqual(args['count'], -12)
        self.assertEqual(args['args'], ['one', 'two words', 'its', 'three'])
        self.assertEqual(args['env'], {'LOG_LEVEL': 'debug', 'A.B': 'dotted'})
        self.assertEqual(args['mode'], 'test')

    def test_paths(self):
        args, out = self.args_for('cwd = sub/dir\n')
        self.assertEqual(args['program'], (self.proj / 'scenario.json').as_posix())
        self.assertEqual(args['cwd'], 'sub/dir')                # not declared as a path: as written
        self.log.unlink()
        self.scenario()
        self.launch_ini('[Run]\ntype = fake\nprogram = ~/proj/scenario.json\n')
        self.run_editor([*self.start(), 'wait-debug ended'])
        self.assertEqual(self.args_sent()['program'], self.work.as_posix() + '/proj/scenario.json')

    def test_nesting(self):
        args, out = self.args_for('pathMappings.1.localRoot = b\npathMappings.0.localRoot = a\n'
                                  'pathMappings.0.remoteRoot = /srv\noptions.deep.er = yes\n')
        self.assertEqual(args['pathMappings'], [{'localRoot': 'a', 'remoteRoot': '/srv'}, {'localRoot': 'b'}])
        self.assertEqual(args['options'], {'deep': {'er': 'yes'}})

    def test_variables(self):
        self.env['RHUN_DBG_VAR'] = 'from env'
        body = ('p = ${project}\npn = ${projectName}\nf = ${file}\nfd = ${fileDir}\nfn = ${fileName}\n'
                'fs = ${fileStem}\nfe = ${fileExt}\nrf = ${relativeFile}\nl = ${line}\nc = ${column}\n'
                'sel = ${selection}\nh = ${home}\ne = ${env:RHUN_DBG_VAR}\nd = $$5 and $5\n')
        args, out = self.args_for(body, extra=['key ctrl+Home', 'key Down', 'key shift+Right',
                                               'key shift+Right'])
        a = self.src.as_posix()
        self.assertEqual(args['p'], self.proj.as_posix())
        self.assertEqual(args['pn'], 'proj')
        self.assertEqual(args['f'], a)
        self.assertEqual(args['fd'], self.proj.as_posix())
        self.assertEqual(args['fn'], 'a.c')
        self.assertEqual(args['fs'], 'a')
        self.assertEqual(args['fe'], '.c')
        self.assertEqual(args['rf'], 'a.c')
        self.assertEqual(args['l'], '2')
        self.assertEqual(args['c'], '3')
        self.assertEqual(args['sel'], '  ')
        self.assertEqual(args['h'], self.work.as_posix())
        self.assertEqual(args['e'], 'from env')
        self.assertEqual(args['d'], '$5 and $5')

    def test_errors_name_the_line(self):
        cases = [('stopOnEntry = maybe\n', 'error launch.ini line 4: `stopOnEntry` must be true or false'),
                 ('count = 1.5\n', 'error launch.ini line 4: `count` must be a whole number'),
                 ('mode = fast\n', 'error launch.ini line 4: `mode` must be one of: debug test'),
                 ('env = x\n', 'error launch.ini line 4: `env` is written as KEY.NAME = value'),
                 ('x = ${nope}\n', 'error launch.ini line 4: unknown variable ${nope}'),
                 ('x = ${project\n', 'error launch.ini line 4: a ${ without its }'),
                 ('a = 1\na.b = 2\n', 'error launch.ini line 5: `a.b` conflicts with another key '
                                      '(a value, an object and a list at once)'),
                 ('args = "open\n', 'error launch.ini line 4: `args` has an unclosed quote'),
                 ('request = later\n', 'error launch.ini line 4: `request` must be launch or attach')]
        for body, message in cases:
            with self.subTest(body=body):
                if self.log.exists():
                    self.log.unlink()
                args, out = self.args_for(body)
                self.assertIn(message, out)
                self.assertIsNone(args, 'nothing was launched')

    def test_file_variable_without_a_file(self):
        args, out = self.args_for('f = ${file}\n', files=())
        self.assertIn('error launch.ini line 4: ${file} needs an open file', out)

    def test_attach_and_names(self):
        self.scenario()
        self.launch_ini('# a comment\n[First]\ntype = fake\nprogram = scenario.json\n\n'
                        '; another\n[Attach]\ntype = fake\nrequest = attach\nprogram = scenario.json\n'
                        '[Helper]\ntype = fake\nhidden = yes\n')
        out = self.run_editor(['print-configs', *self.start('Attach'), 'wait-debug ended'])
        self.assertEqual([l for l in out if l.startswith('config=')], ['config=First', 'config=Attach'])
        args = self.args_sent()
        self.assertEqual(args['request'], 'attach')
        self.assertIn('attach', [r.split(' ')[0] for r in self.requests()])

    def test_kept_keys_are_not_arguments(self):
        args, out = self.args_for('before = build\nafter = clean\n')
        for key in ('before', 'after', 'hidden', 'server', 'compound'):
            self.assertNotIn(key, args)

    def argv(self):
        for line in self.dap_log():
            if line.startswith('argv '):
                return line[5:].split(' ')
        return None

    def test_config_values_in_the_adapter_command(self):
        # the fake debugger's args end with --count ${config:count|42} (review: cn_find's index)
        args, out = self.args_for('count = 123\n')
        self.assertEqual(self.argv()[-2:], ['--count', '123'])
        self.log.unlink()
        args, out = self.args_for('')
        self.assertEqual(self.argv()[-2:], ['--count', '42'])

    def test_integers_without_leading_zeros(self):
        # review: count = 007 was sent as invalid JSON
        for text, value in (('007', 7), ('-0', 0), ('-012', -12), ('0', 0)):
            with self.subTest(text=text):
                if self.log.exists():
                    self.log.unlink()
                args, out = self.args_for('count = %s\n' % text)
                self.assertEqual(args['count'], value, out)


if __name__ == '__main__':
    unittest.main()
