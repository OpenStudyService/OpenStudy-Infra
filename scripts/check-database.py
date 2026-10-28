#!/usr/bin/env python3
"""Check the real MySQL schema and Flyway on an isolated Docker network."""

import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
TEST_DATABASE_PASSWORD = "isolated-test-password"
TEST_MIGRATION_PASSWORD = "m" * 40
TEST_APP_PASSWORD = "TestOnly#Password&With!Symbols_123456789"
spec = importlib.util.spec_from_file_location("migration", ROOT / "scripts/migrate-database.py")
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)
account_spec = importlib.util.spec_from_file_location("accounts", ROOT / "scripts/provision-database-accounts.py")
accounts = importlib.util.module_from_spec(account_spec)
account_spec.loader.exec_module(accounts)


def run(*arguments, check=True, timeout=180):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(f"{arguments[0]} failed:\n{result.stdout}\n{result.stderr}")
    return result


def check_backend(stage, network, container, backend_jar):
    shutil.copyfile(backend_jar, stage / "backend.jar")
    truststore = stage / "certs/truststore.p12"
    run("keytool", "-importcert", "-noprompt", "-alias", "database",
        "-file", str(stage / "certs/server-cert.pem"), "-keystore", str(truststore),
        "-storetype", "PKCS12", "-storepass", "changeit")
    # This password protects a temporary test CA, not an application credential.
    url = ("jdbc:mysql://database:3306/openstudy?sslMode=VERIFY_IDENTITY"
           "&trustCertificateKeyStoreUrl=file:/validation/certs/truststore.p12"
           "&trustCertificateKeyStoreType=PKCS12&trustCertificateKeyStorePassword=changeit"
           "&connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true")
    run("docker", "run", "--detach", "--name", container,
        "--network", network, "--read-only", "--tmpfs", "/tmp:rw,size=128m",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
        "--mount", f"type=bind,source={stage},target=/validation,readonly",
        "-e", f"DB_URL={url}", "-e", "DB_USERNAME=openstudy_app", "-e", f"DB_PASSWORD={TEST_APP_PASSWORD}",
        "-e", "SPRING_PROFILES_ACTIVE=prod", "-e", "TRUSTED_PROXIES=127.0.0.1",
        "-e", "SPRING_FLYWAY_ENABLED=false", "-e", "SPRING_JPA_HIBERNATE_DDL_AUTO=validate",
        "eclipse-temurin:21-jre", "java", "-Xmx512m", "-jar", "/validation/backend.jar")
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        logs = run("docker", "logs", container, check=False)
        output = logs.stdout + logs.stderr
        if "Started OpenstudyBackendApplication" in output:
            print("Backend: app account startup and Hibernate validation passed with Flyway disabled and verified DB TLS.")
            return
        running = run("docker", "inspect", "--format", "{{.State.Running}}", container, check=False)
        if running.stdout.strip() != "true":
            raise RuntimeError(f"Backend failed to start:\n{output}")
        time.sleep(2)
    raise RuntimeError(f"Backend startup timed out:\n{output}")


