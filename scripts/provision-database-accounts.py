#!/usr/bin/env python3
"""Create dedicated DB accounts using operator credentials; never print passwords."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def accounts_sql(database, migration_password, app_password):
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]{0,63}", database):
        raise ValueError("Invalid database name.")
    if not all(re.fullmatch(r"[A-Za-z0-9_-]{32,128}", value) for value in (migration_password, app_password)):
        raise ValueError("Passwords must contain 32-128 ASCII letters, digits, underscores or hyphens.")
    if migration_password == app_password:
        raise ValueError("Use a different password for each account.")
    return (
        f"CREATE USER 'openstudy_migrator'@'%' IDENTIFIED BY '{migration_password}', "
        f"'openstudy_app'@'%' IDENTIFIED BY '{app_password}' REQUIRE SSL;\n"
        f"GRANT ALTER, CREATE, DROP, INDEX, REFERENCES, SELECT, INSERT, UPDATE, DELETE ON `{database}`.* TO 'openstudy_migrator'@'%';\n"
        f"GRANT SELECT, INSERT, UPDATE, DELETE ON `{database}`.* TO 'openstudy_app'@'%';\n"
    )


def aws(region, *args):
    result = subprocess.run(["aws", *args, "--region", region, "--no-cli-pager", "--output", "json"],
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"Unable to read AWS {args[0]} credentials. Check operator permissions.")
    return json.loads(result.stdout)


def parameter(region, name):
    result = aws(region, "ssm", "get-parameter", "--name", name, "--with-decryption")["Parameter"]
    if result.get("Type") != "SecureString" or not result.get("Value"):
        raise RuntimeError(f"{name} must be a non-empty SecureString.")
    return result["Value"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--master-secret-arn", required=True)
    parser.add_argument("--ca-file", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,50}", args.prefix) or not re.fullmatch(r"[A-Za-z0-9.-]+", args.host):
        raise ValueError("Invalid prefix or database hostname.")
    migration_password = parameter(args.region, f"/{args.prefix}/migrations/db-password")
    app_password = parameter(args.region, f"/{args.prefix}/apps/db-password")
    statements = accounts_sql(args.database, migration_password, app_password)
    master = json.loads(aws(args.region, "secretsmanager", "get-secret-value", "--secret-id", args.master_secret_arn)["SecretString"])
    if not re.fullmatch(r"[A-Za-z0-9_]{1,32}", master["username"]) or any(c in master["password"] for c in "\r\n\x00"):
        raise ValueError("Invalid master credentials format.")
    quoted_password = master["password"].replace("\\", "\\\\").replace('"', '\\"')
    with tempfile.TemporaryDirectory(prefix="openstudy-accounts-") as temporary:
        config = Path(temporary) / "mysql.cnf"
        config.write_text(f'[client]\nuser="{master["username"]}"\npassword="{quoted_password}"\n')
        config.chmod(0o600)
        command = ["mysql", f"--defaults-extra-file={config}", "--protocol=TCP", f"--host={args.host}",
                   "--ssl-mode=VERIFY_IDENTITY", f"--ssl-ca={args.ca_file}", "--batch", "--skip-column-names"]
        check = subprocess.run(command, input="SELECT COUNT(*) FROM mysql.user WHERE User IN ('openstudy_migrator','openstudy_app');\n", capture_output=True, text=True)
        if check.returncode or check.stdout.strip() != "0":
            raise RuntimeError("Cannot verify existing accounts, or one of the account names already exists. Inspect manually.")
        result = subprocess.run(command, input=statements, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError("Account creation failed. Check the DB state before retrying; partial changes may exist.")
    print("Created separate migration and application accounts with TLS required.")


if __name__ == "__main__":
    os.umask(0o077)
    try:
        main()
    except (KeyError, OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"Database account setup failed: {error}", file=sys.stderr)
        sys.exit(1)
