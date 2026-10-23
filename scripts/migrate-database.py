#!/usr/bin/env python3
"""Run versioned SQL on private RDS from the SSM-managed EC2 server."""

import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
from urllib.parse import urlencode
from urllib.request import urlopen


FLYWAY_VERSION = "11.20.2"
FLYWAY_URL = (
    "https://download.red-gate.com/maven/release/com/redgate/flyway/"
    f"flyway-commandline/{FLYWAY_VERSION}/flyway-commandline-{FLYWAY_VERSION}-linux-x64.tar.gz"
)
FLYWAY_SHA256 = "5d170b7926e4bc7931c9098a5a5503932407f76f56a1669a89ba97097155a538"
JDBC_VERSION = "3.5.9"
JDBC_URL = f"https://repo.maven.apache.org/maven2/org/mariadb/jdbc/mariadb-java-client/{JDBC_VERSION}/mariadb-java-client-{JDBC_VERSION}.jar"
JDBC_SHA256 = "11e3bb5bbf8ef0e806ae4d6c5d5033fedf7262cc777f0190bde8a2f3c8e6bd8d"
MIGRATION_NAME = re.compile(r"V[0-9]+(?:_[0-9]+)*__[A-Za-z0-9_]+\.sql")


def aws(*arguments):
    for attempt in range(12):
        result = subprocess.run(
            ["aws", *arguments, "--region", os.environ["AWS_REGION"], "--no-cli-pager"],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            return result.stdout
        if attempt == 11 or not any(code in result.stderr for code in ("AccessDenied", "Throttl")):
            raise RuntimeError(f"AWS {arguments[0]} {arguments[1]} failed: {result.stderr.strip()}")
        time.sleep(5)


def verify_digest(source, expected):
    with source.open("rb") as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != expected:
        raise RuntimeError(f"SHA-256 mismatch: {source.name}")


def download(url, target):
    with urlopen(url, timeout=180) as response, target.open("wb") as output:
        shutil.copyfileobj(response, output)


def extract_flyway(archive, destination):
    """Keep Java code and drivers; use the server's native ARM64/x86 Java."""
    verify_digest(archive, FLYWAY_SHA256)
    with tarfile.open(archive, "r:gz") as bundle:
        for member in bundle:
            parts = PurePosixPath(member.name).parts
            if not parts or parts[0] != f"flyway-{FLYWAY_VERSION}" or ".." in parts:
                raise RuntimeError("Unsafe path in the Flyway archive.")
            if len(parts) < 2 or parts[1] in {"jre", "drivers"}:
                continue
            if member.isdir():
                continue
            if not member.isfile():
                raise RuntimeError("Unexpected link or special file in the Flyway archive.")
            target = destination.joinpath(*parts[1:])
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.extractfile(member) as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
    (destination / "flyway").chmod(0o755)


def install_flyway():
    if shutil.which("java") is None:
        subprocess.run(["dnf", "install", "-y", "java-21-amazon-corretto-headless"], check=True)
    cache = Path(f"/opt/openstudy/flyway-{FLYWAY_VERSION}")
    marker = cache / ".archive-sha256"
    cache_digest = FLYWAY_SHA256 + JDBC_SHA256
    if marker.is_file() and marker.read_text() == cache_digest:
        return cache / "flyway"
    cache.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".flyway-", dir=cache.parent) as temporary:
        stage = Path(temporary)
        archive = stage / "flyway.tar.gz"
        download(FLYWAY_URL, archive)
        distribution = stage / "distribution"
        distribution.mkdir()
        extract_flyway(archive, distribution)
        archive.unlink()
        drivers = distribution / "drivers"
        drivers.mkdir()
        driver = drivers / f"mariadb-java-client-{JDBC_VERSION}.jar"
        download(JDBC_URL, driver)
        verify_digest(driver, JDBC_SHA256)
        (distribution / ".archive-sha256").write_text(cache_digest)
        if cache.exists():
            shutil.rmtree(cache)
        distribution.rename(cache)
    return cache / "flyway"


