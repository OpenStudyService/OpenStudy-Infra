import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "check_database", Path(__file__).resolve().parents[1] / "scripts/check-database.py")
database = importlib.util.module_from_spec(spec)
spec.loader.exec_module(database)


class DatabaseDumpTests(unittest.TestCase):
    def test_preserves_binary_literals_and_windows_line_endings(self):
        data = b"INSERT INTO `example` VALUES ('\x80\xff\\0\\r\\n');\r\n"
        definer = b"/*!50013 DEFINER=`openstudy_app`@`localhost` SQL SECURITY DEFINER */\r\n"
        restored, count = database.prepare_local_dump(data + definer)
        self.assertEqual(count, 1)
        self.assertEqual(restored, data + b"/*!50013 SQL SECURITY INVOKER */\r\n")
        self.assertEqual(database.prepare_local_dump(data), (data, 0))

    def test_does_not_replace_definer_text_inside_a_row(self):
        data = b"INSERT INTO `example` VALUES ('/*!50013 DEFINER=`u`@`h` SQL SECURITY DEFINER */');\n"
        self.assertEqual(database.prepare_local_dump(data), (data, 0))

    def test_restore_suppresses_sensitive_mysql_diagnostics(self):
        failure = subprocess.CompletedProcess([], 1, b"private-row", b"ERROR 1064 (42000) at line 42: secret-row")
        with patch.object(database, "run"), patch.object(database.subprocess, "run", return_value=failure) as execute:
            with self.assertRaisesRegex(RuntimeError, "MySQL error 1064.*Input line 42") as error:
                database.restore_dump("isolated", b"private-row")
        self.assertNotIn("secret-row", str(error.exception))
        self.assertNotIn("private-row", str(error.exception))
        arguments = execute.call_args.args[0]
        self.assertIn("--binary-mode", arguments)
        self.assertIn("--local-infile=0", arguments)
        self.assertIn("--skip-reconnect", arguments)

    def test_composite_foreign_key_ignores_rows_with_null_components(self):
        statements = []

        def query(sql):
            statements.append(sql)
            if "information_schema.tables" in sql:
                return "child\tBASE TABLE\nparent\tBASE TABLE\nexample_view\tVIEW"
            if "key_column_usage" in sql:
                return "child\tfk_example\ta\tparent\ta\nchild\tfk_example\tb\tparent\tb"
            if "NOT EXISTS" in sql:
                return "0"
            return "2"

        result = database.schema_summary(query)
        check = next(sql for sql in statements if "NOT EXISTS" in sql)
        self.assertIn("c.`a` IS NOT NULL AND c.`b` IS NOT NULL", check)
        self.assertIn("c.`a`=p.`a` AND c.`b`=p.`b`", check)
        self.assertEqual(result["foreign_keys_checked"], 1)
        self.assertEqual(result["rows_total"], 4)


if __name__ == "__main__":
    unittest.main()
