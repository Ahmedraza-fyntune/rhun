#!/usr/bin/env python3
"""Test built-in formatters: JSON, XML, SQL, PHP, INI."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
EXE = ROOT / 'build' / 'windows' / 'rhun.exe'
if not EXE.is_file():
    EXE = ROOT / 'build' / 'rhun'


class TestFormatters(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-formatters-')
        self.work = Path(self.tmp.name)
        self.proj = self.work / 'proj'
        self.proj.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def run_rhun(self, actions, files=()):
        script = self.work / 'actions.rsc'
        opens = [f'open {(self.proj / f).as_posix()}' for f in files]
        script.write_text('\n'.join(['wait 100', *opens, *actions, 'quit']) + '\n', encoding='utf-8')
        env = dict(os.environ)
        env['HOME'] = str(self.work)
        env['USERPROFILE'] = str(self.work)
        res = subprocess.run([str(EXE), self.proj.as_posix(), '--headless', '1000x600',
                             '--scale', '1', '--script', script.as_posix()],
                             env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(res.returncode, 0, f"rhun failed: {res.stderr}\nstdout: {res.stdout}")
        return res.stdout.splitlines()

    def test_json_formatter(self):
        f = self.proj / 'test.json'
        f.write_text('{"name":"rhun","features":["fast","clean",{"level":1}],"empty_obj":{},"empty_arr":[],"escaped":"hello \\"world\\""}', encoding='utf-8')
        self.run_rhun(['cmd format_document', 'wait 100', 'cmd save', 'wait 100'], files=('test.json',))
        formatted = f.read_text(encoding='utf-8')
        self.assertIn('"name": "rhun"', formatted)
        self.assertIn('"features": [', formatted)
        self.assertIn('"fast",', formatted)
        self.assertIn('"clean",', formatted)
        self.assertIn('"level": 1', formatted)
        self.assertIn('"empty_obj": {}', formatted)
        self.assertIn('"empty_arr": []', formatted)
        self.assertIn('"escaped": "hello \\"world\\""', formatted)

    def test_xml_formatter(self):
        f = self.proj / 'test.xml'
        f.write_text('<?xml version="1.0"?><root><!-- comment --><item id="1"><name>First</name></item><empty/><item id="2"><name>Second</name></item></root>', encoding='utf-8')
        self.run_rhun(['cmd format_document', 'wait 100', 'cmd save', 'wait 100'], files=('test.xml',))
        formatted = f.read_text(encoding='utf-8')
        self.assertIn('<?xml version="1.0"?>', formatted)
        self.assertIn('<root>', formatted)
        self.assertIn('<!-- comment -->', formatted)
        self.assertIn('<item id="1">', formatted)
        self.assertIn('<name>', formatted)
        self.assertIn('First', formatted)
        self.assertIn('<empty/>', formatted)
        self.assertIn('</item>', formatted)
        self.assertIn('</root>', formatted)

    def test_sql_formatter(self):
        f = self.proj / 'test.sql'
        f.write_text('select u.id, u.name, o.total from users u left join orders o on u.id = o.user_id where u.active = 1 and o.total > 100 order by o.total desc limit 10;', encoding='utf-8')
        self.run_rhun(['cmd format_document', 'wait 100', 'cmd save', 'wait 100'], files=('test.sql',))
        formatted = f.read_text(encoding='utf-8')
        self.assertIn('SELECT', formatted)
        self.assertIn('u.id,', formatted)
        self.assertIn('u.name,', formatted)
        self.assertIn('o.total', formatted)
        self.assertIn('FROM users u', formatted)
        self.assertIn('LEFT JOIN orders o ON u.id = o.user_id', formatted)
        self.assertIn('WHERE u.active = 1', formatted)
        self.assertIn('AND o.total > 100', formatted)
        self.assertIn('ORDER BY o.total DESC', formatted)
        self.assertIn('LIMIT 10;', formatted)

    def test_php_formatter(self):
        f = self.proj / 'test.php'
        f.write_text('<?php\nclass Calculator {\npublic function add($a,$b){if($a>0){return $a+$b;}else{return $b;}}\n}\n', encoding='utf-8')
        self.run_rhun(['cmd format_document', 'wait 100', 'cmd save', 'wait 100'], files=('test.php',))
        formatted = f.read_text(encoding='utf-8')
        self.assertIn('class Calculator {', formatted)
        self.assertIn('public function add($a, $b) {', formatted)
        self.assertIn('if ($a > 0) {', formatted)
        self.assertIn('return $a + $b;', formatted)
        self.assertIn('} else {', formatted)
        self.assertIn('return $b;', formatted)

    def test_ini_formatter(self):
        f = self.proj / 'test.ini'
        f.write_text('; general settings\n[server]\nhost=127.0.0.1\nport=8080\n# database settings\n[database]\nname=test\nuser=root\n', encoding='utf-8')
        self.run_rhun(['cmd format_document', 'wait 100', 'cmd save', 'wait 100'], files=('test.ini',))
        formatted = f.read_text(encoding='utf-8')
        self.assertIn('; general settings', formatted)
        self.assertIn('[server]', formatted)
        self.assertIn('host = 127.0.0.1', formatted)
        self.assertIn('port = 8080', formatted)
        self.assertIn('# database settings', formatted)
        self.assertIn('[database]', formatted)
        self.assertIn('name = test', formatted)
        self.assertIn('user = root', formatted)

    def test_explicit_commands(self):
        f = self.proj / 'data.txt'
        f.write_text('{"alpha":1,"beta":2}', encoding='utf-8')
        self.run_rhun(['cmd format_json', 'wait 100', 'cmd save', 'wait 100'], files=('data.txt',))
        formatted = f.read_text(encoding='utf-8')
        self.assertIn('"alpha": 1', formatted)
        self.assertIn('"beta": 2', formatted)

    def test_format_undo(self):
        f = self.proj / 'undo.json'
        original = '{"x":1,"y":2}\n'
        f.write_text(original, encoding='utf-8')
        # Format, verify formatted, then undo and save
        self.run_rhun(['cmd format_document', 'wait 100', 'cmd undo', 'wait 100', 'cmd save', 'wait 100'], files=('undo.json',))
        restored = f.read_text(encoding='utf-8')
        self.assertEqual(restored, original)


if __name__ == '__main__':
    unittest.main()
