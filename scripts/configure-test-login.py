#!/usr/bin/env python3
"""Register a server-only bcrypt hash without putting credentials in Terraform."""

import argparse
import json
from pathlib import Path
import shlex
import subprocess
import tempfile


def server_settings(source):
    settings = {}
    for line in (source / ".env.mock.local").read_text().splitlines():
        key, separator, value = line.partition("=")
        if separator and key.strip() in {"TEST_LOGIN_EMAIL", "TEST_LOGIN_PASSWORD"}:
            parts = shlex.split(value, comments=True)
            if len(parts) == 1:
                settings[key.strip()] = parts[0]
    email = settings.get("TEST_LOGIN_EMAIL", "")
    password = settings.get("TEST_LOGIN_PASSWORD", "")
    if not email or any(character in email for character in ":\r\n ") or len(password) < 8 or any(character in password for character in "\r\n"):
        raise ValueError("Set a valid test email and a password of at least eight characters in .env.mock.local.")
    result = subprocess.run(["htpasswd", "-niB", "-C", "12", email], input=password + "\n", capture_output=True, text=True, check=True)
    password_hash = result.stdout.strip().split(":", 1)[1]
    return f"OPENSTUDY_TEST_LOGIN_EMAIL={email}\nOPENSTUDY_TEST_LOGIN_PASSWORD_HASH={password_hash}\n"


def configure(source, account_id, region, prefix):
    identity = subprocess.run(["aws", "sts", "get-caller-identity", "--output", "json", "--no-cli-pager"], capture_output=True, text=True, check=True)
    if json.loads(identity.stdout)["Account"] != account_id:
        raise ValueError("AWS account does not match the Terraform target account.")
    request = {
        "Name": f"/{prefix}/frontend/test-login",
        "Type": "SecureString",
        "Tier": "Standard",
        "Value": server_settings(source),
        "Overwrite": True,
    }
    with tempfile.NamedTemporaryFile(mode="w+", prefix="openstudy-test-login-", suffix=".json") as temporary:
        json.dump(request, temporary)
        temporary.flush()
        subprocess.run(["aws", "ssm", "put-parameter", "--region", region, "--cli-input-json", "file://" + temporary.name, "--no-cli-pager"], capture_output=True, text=True, check=True)
    print("Registered server-only test login configuration.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--region", default="ap-northeast-2")
    parser.add_argument("--name-prefix", default="openstudy-prod")
    arguments = parser.parse_args()
    configure(arguments.source_dir, arguments.account_id, arguments.region, arguments.name_prefix)
