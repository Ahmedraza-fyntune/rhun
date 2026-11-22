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

    def test_large_project_with_anchored_vendor_rule(self):
        # Test reproducing Laravel project setup with /vendor and many files
        lar_proj = self.home / 'laravel_proj'
        lar_proj.mkdir()
        gitignore_content = (
            "*.log\n"
            ".DS_Store\n"
            ".env\n"
            ".env.backup\n"
            ".env.production\n"
            ".phpactor.json\n"
            "/.agents\n"
            ".phpunit.result.cache\n"
            "/.fleet\n"
            "/.idea\n"
            "/.nova\n"
            "/Temp\n"
            "/.phpunit.cache\n"
            "/.vscode\n"
            "/.zed\n"
            "/auth.json\n"
            "/node_modules\n"
            "/public/build\n"
            "/public/hot\n"
            "/public/storage\n"
            "/storage/*.key\n"
            "/storage/pail\n"
            "/vendor\n"
            "Homestead.json\n"
            "Homestead.yaml\n"
            "Thumbs.db\n"
        )
        (lar_proj / '.gitignore').write_text(gitignore_content, encoding='utf-8')

        # Project files matching query
        (lar_proj / 'tests' / 'Feature').mkdir(parents=True)
        (lar_proj / 'tests' / 'Feature' / 'DivisionExamTimetableTest.php').write_text('<?php', encoding='utf-8')
        (lar_proj / 'tests' / 'Feature' / 'DisciplineModuleTest.php').write_text('<?php', encoding='utf-8')
        (lar_proj / 'app' / 'Casts').mkdir(parents=True)
        (lar_proj / 'app' / 'Casts' / 'SafeEncryptedString.php').write_text('<?php', encoding='utf-8')

        # Vendor files matching query (must NOT appear in results)
        (lar_proj / 'vendor' / 'nikic' / 'php-parser').mkdir(parents=True)
        (lar_proj / 'vendor' / 'nikic' / 'php-parser' / 'ConstExprEvaluationException.php').write_text('<?php', encoding='utf-8')
        (lar_proj / 'vendor' / 'symfony' / 'clock').mkdir(parents=True)
        (lar_proj / 'vendor' / 'symfony' / 'clock' / 'ClockSensitiveTrait.php').write_text('<?php', encoding='utf-8')

        # Hundreds of other files to stress rule count and steps
        for i in range(500):
            d = lar_proj / f'dir{i}'
            d.mkdir()
            (d / f'file{i}.txt').write_text('data', encoding='utf-8')

        script = self.home / 'lar_test.rsc'
        script.write_text('cmd quick_open\ntype teenet\nprint-palette\nquit\n', encoding='utf-8')

        r = subprocess.run(
            [str(EXE), lar_proj.as_posix(), '--headless', '1400x860', '--script', script.as_posix()],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=20
        )
        self.assertEqual(r.returncode, 0, f"Error: {r.stderr}\nStdout: {r.stdout}")

        # Vendor files must NOT appear
        self.assertNotIn('vendor', r.stdout)
        self.assertNotIn('ConstExprEvaluationException', r.stdout)
        self.assertNotIn('ClockSensitiveTrait', r.stdout)

        # Expected project files must appear
        self.assertIn('DivisionExamTimetableTest.php', r.stdout)
        self.assertIn('DisciplineModuleTest.php', r.stdout)
        self.assertIn('SafeEncryptedString.php', r.stdout)


if __name__ == '__main__':
    unittest.main()
