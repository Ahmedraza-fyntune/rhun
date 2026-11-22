#!/usr/bin/env python3
"""Tests for Codebase Insights: File, Folder & Project Statistics."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', str(ROOT / 'build/rhun'))).resolve()


class CodebaseInsightsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rhun-insights-')
        self.home = Path(self.tmp.name)
        self.project = self.home / 'project'
        self.project.mkdir()

        self.env = dict(
            os.environ,
            HOME=self.home.as_posix(),
            XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
            XDG_STATE_HOME=(self.home / 'state').as_posix(),
        )

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, commands, target_project=None):
        proj = target_project or self.project
        script = self.home / 'test.rsc'
        script.write_text('\n'.join(commands) + '\n', encoding='utf-8')
        r = subprocess.run(
            [str(EXE), proj.as_posix(), '--headless', '1400x860', '--script', script.as_posix()],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=20
        )
        self.assertEqual(r.returncode, 0, f"Error: {r.stderr}\nStdout: {r.stdout}")
        return r.stdout

    def test_line_counting_and_comment_classification(self):
        """Test line counting, LF/CRLF/CR, single & multiline comments, and invariants."""
        # 1. Python file:
        # Total: 8 lines
        # Code: 3
        # Comment: 3 (single-line # comments)
        # Blank: 2
        py_content = (
            "# Module header comment\n"
            "\n"
            "def add(a, b):\n"
            "    # Docstring line\n"
            "    res = a + b\n"
            "    return res\n"
            "\n"
            "# End of file comment\n"
        )
        (self.project / 'calc.py').write_text(py_content, encoding='utf-8')

        # 2. C file with CRLF endings:
        # Total: 12 lines
        # Code: 5
        # Comment: 5 (1 // comment, 4 in /* */ block)
        # Blank: 2
        c_content = (
            "// C file header\r\n"
            "\r\n"
            "#include <stdio.h>\r\n"
            "/* Multi-line\r\n"
            " * comment block\r\n"
            " */\r\n"
            "int main(void) {\r\n"
            "    printf(\"hello\\n\");\r\n"
            "    return 0;\r\n"
            "}\r\n"
            "\r\n"
            "// Trailing comment\r\n"
        )
        (self.project / 'main.c').write_bytes(c_content.encode('utf-8'))

        # 3. Assembly file with CR endings:
        # Total: 8 lines
        # Code: 4
        # Comment: 2
        # Blank: 2
        asm_content = (
            "# ASM file\r"
            "\r"
            "global _start\r"
            "_start:\r"
            "    mov eax, 1\r"
            "    xor ebx, ebx\r"
            "\r"
            "# exit syscall\r"
        )
        (self.project / 'start.s').write_bytes(asm_content.encode('utf-8'))

        out = self.run_script([
            'cmd codebase_insights',
            'print-doc',
            'quit'
        ])

        self.assertIn('# Codebase Insights', out)
        self.assertIn('## Project Overview', out)
        self.assertIn('## File Type Distribution', out)
        self.assertIn('## Largest Files', out)
        self.assertIn('## Largest Directories', out)
        self.assertIn('## Exclusion Rules', out)

        # Parse metrics from Project Overview
        tot_lines_m = re.search(r'- \*\*Total Lines\*\*: (\d+)', out)
        code_lines_m = re.search(r'- \*\*Code Lines\*\*: (\d+)', out)
        comm_lines_m = re.search(r'- \*\*Comment Lines\*\*: (\d+)', out)
        blank_lines_m = re.search(r'- \*\*Blank Lines\*\*: (\d+)', out)

        self.assertIsNotNone(tot_lines_m)
        self.assertIsNotNone(code_lines_m)
        self.assertIsNotNone(comm_lines_m)
        self.assertIsNotNone(blank_lines_m)

        tot_lines = int(tot_lines_m.group(1))
        code_lines = int(code_lines_m.group(1))
        comm_lines = int(comm_lines_m.group(1))
        blank_lines = int(blank_lines_m.group(1))

        # Check invariant: Total Lines == Code Lines + Comment Lines + Blank Lines
        self.assertEqual(tot_lines, code_lines + comm_lines + blank_lines)
        self.assertEqual(tot_lines, 8 + 12 + 8)
        self.assertEqual(code_lines, 3 + 5 + 4)
        self.assertEqual(comm_lines, 3 + 5 + 2)
        self.assertEqual(blank_lines, 2 + 2 + 2)

    def test_binary_file_detection(self):
        """Binary files must contribute to count & storage, but 0 lines of code."""
        # Text file
        (self.project / 'hello.txt').write_text("Hello world\nSecond line\n", encoding='utf-8')

        # Binary file by extension
        png_data = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06' + b'\x00' * 500
        (self.project / 'image.png').write_bytes(png_data)

        # Binary file with NUL byte in first 8KB despite unknown extension
        custom_bin = b'CUSTOMHEADER' + b'\x00\x01\x02\x03' + b'DATA' * 200
        (self.project / 'sample.dat').write_bytes(custom_bin)

        out = self.run_script([
            'cmd codebase_insights',
            'print-doc',
            'quit'
        ])

        # Project overview: Total Files = 3 (Text: 1, Binary: 2)
        self.assertIn('- **Total Files**: 3 (Text: 1, Binary: 2)', out)
        self.assertIn('- **Total Lines**: 2', out)
        self.assertIn('- **Code Lines**: 2', out)

        # File type table should list Binary
        self.assertIn('Binary', out)

    def test_exclusion_rules(self):
        """Default exclusions (.git, node_modules, etc.) and gitignore rules must be respected."""
        # Included source
        (self.project / 'src').mkdir()
        (self.project / 'src' / 'app.py').write_text("print('running app')\n", encoding='utf-8')

        # Default excluded directory
        (self.project / 'node_modules' / 'lib').mkdir(parents=True)
        (self.project / 'node_modules' / 'lib' / 'pkg.js').write_text("module.exports = {};\n", encoding='utf-8')

        (self.project / 'dist').mkdir()
        (self.project / 'dist' / 'bundle.js').write_text("console.log('dist');\n", encoding='utf-8')

        (self.project / '__pycache__').mkdir()
        (self.project / '__pycache__' / 'app.cpython-311.pyc').write_bytes(b'\x00\x00\x00\x00')

        # .gitignore rules
        (self.project / '.gitignore').write_text("*.log\n/temp/\n", encoding='utf-8')
        (self.project / 'debug.log').write_text("debug log entry\n", encoding='utf-8')
        (self.project / 'temp').mkdir()
        (self.project / 'temp' / 'scratch.txt').write_text("scratch content\n", encoding='utf-8')

        out = self.run_script([
            'cmd codebase_insights',
            'print-doc',
            'quit'
        ])

        # Ignored files/folders must NOT be included in metrics
        self.assertNotIn('node_modules', out.split('## Exclusion Rules')[0])
        self.assertNotIn('bundle.js', out)
        self.assertNotIn('debug.log', out)
        self.assertNotIn('scratch.txt', out)

        # Only src/app.py and .gitignore are included
        self.assertIn('src/app.py', out)

    def test_custom_exclude_setting(self):
        """Custom setting 'insights.exclude' must exclude specified paths."""
        (self.project / 'docs').mkdir()
        (self.project / 'docs' / 'index.md').write_text("# Documentation\n", encoding='utf-8')

        (self.project / 'custom_ignore').mkdir()
        (self.project / 'custom_ignore' / 'test.py').write_text("print('should be excluded')\n", encoding='utf-8')

        # Configure custom exclusion in settings (INI format)
        cfg_dir = self.home / 'config' / 'rhun'
        cfg_dir.mkdir(parents=True)
        (cfg_dir / 'config').write_text("[files]\ninsights_exclude = custom_ignore\n", encoding='utf-8')

        out = self.run_script([
            'cmd codebase_insights',
            'print-doc',
            'quit'
        ])

        self.assertNotIn('custom_ignore', out.split('## Exclusion Rules')[0])
        self.assertIn('docs/index.md', out)
        self.assertIn('custom_ignore', out.split('## Exclusion Rules')[1])

    def test_largest_files_and_directories_ranking(self):
        """Largest files and largest directories tables must be ordered descending by size."""
        (self.project / 'small').mkdir()
        (self.project / 'small' / 'file_s.txt').write_text("small\n", encoding='utf-8')  # 6 bytes

        (self.project / 'large').mkdir()
        (self.project / 'large' / 'file_l.txt').write_text("A" * 50000 + "\n", encoding='utf-8')  # 50001 bytes

        (self.project / 'medium').mkdir()
        (self.project / 'medium' / 'file_m.txt').write_text("B" * 10000 + "\n", encoding='utf-8')  # 10001 bytes

        out = self.run_script([
            'cmd codebase_insights',
            'print-doc',
            'quit'
        ])

        # Verify Largest Files section order: file_l > file_m > file_s
        large_files_sec = out.split('## Largest Files')[1].split('## Largest Directories')[0]
        pos_l = large_files_sec.find('file_l.txt')
        pos_m = large_files_sec.find('file_m.txt')
        pos_s = large_files_sec.find('file_s.txt')

        self.assertTrue(pos_l >= 0 and pos_m >= 0 and pos_s >= 0)
        self.assertTrue(pos_l < pos_m < pos_s, "Files are not sorted descending by size")

        # Verify Largest Directories section order: large > medium > small
        large_dirs_sec = out.split('## Largest Directories')[1].split('## Exclusion Rules')[0]
        dir_l = large_dirs_sec.find('`large`')
        dir_m = large_dirs_sec.find('`medium`')
        dir_s = large_dirs_sec.find('`small`')

        self.assertTrue(dir_l >= 0 and dir_m >= 0 and dir_s >= 0)
        self.assertTrue(dir_l < dir_m < dir_s, "Directories are not sorted descending by size")

    def test_target_folder_insights(self):
        """Context menu action targeting a subfolder generates insights restricted to that folder."""
        (self.project / 'sub').mkdir()
        (self.project / 'sub' / 'subfile.py').write_text("print('in sub')\n", encoding='utf-8')
        (self.project / 'outside.txt').write_text("outside\n", encoding='utf-8')

        sub_path = (self.project / 'sub').as_posix()
        out = self.run_script([
            'cmd codebase_insights',
            'print-doc',
            'quit'
        ], target_project=self.project / 'sub')

        self.assertIn('- **Root Path**: `' + sub_path + '`', out)
        self.assertIn('subfile.py', out)
        self.assertNotIn('outside.txt', out)

    def test_explorer_hover_tooltips_and_startup_stability(self):
        """Hovering over explorer rows generates single-line tooltips with file/folder counts without crashing."""
        sub = self.project / 'subfolder'
        sub.mkdir()
        (sub / 'nested.py').write_text("print('nested')\n", encoding='utf-8')
        (sub / 'inner').mkdir()
        (self.project / 'code.py').write_text("# sample\nprint('hello')\n", encoding='utf-8')
        (self.project / 'binary.bin').write_bytes(b'\x00\x01\x02\x03')

        # Hover over folder and file rows and verify tooltips and stability
        out = self.run_script([
            'move 60 92',
            'wait 650',
            'print-tip',
            'move 60 116',
            'wait 650',
            'print-tip',
            'move 60 140',
            'wait 650',
            'print-tip',
            'wait 5500',  # exceed 5s update timer to verify background timers and stability
            'quit'
        ])

        self.assertIn('tip=Folder:', out)
        self.assertIn('tip=File:', out)
        self.assertIn('code.py', out)
        self.assertIn('Python', out)
        self.assertTrue('file' in out and 'folder' in out)


if __name__ == '__main__':
    unittest.main()
