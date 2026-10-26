import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/compare-v1-migrations.py"


class CompareV1MigrationsTests(unittest.TestCase):
    def compare(self, infra, backend):
        with tempfile.TemporaryDirectory() as temporary:
            paths = [Path(temporary) / name for name in ("infra.sql", "backend.sql")]
            for path, content in zip(paths, (infra, backend)):
                path.write_bytes(content)
            result = subprocess.run(
                [sys.executable, str(SCRIPT), *map(str, paths)],
                capture_output=True, text=True,
            )
            self.assertEqual(paths[0].read_bytes(), infra)
            self.assertEqual(paths[1].read_bytes(), backend)
        return result.returncode, json.loads(result.stdout)

    def test_identical_files_report_raw_sha256(self):
        content = b"SELECT 1;\n"
        code, report = self.compare(content, content)
        self.assertEqual(code, 0)
        self.assertEqual(report["comparison"], "identical")
        self.assertEqual(report["infra"]["sha256"], hashlib.sha256(content).hexdigest())
        self.assertEqual(report["infra"]["bytes"], len(content))

    def test_final_newline_difference_keeps_distinct_hashes(self):
        code, report = self.compare(b"SELECT 1;", b"SELECT 1;\n")
        self.assertEqual(code, 0)
        self.assertEqual(report["comparison"], "line_endings_only")
        self.assertNotEqual(report["infra"]["sha256"], report["backend"]["sha256"])
        self.assertFalse(report["infra"]["ends_with_newline"])
        self.assertTrue(report["backend"]["ends_with_newline"])

    def test_line_terminators_can_differ(self):
        for terminator in (b"\r\n", b"\r"):
            with self.subTest(terminator=terminator):
                code, report = self.compare(b"-- note\nSELECT 1;\n", terminator.join((b"-- note", b"SELECT 1;")))
                self.assertEqual(code, 0)
                self.assertEqual(report["comparison"], "line_endings_only")

    def test_sql_spaces_comments_and_blank_lines_are_not_ignored(self):
        original = b"-- note\nSELECT 1;\n"
        for changed in (
            b"-- note\nSELECT 2;\n",
            b"-- note\nSELECT  1;\n",
            b"-- changed\nSELECT 1;\n",
            b"-- note\n\nSELECT 1;\n",
            original + b"\n",
        ):
            with self.subTest(changed=changed):
                code, report = self.compare(original, changed)
                self.assertEqual(code, 1)
                self.assertEqual(report["comparison"], "different")

    def test_missing_file_reports_error_without_traceback(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "missing.sql"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(path), str(path)],
                capture_output=True, text=True,
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("Cannot read infra SQL file", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
