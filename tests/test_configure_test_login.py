import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


module_path = Path(__file__).resolve().parents[1] / "scripts/configure-test-login.py"
spec = importlib.util.spec_from_file_location("configure_test_login", module_path)
configuration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configuration)


class TestLoginConfigurationTest(unittest.TestCase):
    def test_registration_sends_only_the_hash_to_ssm(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            (source / ".env.mock.local").write_text("TEST_LOGIN_EMAIL=demo@example.test\nTEST_LOGIN_PASSWORD=local-test-password\n")
            requests = []
            paths = []

            def process(command, **kwargs):
                if command[0] == "htpasswd":
                    self.assertEqual(kwargs["input"], "local-test-password\n")
                    self.assertNotIn("local-test-password", command)
                    return subprocess.CompletedProcess(command, 0, "demo@example.test:$2y$12$" + "A" * 53 + "\n")
                if command[1] == "sts":
                    return subprocess.CompletedProcess(command, 0, '{"Account":"123456789012"}')
                path = command[command.index("--cli-input-json") + 1].removeprefix("file://")
                paths.append(path)
                requests.append(json.loads(Path(path).read_text()))
                return subprocess.CompletedProcess(command, 0, '{}')

            with patch.object(configuration.subprocess, "run", side_effect=process):
                configuration.configure(source, "123456789012", "ap-northeast-2", "openstudy-prod")
            self.assertEqual(requests[0]["Name"], "/openstudy-prod/frontend/test-login")
            self.assertEqual(requests[0]["Type"], "SecureString")
            self.assertNotIn("local-test-password", requests[0]["Value"])
            self.assertIn("OPENSTUDY_TEST_LOGIN_PASSWORD_HASH=$2y$12$", requests[0]["Value"])
            self.assertFalse(Path(paths[0]).exists())

    def test_wrong_account_stops_before_reading_credentials(self):
        with patch.object(configuration.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, '{"Account":"999999999999"}')) as run:
            with self.assertRaisesRegex(ValueError, "account"):
                configuration.configure(Path("missing"), "123456789012", "ap-northeast-2", "openstudy-prod")
        run.assert_called_once()

    def test_incomplete_settings_stop_before_hashing(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            (source / ".env.mock.local").write_text("TEST_LOGIN_EMAIL=demo@example.test\n")
            with patch.object(configuration.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "eight"):
                    configuration.server_settings(source)
            run.assert_not_called()
