import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import tomllib
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/migrate-database.py"
spec = importlib.util.spec_from_file_location("migrate_database", SCRIPT)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class DatabaseMigrationTests(unittest.TestCase):
    def test_config_requires_verified_tls_and_utc(self):
        config = migration.flyway_configuration(
            "test.rds.amazonaws.com", "openstudy", "admin", "dummy", Path("/run/sql"), Path("/run/rds.pem"),
        )
        parsed = tomllib.loads(config)
        environment = parsed["environments"]["default"]
        settings = parsed["flyway"]
        query = parse_qs(urlsplit(environment["url"][5:]).query)
        self.assertEqual(query["sslMode"], ["verify-full"])
        self.assertEqual(query["serverSslCert"], ["/run/rds.pem"])
        self.assertIn("serverSslCert=/run/rds.pem", environment["url"])
        self.assertTrue(settings["cleanDisabled"])
        self.assertFalse(settings["baselineOnMigrate"])
        self.assertTrue(settings["validateOnMigrate"])
        self.assertEqual(environment["initSql"], "SET time_zone = '+00:00'")

    def test_password_cannot_inject_a_configuration_setting(self):
        config = migration.flyway_configuration(
            "test.rds.amazonaws.com", "openstudy", "admin", " leading\\secret\nflyway.cleanDisabled=false\r\t",
            Path("/run/sql"), Path("/run/ca.pem"),
        )
        parsed = tomllib.loads(config)
        self.assertEqual(parsed["environments"]["default"]["password"], " leading\\secret\nflyway.cleanDisabled=false\r\t")
        self.assertTrue(parsed["flyway"]["cleanDisabled"])

    def test_password_cannot_be_treated_as_a_flyway_resolver(self):
        config = migration.flyway_configuration("host", "openstudy", "admin", "$fixture", Path("sql"), Path("ca"))
        self.assertEqual(tomllib.loads(config)["environments"]["default"]["password"], "$$fixture")

    def test_reject_connection_string_injection(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid database"):
            migration.flyway_configuration("host?sslMode=disable", "openstudy", "admin", "dummy", Path("sql"), Path("ca"))

    def test_refuse_modified_sql(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "V1__test.sql"
            source.write_text("SELECT 1;")
            with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
                migration.verify_digest(source, "0" * 64)

    def test_extract_java_files_without_bundled_x86_runtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "flyway.tar.gz"
            with tarfile.open(archive, "w:gz") as bundle:
                for name in ["flyway", "lib/core.jar", "jre/bin/java", "drivers/legacy.jar"]:
                    member = tarfile.TarInfo(f"flyway-{migration.FLYWAY_VERSION}/{name}")
                    member.size = 4
                    bundle.addfile(member, io.BytesIO(b"test"))
            stage = root / "stage"
            stage.mkdir()
            with patch.object(migration, "verify_digest"):
                migration.extract_flyway(archive, stage)
            self.assertTrue((stage / "flyway").is_file())
            self.assertTrue((stage / "lib/core.jar").is_file())
            self.assertFalse((stage / "jre").exists())
            self.assertFalse((stage / "drivers").exists())

    def test_reject_archive_path_escape(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "flyway.tar.gz"
            with tarfile.open(archive, "w:gz") as bundle:
                member = tarfile.TarInfo(f"flyway-{migration.FLYWAY_VERSION}/../escape")
                member.size = 4
                bundle.addfile(member, io.BytesIO(b"test"))
            with patch.object(migration, "verify_digest"), self.assertRaisesRegex(RuntimeError, "Unsafe path"):
                migration.extract_flyway(archive, Path(temporary) / "stage")


if __name__ == "__main__":
    unittest.main()
