"""Disposable MySQL integration checks for the offline AddOwner command."""
import argparse
import json
from pathlib import Path
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, timeout=180, **kwargs)


def check(jar, classes):
    name = "openstudy-owner-check-" + uuid.uuid4().hex[:12]
    password = "DisposableFixtureOnly123!"
    assert run("docker", "network", "create", "--internal", name).returncode == 0
    try:
        assert run("docker", "run", "--detach", "--rm", "--name", name, "--network", name,
                   "--network-alias", "database", "--tmpfs", "/var/lib/mysql:rw,size=512m",
                   "-e", "MYSQL_ROOT_PASSWORD=" + password, "-e", "MYSQL_ROOT_HOST=%",
                   "-e", "MYSQL_DATABASE=openstudy", "mysql:8.4.11").returncode == 0

        def sql(text, ok=True):
            result = run("docker", "exec", "-i", name, "mysql", "-uroot", "-p" + password,
                         "--batch", "--skip-column-names", "openstudy", input=text)
            assert (result.returncode == 0) == ok, "Unexpected SQL result (diagnostics suppressed)"
            return result.stdout.strip()

        for _ in range(90):
            if run("docker", "exec", name, "mysqladmin", "-uroot", "-p" + password, "ping", "--silent").returncode == 0:
                break
            time.sleep(2)
        else:
            raise RuntimeError("Fixture MySQL not ready")
        sql((ROOT / "database/migrations/V1__init_schema.sql").read_text())
        sql("INSERT INTO employees(email,password_hash,name,nickname,global_role,status) "
            "VALUES('original@example.invalid','preserve-this-hash','original','original','OWNER','ACTIVE'),"
            "('employee@example.invalid','preserve-employee-hash','employee','employee','EMPLOYEE','ACTIVE');")

        def add(email="added@example.invalid", secret=password, ok=True):
            result = run("docker", "run", "--rm", "--network", name, "--read-only", "--tmpfs", "/tmp:rw,size=64m",
                         "--mount", f"type=bind,source={jar},target=/app/app.jar,readonly",
                         "--mount", f"type=bind,source={classes},target=/operator,readonly",
                         "-e", "DB_URL=jdbc:mysql://database:3306/openstudy?sslMode=REQUIRED&allowPublicKeyRetrieval=true",
                         "-e", "DB_USERNAME=root", "-e", "DB_PASSWORD=" + password,
                         "-e", "OWNER_EMAIL=" + email, "-e", "OWNER_NAME=Additional Owner", "-e", "OWNER_PASSWORD=" + secret,
                         "eclipse-temurin:21-jre", "java", "-cp", "/app/app.jar", "-Dloader.path=/operator",
                         "-Dloader.main=AddOwner", "org.springframework.boot.loader.launch.PropertiesLauncher")
            assert (result.returncode == 0) == ok, "Unexpected AddOwner result (diagnostics suppressed)"
            assert secret not in result.stdout + result.stderr, "Credential in operator output"

        add(ok=False)  # V1 must still enforce the one-OWNER policy.
        sql((ROOT / "database/migrations/V23__allow_multiple_owners.sql").read_text())
        add()
        assert sql("SELECT COUNT(*) FROM employees WHERE global_role='OWNER'") == "2"
        assert sql("SELECT password_hash FROM employees WHERE email='original@example.invalid'") == "preserve-this-hash"
        assert sql("SELECT LEFT(password_hash,7) FROM employees WHERE email='added@example.invalid'") == "$2a$12$"
        assert sql("SELECT COUNT(*) FROM audit_events WHERE action='OWNER_ADDED'") == "1"
        original = sql("SELECT id,email,password_hash,global_role,status FROM employees ORDER BY id")
        add(ok=False)  # Duplicate retries must not overwrite credentials or emit another audit.
        add(email="employee@example.invalid", ok=False)
        add(email="invalid-password@example.invalid", secret="short", ok=False)
        assert sql("SELECT id,email,password_hash,global_role,status FROM employees ORDER BY id") == original
        assert sql("SELECT COUNT(*) FROM audit_events WHERE action='OWNER_ADDED'") == "1"
        sql("RENAME TABLE audit_events TO audit_events_unavailable")
        add(email="rollback@example.invalid", ok=False)
        sql("RENAME TABLE audit_events_unavailable TO audit_events")
        assert sql("SELECT COUNT(*) FROM employees WHERE email='rollback@example.invalid'") == "0"
        sql("UPDATE employees SET status='SUSPENDED' WHERE global_role='OWNER'")
        add(email="no-active-owner@example.invalid", ok=False)
        sql("DELETE FROM administration_guard")
        add(email="no-guard@example.invalid", ok=False)
        print(json.dumps({"checks": 8, "result": "passed", "existing_accounts_preserved": True,
                          "duplicate_email_rejected": True, "audit_failure_rolled_back": True}))
    finally:
        run("docker", "rm", "--force", name)
        run("docker", "network", "rm", name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend-jar", required=True, type=Path)
    parser.add_argument("--classes", required=True, type=Path)
    args = parser.parse_args()
    check(args.backend_jar.resolve(), args.classes.resolve())
