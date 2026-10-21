#!/usr/bin/env python3
"""Build the live Frontend and atomically publish it to EC2 through S3 and SSM."""

import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tarfile
import tempfile
import time


def aws_json(region, *arguments):
    result = subprocess.run(
        ["aws", *arguments, "--region", region, "--output", "json", "--no-cli-pager"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def package_release(dist, archive):
    if not (dist / "index.html").is_file() or not (dist / "assets").is_dir():
        raise RuntimeError("The live build must contain index.html and assets/.")
    with tarfile.open(archive, "w:gz") as bundle:
        for source in sorted(dist.rglob("*")):
            if source.is_symlink():
                raise RuntimeError("Do not publish symlinks from the build output.")
            if source.is_file() and source.suffix != ".map" and source.name != "mockServiceWorker.js":
                bundle.add(source, arcname=source.relative_to(dist), recursive=False)
    return hashlib.sha256(archive.read_bytes()).hexdigest()


def publish_commands(bucket, digest, region):
    uri = shlex.quote(f"s3://{bucket}/releases/{digest}.tar.gz")
    return f"""bash <<'OPENSTUDY_FRONTEND'
set -euo pipefail
task_release_tmp=$(mktemp -d)
task_release_stage=$(mktemp -d /srv/openstudy/releases/.stage-XXXXXX)
trap 'rm -rf "$task_release_tmp" "$task_release_stage"' EXIT
aws s3 cp {uri} "$task_release_tmp/release.tar.gz" --region {shlex.quote(region)} --only-show-errors
printf '%s  %s\\n' {shlex.quote(digest)} "$task_release_tmp/release.tar.gz" | sha256sum --check --status
release=/srv/openstudy/releases/{digest}
if [ ! -d "$release" ]; then
  tar --no-same-owner --no-same-permissions -xzf "$task_release_tmp/release.tar.gz" -C "$task_release_stage"
  test -s "$task_release_stage/index.html"
  test -d "$task_release_stage/assets"
  chmod -R a+rX "$task_release_stage"
  mv "$task_release_stage" "$release"
fi
test -s "$release/index.html"
test -d "$release/assets"
install -d -m 0755 /srv/openstudy/assets
cp -an "$release/assets/." /srv/openstudy/assets/
ln -sfn releases/{digest} /srv/openstudy/current-next
mv -Tf /srv/openstudy/current-next /srv/openstudy/current
systemctl is-active --quiet openstudy-web
echo 'Frontend release published.'
OPENSTUDY_FRONTEND"""


def wait_command(region, command_id, instance_id):
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        try:
            result = aws_json(region, "ssm", "get-command-invocation", "--command-id", command_id, "--instance-id", instance_id)
        except subprocess.CalledProcessError as error:
            if "InvocationDoesNotExist" not in (error.stderr or ""):
                raise
            time.sleep(2)
            continue
        status = result["Status"]
        if status == "Success":
            return
        if status not in {"Pending", "InProgress", "Delayed"}:
            raise RuntimeError(f"SSM publication {status}: {result.get('StandardErrorContent', '')}")
        time.sleep(2)
    raise RuntimeError("Timed out waiting for the SSM publication command.")


def wait_configuration(region, association_id, instance_id):
    # Association creation can report success before its first execution starts.
    deadline = time.monotonic() + 1800
    while time.monotonic() < deadline:
        executions = aws_json(region, "ssm", "describe-association-executions", "--association-id", association_id)["AssociationExecutions"]
        if executions:
            execution = max(executions, key=lambda item: item["CreatedTime"])
            if execution["Status"] in {"Failed", "TimedOut"}:
                raise RuntimeError("EC2 server configuration failed. Check the SSM association execution.")
            if execution["Status"] == "Success":
                targets = aws_json(
                    region, "ssm", "describe-association-execution-targets", "--association-id", association_id,
                    "--execution-id", execution["ExecutionId"],
                )["AssociationExecutionTargets"]
                if any(target["ResourceId"] == instance_id and target["Status"] == "Success" for target in targets):
                    return
        print("Waiting for EC2 server configuration to finish...", flush=True)
        time.sleep(10)
    raise RuntimeError("Timed out waiting for the EC2 server configuration.")


def verify_https(hostname, expected):
    deadline = time.monotonic() + 300
    pending = {"/", "/login"}
    while pending and time.monotonic() < deadline:
        for route in list(pending):
            result = subprocess.run(
                ["curl", "--fail", "--silent", "--show-error", "--compressed", "--max-time", "10", f"https://{hostname}{route}"],
                capture_output=True,
            )
            if result.returncode == 0 and result.stdout == expected:
                pending.remove(route)
        if pending:
            print("Waiting for DuckDNS, HTTPS certificate, and the new HTML...", flush=True)
            time.sleep(5)
    if pending:
        raise RuntimeError("The HTTPS response did not match the live build. Check DuckDNS and openstudy-web logs.")


def deploy():
    source = Path(os.environ["FRONTEND_SOURCE_DIR"])
    region = os.environ["AWS_REGION"]
    hostname = os.environ["FRONTEND_HOSTNAME"]
    instance_id = os.environ["FRONTEND_INSTANCE_ID"]
    bucket = os.environ["FRONTEND_ARTIFACT_BUCKET"]
    node_version = subprocess.run(["node", "--version"], capture_output=True, text=True, check=True).stdout.strip()
    if not node_version.startswith("v24."):
        raise RuntimeError("Frontend deployment requires Node.js 24.")
    if aws_json(region, "sts", "get-caller-identity")["Account"] != os.environ["AWS_ACCOUNT_ID"]:
        raise RuntimeError("AWS CLI account does not match the Terraform target account.")
    wait_configuration(region, os.environ["FRONTEND_ASSOCIATION_ID"], instance_id)
    env = {**os.environ, "VITE_API_MODE": "live", "VITE_API_BASE_URL": "/api"}
    for command in [["npm", "ci", "--include=dev"], ["npm", "run", "check"], ["npm", "run", "build"]]:
        subprocess.run(command, cwd=source, env=env, check=True)
    with tempfile.TemporaryDirectory(prefix="openstudy-release-") as temporary:
        archive = Path(temporary) / "release.tar.gz"
        digest = package_release(source / "dist", archive)
        subprocess.run(["aws", "s3", "cp", str(archive), f"s3://{bucket}/releases/{digest}.tar.gz", "--region", region, "--sse", "AES256", "--only-show-errors"], check=True)
        command = aws_json(
            region, "ssm", "send-command", "--instance-ids", instance_id,
            "--document-name", "AWS-RunShellScript", "--timeout-seconds", "180",
            "--parameters", json.dumps({"commands": [publish_commands(bucket, digest, region)]}),
        )
        wait_command(region, command["Command"]["CommandId"], instance_id)
    verify_https(hostname, (source / "dist/index.html").read_bytes())
    print(f"Frontend deployed: https://{hostname}", flush=True)


if __name__ == "__main__":
    try:
        deploy()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Frontend EC2 deployment failed: {error}", file=sys.stderr)
        sys.exit(1)
