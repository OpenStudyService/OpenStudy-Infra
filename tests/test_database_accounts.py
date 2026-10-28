import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("accounts", Path(__file__).resolve().parents[1] / "scripts/provision-database-accounts.py")
accounts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(accounts)


class DatabaseAccountTests(unittest.TestCase):
    def test_accepts_symbols_in_password(self):
        sql = accounts.accounts_sql("openstudy", "m" * 40, "TestOnly#Password&With!Symbols_123456789")
        self.assertIn("CREATE USER", sql)

    def test_rejects_sql_injection_and_shared_passwords(self):
        for database, first, second in [
            ("openstudy;DROP", "a" * 40, "b" * 40),
            ("openstudy", "'" + "a" * 40, "b" * 40),
            ("openstudy", "\\" + "a" * 40, "b" * 40),
            ("openstudy", "a" * 40, "a" * 40),
        ]:
            with self.subTest(database=database), self.assertRaises(ValueError):
                accounts.accounts_sql(database, first, second)


if __name__ == "__main__":
    unittest.main()
