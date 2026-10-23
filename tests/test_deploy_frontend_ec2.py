import importlib.util
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch


module_path = Path(__file__).resolve().parents[1] / "scripts/deploy-frontend-ec2.py"
spec = importlib.util.spec_from_file_location("deploy_frontend_ec2", module_path)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class FrontendEC2Test(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.dist = self.root / "dist"
        (self.dist / "assets").mkdir(parents=True)
        (self.dist / "index.html").write_text("<html>live</html>")
        (self.dist / "assets/app-abc.js").write_text("live app")
        (self.dist / "assets/app-abc.js.map").write_text("source map")
        (self.dist / "mockServiceWorker.js").write_text("mock worker")
        self.environment = {
            "FRONTEND_SOURCE_DIR": str(self.root),
            "AWS_REGION": "ap-northeast-2",
            "AWS_ACCOUNT_ID": "123456789012",
            "FRONTEND_HOSTNAME": "openstudy.duckdns.org",
            "FRONTEND_INSTANCE_ID": "i-0123456789abcdef0",
            "FRONTEND_ASSOCIATION_ID": "association-1",
            "FRONTEND_ARTIFACT_BUCKET": "example-artifacts",
            "FRONTEND_API_MODE": "live",
        }

    def process(self, command, **kwargs):
        return subprocess.CompletedProcess(command, 0, "v24.19.0\n" if command[0] == "node" else "")

    def test_package_excludes_source_maps_and_mock_worker(self):
        archive = self.root / "release.tar.gz"
        digest = publisher.package_release(self.dist, archive)
        self.assertEqual(len(digest), 64)
        with tarfile.open(archive) as bundle:
            self.assertEqual(set(bundle.getnames()), {"index.html", "assets/app-abc.js"})

    def test_package_rejects_symlinks(self):
        (self.dist / "linked-file").symlink_to(self.dist / "index.html")
        with self.assertRaisesRegex(RuntimeError, "symlinks"):
            publisher.package_release(self.dist, self.root / "release.tar.gz")

    def test_demo_package_includes_worker_and_excludes_source_maps(self):
        archive = self.root / "release.tar.gz"
        publisher.package_release(self.dist, archive, "mock")
        with tarfile.open(archive) as bundle:
            self.assertEqual(set(bundle.getnames()), {"index.html", "assets/app-abc.js", "mockServiceWorker.js"})

    def test_demo_package_requires_its_worker(self):
        (self.dist / "mockServiceWorker.js").unlink()
        with self.assertRaisesRegex(RuntimeError, "mockServiceWorker.js"):
            publisher.package_release(self.dist, self.root / "release.tar.gz", "mock")

    def test_incomplete_build_fails_before_packaging(self):
        (self.dist / "index.html").unlink()
        with self.assertRaisesRegex(RuntimeError, "index.html"):
            publisher.package_release(self.dist, self.root / "release.tar.gz")

    def test_publication_checks_and_builds_before_upload_and_verification(self):
        with patch.dict(os.environ, self.environment), \
                patch.object(publisher.subprocess, "run", side_effect=self.process) as process, \
                patch.object(publisher, "aws_json", side_effect=[{"Account": "123456789012"}, {"Command": {"CommandId": "command-1"}}]) as aws, \
                patch.object(publisher, "wait_command") as wait, \
                patch.object(publisher, "wait_configuration") as configuration, \
                patch.object(publisher, "verify_https") as verify:
            publisher.deploy()
        commands = [call.args[0] for call in process.call_args_list]
        self.assertEqual(commands[1:4], [["npm", "ci", "--include=dev"], ["npm", "run", "check"], ["npm", "run", "build"]])
        self.assertEqual(commands[4][:3], ["aws", "s3", "cp"])
        self.assertEqual(process.call_args_list[2].kwargs["env"]["VITE_API_MODE"], "live")
        self.assertEqual(process.call_args_list[2].kwargs["env"]["VITE_API_BASE_URL"], "/api")
        self.assertIn("send-command", aws.call_args.args)
        wait.assert_called_once_with("ap-northeast-2", "command-1", "i-0123456789abcdef0")
        configuration.assert_called_once_with("ap-northeast-2", "association-1", "i-0123456789abcdef0")
        verify.assert_called_once_with("openstudy.duckdns.org", b"<html>live</html>")

    def test_explicit_demo_mode_builds_and_publishes_the_worker(self):
        archives = []

        def process(command, **kwargs):
            if command[:3] == ["aws", "s3", "cp"]:
                with tarfile.open(command[3]) as bundle:
                    archives.append(set(bundle.getnames()))
            return self.process(command, **kwargs)

        with patch.dict(os.environ, {**self.environment, "FRONTEND_API_MODE": "mock"}), \
                patch.object(publisher.subprocess, "run", side_effect=process) as run, \
                patch.object(publisher, "aws_json", side_effect=[{"Account": "123456789012"}, {"Command": {"CommandId": "command-1"}}]), \
                patch.object(publisher, "wait_command"), \
                patch.object(publisher, "wait_configuration"), \
                patch.object(publisher, "verify_https"):
            publisher.deploy()
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[3], ["npm", "run", "build:demo"])
        self.assertEqual(run.call_args_list[3].kwargs["env"]["VITE_API_MODE"], "mock")
        self.assertEqual(archives, [{"index.html", "assets/app-abc.js", "mockServiceWorker.js"}])

    def test_invalid_api_mode_stops_before_build_or_upload(self):
        with patch.dict(os.environ, {**self.environment, "FRONTEND_API_MODE": "invalid"}), \
                patch.object(publisher.subprocess, "run") as run:
            with self.assertRaisesRegex(RuntimeError, "FRONTEND_API_MODE"):
                publisher.deploy()
        run.assert_not_called()

    def test_wrong_account_stops_before_build_or_upload(self):
        with patch.dict(os.environ, self.environment), \
                patch.object(publisher.subprocess, "run", side_effect=self.process) as process, \
                patch.object(publisher, "aws_json", return_value={"Account": "999999999999"}):
            with self.assertRaisesRegex(RuntimeError, "account"):
                publisher.deploy()
        process.assert_called_once()

    def test_failed_build_prevents_upload(self):
        def process(command, **kwargs):
            if command == ["npm", "run", "build"]:
                raise subprocess.CalledProcessError(1, command)
            return self.process(command, **kwargs)
        with patch.dict(os.environ, self.environment), \
                patch.object(publisher.subprocess, "run", side_effect=process) as run, \
                patch.object(publisher, "wait_configuration"), \
                patch.object(publisher, "aws_json", return_value={"Account": "123456789012"}):
            with self.assertRaises(subprocess.CalledProcessError):
                publisher.deploy()
        self.assertFalse(any(call.args[0][0] == "aws" for call in run.call_args_list))

    def test_ssm_failure_stops_publication(self):
        with patch.object(publisher, "aws_json", return_value={"Status": "Failed", "StandardErrorContent": "download failed"}):
            with self.assertRaisesRegex(RuntimeError, "download failed"):
                publisher.wait_command("ap-northeast-2", "command-1", "i-0123456789abcdef0")

    def test_configuration_waits_for_the_specific_instance(self):
        responses = [
            {"AssociationExecutions": [{"CreatedTime": "2026-10-20", "ExecutionId": "execution-1", "Status": "Success"}]},
            {"AssociationExecutionTargets": []},
            {"AssociationExecutions": [{"CreatedTime": "2026-10-20", "ExecutionId": "execution-1", "Status": "Success"}]},
            {"AssociationExecutionTargets": [{"ResourceId": "i-target", "Status": "Success"}]},
        ]
        with patch.object(publisher, "aws_json", side_effect=responses), patch.object(publisher.time, "sleep") as sleep:
            publisher.wait_configuration("ap-northeast-2", "association-1", "i-target")
        sleep.assert_called_once_with(10)

    def test_failed_configuration_prevents_publication(self):
        response = {"AssociationExecutions": [{"CreatedTime": "2026-10-20", "ExecutionId": "execution-1", "Status": "Failed"}]}
        with patch.object(publisher, "aws_json", return_value=response):
            with self.assertRaisesRegex(RuntimeError, "configuration failed"):
                publisher.wait_configuration("ap-northeast-2", "association-1", "i-target")

    def test_https_verification_checks_both_routes_with_certificate_validation(self):
        with patch.object(publisher.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"live")) as run:
            publisher.verify_https("openstudy.duckdns.org", b"live")
        urls = {call.args[0][-1] for call in run.call_args_list}
        self.assertEqual(urls, {"https://openstudy.duckdns.org/", "https://openstudy.duckdns.org/login"})
        self.assertFalse(any("--insecure" in call.args[0] for call in run.call_args_list))

    def test_remote_publication_script_has_valid_bash(self):
        commands = publisher.publish_commands("example-artifacts", "a" * 64, "ap-northeast-2")
        result = subprocess.run(["bash", "-n"], input=commands, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