def flyway_configuration(host, database, username, password, migrations, certificate):
    if not re.fullmatch(r"[A-Za-z0-9.-]+", host) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9]{0,63}", database):
        raise RuntimeError("Invalid database hostname or database name.")
    query = urlencode({
        "permitMysqlScheme": "true", "sslMode": "verify-full",
        "serverSslCert": str(certificate),
    }, safe="/:")
    environment = {
        "url": f"jdbc:mysql://{host}:3306/{database}?{query}",
        "driver": "org.mariadb.jdbc.Driver",
        "user": username,
        # Escape Flyway's resolver prefix, independently of TOML string escaping.
        "password": "$" + password if password.startswith("$") else password,
        "connectRetries": 12,
        "connectRetriesInterval": 5,
        "initSql": "SET time_zone = '+00:00'",
    }
    settings = {
        "environment": "default",
        "locations": [f"filesystem:{migrations}"],
        "cleanDisabled": True,
        "baselineOnMigrate": False,
        "outOfOrder": False,
        "validateOnMigrate": True,
        "validateMigrationNaming": True,
        "failOnMissingLocations": True,
        "placeholderReplacement": False,
    }
    # JSON scalars and arrays are valid TOML values for these ASCII settings.
    return "\n".join(
        f"[{name}]\n" + "".join(f"{key} = {json.dumps(value)}\n" for key, value in values.items())
        for name, values in [("environments.default", environment), ("flyway", settings)]
    )


def migrate():
    launcher = install_flyway()
    region = os.environ["AWS_REGION"]
    if not re.fullmatch(r"[a-z]{2}(?:-[a-z]+)+-[0-9]+", region):
        raise RuntimeError("Invalid AWS region.")
    migrations = json.loads(os.environ["DATABASE_MIGRATIONS"])
    if not migrations or not all(MIGRATION_NAME.fullmatch(name) for name in migrations):
        raise RuntimeError("Use versioned SQL files such as V1__initial_schema.sql.")
    with tempfile.TemporaryDirectory(prefix="openstudy-flyway-", dir="/run") as temporary:
        stage = Path(temporary)
        sql = stage / "sql"
        sql.mkdir()
        for name, digest in sorted(migrations.items()):
            uri = f"s3://{os.environ['DATABASE_ARTIFACT_BUCKET']}/schema/{os.environ['DATABASE_SOURCE_HASH']}/migrations/{name}"
            aws("s3", "cp", uri, str(sql / name), "--only-show-errors")
            verify_digest(sql / name, digest)
        certificate = stage / "rds-ca.pem"
        download(f"https://truststore.pki.rds.amazonaws.com/{region}/{region}-bundle.pem", certificate)
        response = json.loads(aws("secretsmanager", "get-secret-value", "--secret-id", os.environ["DATABASE_SECRET_ARN"], "--output", "json"))
        secret = json.loads(response["SecretString"])
        config = stage / "flyway.toml"
        config.write_text(flyway_configuration(
            os.environ["DATABASE_HOST"], os.environ["DATABASE_NAME"],
            secret["username"], secret["password"], sql, certificate,
        ))
        config.chmod(0o600)
        result = subprocess.run(
            [str(launcher), f"-configFiles={config}", "migrate"],
            env={**os.environ, "FLYWAY_JAVA_CMD": shutil.which("java"), "JAVA_ARGS": "-Xmx256m"},
            capture_output=True, text=True, cwd=stage,
        )
        output = (result.stdout + result.stderr).replace(secret["password"], "[REDACTED]")
        print(output, end="", flush=True)
        if result.returncode != 0:
            raise RuntimeError("Flyway migration failed. Inspect the SSM execution; no automatic repair or clean was run.")


if __name__ == "__main__":
    os.umask(0o077)
    try:
        # Serialize manual SSM reruns as well as Terraform-triggered migrations.
        with open("/run/openstudy-database.lock", "a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            migrate()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Database migration failed: {error}", file=sys.stderr)
        sys.exit(1)
