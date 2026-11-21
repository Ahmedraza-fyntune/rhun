#!/usr/bin/env python3
"""Tests for respecting .gitignore rules in file search (Issue #128)."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', str(ROOT / 'build/rhun'))).resolve()


class GitignoreSearchTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-gitignore-')
        self.home = Path(self.tmp.name)
        self.project = self.home / 'project'
        self.project.mkdir()

        # Create project files
        (self.project / '.gitignore').write_text(
            "node_modules/\n"
            "vendor/\n"
            "dist/\n"
            ".env\n"
            "*.log\n"
            "!important.log\n"
            "/gen\n",
            encoding='utf-8'
        )

        # Included files
        (self.project / 'src').mkdir()
        (self.project / 'src' / 'index.js').write_text("console.log('hello target_code');\n", encoding='utf-8')
        (self.project / 'src' / 'gen').mkdir()
        (self.project / 'src' / 'gen' / 'nested.txt').write_text("nested gen file target_code\n", encoding='utf-8')
        (self.project / '.env.example').write_text("APP_KEY=example target_code\n", encoding='utf-8')
        (self.project / 'important.log').write_text("important log target_code\n", encoding='utf-8')

        # Ignored files / directories
        (self.project / 'node_modules' / 'pkg').mkdir(parents=True)
        (self.project / 'node_modules' / 'pkg' / 'mod.js').write_text("ignored node target_code\n", encoding='utf-8')

        (self.project / 'vendor' / 'lib').mkdir(parents=True)
        (self.project / 'vendor' / 'lib' / 'lib.php').write_text("ignored vendor target_code\n", encoding='utf-8')

        (self.project / 'dist').mkdir()
        (self.project / 'dist' / 'bundle.js').write_text("ignored dist target_code\n", encoding='utf-8')

        (self.project / '.env').write_text("SECRET=hidden target_code\n", encoding='utf-8')
        (self.project / 'debug.log').write_text("debug log target_code\n", encoding='utf-8')

        (self.project / 'gen').mkdir()
        (self.project / 'gen' / 'output.txt').write_text("ignored root gen target_code\n", encoding='utf-8')

        # Nested directory with its own .gitignore
        (self.project / 'docs').mkdir()
        (self.project / 'docs' / '.gitignore').write_text("*.draft\n", encoding='utf-8')
        (self.project / 'docs' / 'guide.md').write_text("# Guide target_code\n", encoding='utf-8')
        (self.project / 'docs' / 'todo.draft').write_text("draft todo target_code\n", encoding='utf-8')

        self.env = dict(
            os.environ,
            HOME=self.home.as_posix(),
            XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
            XDG_STATE_HOME=(self.home / 'state').as_posix(),
        )

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, commands):
        script = self.home / 'test.rsc'
        script.write_text('\n'.join(commands) + '\n', encoding='utf-8')
        r = subprocess.run(
            [str(EXE), self.project.as_posix(), '--headless', '1400x860', '--script', script.as_posix()],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertEqual(r.returncode, 0, f"Error: {r.stderr}\nStdout: {r.stdout}")
        return r.stdout

    def test_quick_open_respects_gitignore(self):
        out = self.run_script([
            'cmd quick_open',
            'print-palette',
            'quit'
        ])

        # Ignored files must not appear in Quick Open results
        self.assertNotIn('node_modules', out)
        self.assertNotIn('vendor', out)
        self.assertNotIn('dist', out)
        self.assertNotIn('debug.log', out)
        self.assertNotIn('gen/output.txt', out)
        self.assertNotIn('docs/todo.draft', out)
        lines = [line.strip() for line in out.splitlines()]
        self.assertNotIn('.env', lines)

        # Included files must appear
        self.assertIn('src/index.js', out)
        self.assertIn('src/gen/nested.txt', out)
        self.assertIn('.env.example', out)
        self.assertIn('important.log', out)
        self.assertIn('docs/guide.md', out)

    def test_find_in_files_respects_gitignore(self):
        out = self.run_script([
            'cmd find_in_files',
            'type target_code',
            'wait-grep',
            'print-palette',
            'quit'
        ])

        # Ignored files must not be matched in grep results
        self.assertNotIn('node_modules', out)
        self.assertNotIn('vendor', out)
        self.assertNotIn('dist', out)
        self.assertNotIn('debug.log', out)
        self.assertNotIn('ignored root gen', out)
        self.assertNotIn('draft todo', out)

        # Allowed files must be matched
        self.assertIn('console.log', out)
        self.assertIn('nested gen file', out)
        self.assertIn('APP_KEY=example', out)
        self.assertIn('important log', out)
        self.assertIn('# Guide target_code', out)

    def test_include_ignored_option(self):
        # Configure files.include_ignored = true
        config_dir = self.home / 'config' / 'rhun'
        config_dir.mkdir(parents=True, exist_ok=True)
        (config_dir / 'config').write_text(
            "[files]\n"
            "include_ignored = true\n",
            encoding='utf-8'
        )

        out = self.run_script([
            'cmd quick_open',
            'print-palette',
            'quit'
        ])

        # When include_ignored is true, gitignored files appear
        self.assertIn('debug.log', out)
        self.assertIn('gen/output.txt', out)
        self.assertIn('docs/todo.draft', out)


if __name__ == '__main__':
    unittest.main()
