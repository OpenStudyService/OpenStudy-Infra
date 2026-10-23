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
spec = importlib.util.spec_from_file_location("migration", ROOT / "scripts/migrate-database.py")
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


def run(*arguments, check=True, timeout=180):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(f"{arguments[0]} failed:\n{result.stdout}\n{result.stderr}")
    return result


def check_schema(archive):
    token = uuid.uuid4().hex[:12]
    network = f"openstudy-db-check-{token}"
    mysql = f"{network}-mysql"
    java = f"{network}-java"
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
            "database", "openstudy", "root", "", Path("/validation/sql"), Path("/validation/certs/server-cert.pem"),
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
                "-e", "MYSQL_ALLOW_EMPTY_PASSWORD=yes", "-e", "MYSQL_ROOT_HOST=%",
                "-e", "MYSQL_DATABASE=openstudy", "mysql:8.4.11",
                "--ssl-ca=/certs/server-cert.pem", "--ssl-cert=/certs/server-cert.pem",
                "--ssl-key=/certs/server-key.pem", "--require-secure-transport=ON",
                "--innodb-buffer-pool-size=64M", "--performance-schema=OFF")
            deadline = time.monotonic() + 180
            while run("docker", "exec", mysql, "mysqladmin", "--silent", "ping", check=False).returncode:
                if time.monotonic() > deadline:
                    raise RuntimeError("The isolated MySQL did not become ready.")
                time.sleep(2)

            def flyway_run(check=True):
                return run("docker", "run", "--rm", "--name", java, "--network", network,
                           "--read-only", "--tmpfs", "/tmp:rw,size=128m", "--cap-drop", "ALL",
                           "--security-opt", "no-new-privileges", "--workdir", "/tmp",
                           "--mount", f"type=bind,source={stage},target=/validation,readonly",
                           "-e", "FLYWAY_JAVA_CMD=/opt/java/openjdk/bin/java", "-e", "JAVA_ARGS=-Xmx256m",
                           "eclipse-temurin:21-jre", "/validation/flyway/flyway",
                           "-configFiles=/validation/flyway.toml", "-outputType=json", "migrate", check=check)

            first = json.loads(flyway_run().stdout)
            second = json.loads(flyway_run().stdout)
            if first["migrationsExecuted"] != len(list(sql.glob("V*__*.sql"))) or second["migrationsExecuted"] != 0:
                raise RuntimeError("Flyway must apply pending SQL once and leave a second run unchanged.")
            count = run("docker", "exec", mysql, "mysql", "--batch", "--skip-column-names", "-e",
                        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='openstudy'").stdout.strip()
            if count != "59":
                raise RuntimeError(f"Expected 58 application tables plus Flyway history, received {count}.")
            wrong_host = migration.flyway_configuration(
                mysql, "openstudy", "root", "", Path("/validation/sql"), Path("/validation/certs/server-cert.pem"),
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
                "database", "openstudy", "root", "", Path("/validation/sql"), Path("/validation/certs/untrusted-cert.pem"),
            )
            config.write_text(wrong_ca.replace("connectRetries = 12", "connectRetries = 0"))
            rejected = flyway_run(check=False)
            if rejected.returncode == 0 or not any(term in (rejected.stdout + rejected.stderr).lower() for term in ("certificate", "ssl", "tls", "pkix")):
                raise RuntimeError("TLS must reject an untrusted certificate authority.")
            config.write_text(valid_config)
            with (sql / "V1__initial_schema.sql").open("a") as output:
                output.write("\nCREATE TABLE checksum_change_must_not_run (id INT);\n")
            changed = flyway_run(check=False)
            if changed.returncode == 0 or "checksum" not in (changed.stdout + changed.stderr).lower():
                raise RuntimeError("Flyway must reject changes to an applied migration.")
            print("MySQL 8.4.11: 58 tables created; rerun unchanged; modified V1 rejected; TLS rejects wrong host and CA.")
        finally:
            run("docker", "rm", "--force", java, mysql, check=False, timeout=60)
            run("docker", "network", "rm", network, check=False, timeout=60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flyway-archive", type=Path, help="Reuse a downloaded official archive; SHA-256 is checked.")
    check_schema(parser.parse_args().flyway_archive)