def check_schema(archive, backend_jar=None):
    token = uuid.uuid4().hex[:12]
    network = f"openstudy-db-check-{token}"
    mysql = f"{network}-mysql"
    java = f"{network}-java"
    application = f"{network}-backend"
    with tempfile.TemporaryDirectory(prefix="openstudy-db-check-") as temporary:
        stage = Path(temporary)
        flyway = stage / "flyway"
        flyway.mkdir()
        if archive is None:
            archive = stage / "flyway.tar.gz"
            migration.download(migration.FLYWAY_URL, archive)
        migration.extract_flyway(archive, flyway)
        drivers = flyway / "drivers"
        drivers.mkdir()
        driver = drivers / f"mariadb-java-client-{migration.JDBC_VERSION}.jar"
        migration.download(migration.JDBC_URL, driver)
        migration.verify_digest(driver, migration.JDBC_SHA256)
        sql = stage / "sql"
        shutil.copytree(ROOT / "database/migrations", sql)
        certs = stage / "certs"
        certs.mkdir()
        certs.chmod(0o755)
        run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-keyout", str(certs / "server-key.pem"), "-out", str(certs / "server-cert.pem"),
            "-subj", "/CN=database", "-addext", "subjectAltName=DNS:database")
        # Test-only key; the unprivileged mysqld process must read the bind mount.
        (certs / "server-key.pem").chmod(0o644)
        (certs / "server-cert.pem").chmod(0o644)
        config = stage / "flyway.toml"
        valid_config = migration.flyway_configuration(
            "database", "openstudy", "openstudy_migrator", TEST_MIGRATION_PASSWORD, Path("/validation/sql"), Path("/validation/certs/server-cert.pem"),
        )
        config.write_text(valid_config)
        for image in ["mysql:8.4.11", "eclipse-temurin:21-jre"]:
            run("docker", "pull", image, timeout=600)
        try:
            run("docker", "network", "create", "--internal", network)
            run("docker", "run", "--detach", "--rm", "--name", mysql,
                "--network", network, "--network-alias", "database",
                "--mount", f"type=bind,source={certs},target=/certs,readonly",
                "--tmpfs", "/var/lib/mysql:rw,size=1g", "--memory", "512m",
                "-e", f"MYSQL_ROOT_PASSWORD={TEST_DATABASE_PASSWORD}", "-e", "MYSQL_ROOT_HOST=%",
                "-e", "MYSQL_DATABASE=openstudy", "mysql:8.4.11",
                "--ssl-ca=/certs/server-cert.pem", "--ssl-cert=/certs/server-cert.pem",
                "--ssl-key=/certs/server-key.pem", "--require-secure-transport=ON",
                "--innodb-buffer-pool-size=64M", "--performance-schema=OFF")
            deadline = time.monotonic() + 180
            while run("docker", "exec", mysql, "mysqladmin", "--silent", "-uroot", f"-p{TEST_DATABASE_PASSWORD}", "ping", check=False).returncode:
                if time.monotonic() > deadline:
                    raise RuntimeError("The isolated MySQL did not become ready.")
                time.sleep(2)

            setup_sql = accounts.accounts_sql("openstudy", TEST_MIGRATION_PASSWORD, TEST_APP_PASSWORD)
            run("docker", "exec", mysql, "mysql", "-uroot", f"-p{TEST_DATABASE_PASSWORD}", "-e", setup_sql)

            def flyway_run(command="migrate", check=True):
                return run("docker", "run", "--rm", "--name", java, "--network", network,
                           "--read-only", "--tmpfs", "/tmp:rw,size=128m", "--cap-drop", "ALL",
                           "--security-opt", "no-new-privileges", "--workdir", "/tmp",
                           "--mount", f"type=bind,source={stage},target=/validation,readonly",
                           "-e", "FLYWAY_JAVA_CMD=/opt/java/openjdk/bin/java", "-e", "JAVA_ARGS=-Xmx256m",
                           "eclipse-temurin:21-jre", "/validation/flyway/flyway",
                           "-configFiles=/validation/flyway.toml", "-outputType=json", command, check=check)

            first = json.loads(flyway_run().stdout)
            second = json.loads(flyway_run().stdout)
            if first["migrationsExecuted"] != len(list(sql.glob("V*__*.sql"))) or second["migrationsExecuted"] != 0:
                raise RuntimeError("Flyway must apply pending SQL once and leave a second run unchanged.")
            count = run("docker", "exec", mysql, "mysql", "-uroot", f"-p{TEST_DATABASE_PASSWORD}", "--batch", "--skip-column-names", "-e",
                        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='openstudy'").stdout.strip()
            if count != "66":
                raise RuntimeError(f"Expected 65 application tables plus Flyway history, received {count}.")
            history = run("docker", "exec", mysql, "mysql", "-uroot", f"-p{TEST_DATABASE_PASSWORD}", "--batch", "--skip-column-names", "-e",
                          "SELECT version,success FROM openstudy.flyway_schema_history ORDER BY installed_rank").stdout.splitlines()
            if history != ["1\t1"]:
                raise RuntimeError(f"Expected successful consolidated V1 history, received {history}.")
            flyway_run("validate")
            app_command = ("docker", "exec", mysql, "mysql", "--protocol=TCP", "--host=127.0.0.1", "--ssl-mode=REQUIRED",
                           "-uopenstudy_app", f"-p{TEST_APP_PASSWORD}", "openstudy", "-e")
            admin_command = ("docker", "exec", mysql, "mysql", "-uroot", f"-p{TEST_DATABASE_PASSWORD}", "openstudy", "-e")
            run(*admin_command, "CREATE TABLE permission_probe (id INT PRIMARY KEY)")
            run(*app_command, "INSERT INTO permission_probe VALUES (1); SELECT * FROM permission_probe; UPDATE permission_probe SET id=2; DELETE FROM permission_probe WHERE id=2")
            run(*admin_command, "DROP TABLE permission_probe")
            rejected_ddl = run(*app_command, "CREATE TABLE app_must_not_create (id INT)", check=False)
            if rejected_ddl.returncode == 0 or "denied" not in rejected_ddl.stderr.lower():
                raise RuntimeError("The application account must not have DDL permissions.")
            if backend_jar is not None:
                check_backend(stage, network, application, backend_jar)
            wrong_host = migration.flyway_configuration(
                mysql, "openstudy", "openstudy_migrator", TEST_MIGRATION_PASSWORD, Path("/validation/sql"), Path("/validation/certs/server-cert.pem"),
            )
            config.write_text(wrong_host.replace("connectRetries = 12", "connectRetries = 0"))
            rejected = flyway_run(check=False)
            if rejected.returncode == 0 or not any(term in (rejected.stdout + rejected.stderr).lower() for term in ("certificate", "ssl", "tls", "pkix")):
                raise RuntimeError("TLS must reject a hostname that does not match the certificate.")
            run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                "-keyout", str(certs / "untrusted-key.pem"), "-out", str(certs / "untrusted-cert.pem"),
                "-subj", "/CN=untrusted")
            (certs / "untrusted-cert.pem").chmod(0o644)
            wrong_ca = migration.flyway_configuration(
                "database", "openstudy", "openstudy_migrator", TEST_MIGRATION_PASSWORD, Path("/validation/sql"), Path("/validation/certs/untrusted-cert.pem"),
            )
            config.write_text(wrong_ca.replace("connectRetries = 12", "connectRetries = 0"))
            rejected = flyway_run(check=False)
            if rejected.returncode == 0 or not any(term in (rejected.stdout + rejected.stderr).lower() for term in ("certificate", "ssl", "tls", "pkix")):
                raise RuntimeError("TLS must reject an untrusted certificate authority.")
            config.write_text(valid_config)
            with (sql / "V1__init_schema.sql").open("a") as output:
                output.write("\nCREATE TABLE checksum_change_must_not_run (id INT);\n")
            changed = flyway_run(check=False)
            if changed.returncode == 0 or "checksum" not in (changed.stdout + changed.stderr).lower():
                raise RuntimeError("Flyway must reject changes to an applied migration.")
            print("MySQL 8.4.11: consolidated V1 succeeded; 65 tables plus Flyway history; validate passed; rerun unchanged; modified V1 rejected; app DDL denied; TLS rejects wrong host and CA.")
        finally:
            run("docker", "rm", "--force", application, java, mysql, check=False, timeout=60)
            run("docker", "network", "rm", network, check=False, timeout=60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flyway-archive", type=Path, help="Reuse a downloaded official archive; SHA-256 is checked.")
    parser.add_argument("--backend-jar", type=Path, help="Also validate and start a Backend bootJar against the temporary DB; requires Java keytool.")
    args = parser.parse_args()
    check_schema(args.flyway_archive, args.backend_jar)
