#!/usr/bin/env python3
"""Supply only SMTP credentials from a Java-properties env file to Terraform."""
import argparse
import json
import os
from pathlib import Path
import subprocess

def credentials(path):
    values = {}
    for line in Path(path).read_text(encoding="utf-8-sig").splitlines():
        if not line.strip() or line.lstrip().startswith(("#", "!")) or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() in ("spring.mail.username", "spring.mail.password"):
            values[key.strip()] = value.strip()
    username = values.get("spring.mail.username", "")
    password = values.get("spring.mail.password", "")
    if not username or not password:
        raise ValueError("SMTP username and password are required in the env file")
    if any(c in username + password for c in "\\\r\n"):
        raise ValueError("SMTP credentials must be single-line literal values")
    return {"username": username, "password": password}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", required=True)
    parser.add_argument("terraform_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.terraform_args or args.terraform_args[0] not in ("plan", "apply"):
        parser.error("Pass Terraform plan or apply arguments after --env-file")
    environment = dict(os.environ)
    environment["TF_VAR_invitation_smtp_credentials"] = json.dumps(credentials(args.env_file))
    root = Path(__file__).resolve().parents[1]
    result = subprocess.run(["terraform", "-chdir=" + str(root / "terraform/aws"), *args.terraform_args], env=environment)
    raise SystemExit(result.returncode)

if __name__ == "__main__":
    main()
