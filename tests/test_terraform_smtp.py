from pathlib import Path
import runpy
import tempfile
import unittest

credentials = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/terraform-smtp.py"))["credentials"]

class SmtpEnvironmentTests(unittest.TestCase):
    def read(self, text):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / ".env"
            path.write_text(text)
            return credentials(path)

    def test_only_smtp_credentials_cross_the_terraform_boundary(self):
        result = self.read("DB_PASSWORD=local-db-secret\nspring.profiles.active=local\nspring.mail.username=sender@example.test\nspring.mail.password=unit-smtp-secret\n")
        self.assertEqual(result, {"username": "sender@example.test", "password": "unit-smtp-secret"})

    def test_owner_or_database_password_cannot_replace_missing_smtp_password(self):
        with self.assertRaisesRegex(ValueError, "SMTP username and password are required"):
            self.read("spring.mail.username=sender@example.test\nDB_PASSWORD=local-db-secret\nBOOTSTRAP_OWNER_PASSWORD=owner-secret\n")

    def test_escaped_values_fail_without_echoing_the_credential(self):
        secret = "unit-secret\\nother-property"
        with self.assertRaises(ValueError) as error:
            self.read("spring.mail.username=sender@example.test\nspring.mail.password=" + secret + "\n")
        self.assertNotIn(secret, str(error.exception))

if __name__ == "__main__":
    unittest.main()
