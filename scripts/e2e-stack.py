#!/usr/bin/env python3
"""Disposable Nginx deployment stack for Playwright. No AWS or application credentials."""

import argparse
import base64
from contextlib import ExitStack
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.client
import json
from pathlib import Path
import re
import signal
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
IMAGE = "nginx:1.30.6"
MODES = (("unconfigured", False, False), ("demo", True, False), ("proxy", False, True))
EMAIL = "demo@example.test"
PASSWORD = "disposable-playwright-password"


def run(*args, timeout=120, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, check=True, timeout=timeout, **kwargs).stdout.strip()


def remove(*args):
    subprocess.run(["docker", *args], capture_output=True, timeout=15)


def render(directory, demo, backend, origins):
    # Evaluate only the template, outside the real Terraform stack and its state.
    variables = dict(hostname="openstudy.example.test", cors_allowed_origins=origins,
                     test_login_enabled=demo, backend_enabled=backend)
    expression = "base64encode(templatefile(%s, jsondecode(%s)))" % (
        json.dumps(str(ROOT / "terraform/aws/templates/nginx.conf.tftpl")),
        json.dumps(json.dumps(variables)),
    )
    result = run("terraform", f"-chdir={directory}", "console", "-no-color", input=expression + "\n")
    return base64.b64decode(json.loads(result)).decode()


def local_tls(configuration):
    configuration = configuration.replace("load_module /usr/lib/nginx/modules/ngx_http_acme_module.so;\n", "")
    configuration = re.sub(r"  acme_issuer letsencrypt \{.*?\n  \}\n", "", configuration, flags=re.S)
    configuration = configuration.replace("    acme_certificate letsencrypt;\n", "")
    return configuration.replace("$acme_certificate_key", "/etc/nginx/e2e-key.pem").replace(
        "$acme_certificate", "/etc/nginx/e2e-cert.pem")


def reserve_check(port):
    # Fail before starting containers if any of this stack's fixed ports is occupied.
    with ExitStack() as stack:
        for current in range(port, port + 7):
            server = stack.enter_context(socket.socket())
            server.bind(("127.0.0.1", current))


def serve(port):
    reserve_check(port)
    run("docker", "info", "--format", "{{.ServerVersion}}", timeout=10)
    try:
        run("docker", "image", "inspect", IMAGE, timeout=10)
    except subprocess.CalledProcessError:
        run("docker", "pull", IMAGE, timeout=150)
    identifier = "openstudy-e2e-" + uuid.uuid4().hex[:10]
    with ExitStack() as cleanup:
        directory = Path(cleanup.enter_context(tempfile.TemporaryDirectory(prefix=identifier)))
        directory.chmod(0o755)
        for child in ("auth", "acme", "www", "www/current", "www/assets", "terraform"):
            (directory / child).mkdir()
        (directory / "acme").chmod(0o777)
        (directory / "www/current/index.html").write_text(
            '<!doctype html><html lang="en"><meta charset="utf-8"><title>OpenStudy deployment fixture</title>'
            '<h1>OpenStudy deployment fixture</h1><script src="/assets/app-e2e.js"></script></html>')
        (directory / "www/assets/app-e2e.js").write_text('document.documentElement.dataset.assetLoaded="true";')
        credentials = run("htpasswd", "-niB", "-C", "4", EMAIL, input=PASSWORD + "\n")
        (directory / "auth/htpasswd").write_text(credentials + "\n")
        run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1",
            "-keyout", str(directory / "key.pem"), "-out", str(directory / "cert.pem"))
        (directory / "key.pem").chmod(0o644)
        run("docker", "network", "create", identifier)
        cleanup.callback(remove, "network", "rm", identifier)

        # Echo upstream is an infrastructure fixture, not the OpenStudy Backend.
        (directory / "upstream.conf").write_text('''worker_processes 1;
pid /tmp/nginx.pid;
events { worker_connections 64; }
http {
  access_log off;
  client_body_temp_path /tmp/client_temp;
  proxy_temp_path /tmp/proxy_temp;
  fastcgi_temp_path /tmp/fastcgi_temp;
  uwsgi_temp_path /tmp/uwsgi_temp;
  scgi_temp_path /tmp/scgi_temp;
  server {
    listen 8081;
    default_type application/json;
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Credentials "false" always;
    location = /api/denied { return 401 '{"code":"FIXTURE_UNAUTHENTICATED"}'; }
    location /api {
      return 200 '{"uri":"$request_uri","proto":"$http_x_forwarded_proto","cookie":"$http_cookie","csrf":"$http_x_csrf_token","method":"$request_method"}';
    }
  }
}
''')
        upstream = identifier + "-upstream"
        cleanup.callback(remove, "rm", "-f", upstream)
        run("docker", "run", "-d", "--name", upstream, "--network", identifier,
            "--network-alias", "host.docker.internal", "--entrypoint", "nginx", "--user", "101:101",
            "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges", "--tmpfs", "/tmp:size=8m",
            "-v", f"{directory / 'upstream.conf'}:/etc/nginx/nginx.conf:ro", IMAGE, "-g", "daemon off;")
        origin = f"http://127.0.0.1:{port}"
        sites = {name: {"http": f"http://127.0.0.1:{port + 1 + index * 2}",
                        "https": f"https://127.0.0.1:{port + 2 + index * 2}"}
                 for index, (name, _, _) in enumerate(MODES)}
        origins = [origin, *(site["https"] for site in sites.values())]
        for index, (name, demo, backend) in enumerate(MODES):
            config = directory / f"{name}.conf"
            configuration = render(directory / "terraform", demo, backend, origins)
            config.write_text(configuration)
            container = identifier + "-" + name
            common = ["docker", "run", "--entrypoint", "nginx", "--user", "101:101", "--read-only",
                      "--cap-drop", "ALL", "--security-opt", "no-new-privileges", "--tmpfs", "/tmp:size=32m",
                      "--network", identifier,
                      "-v", f"{config}:/etc/nginx/nginx.conf:ro",
                      "-v", f"{ROOT / 'terraform/aws/templates/test-login.js'}:/etc/nginx/test-login.js:ro",
                      "-v", f"{directory / 'auth'}:/etc/nginx/auth:ro",
                      "-v", f"{directory / 'acme'}:/var/cache/nginx/acme",
                      "-v", f"{directory / 'www'}:/srv/openstudy:ro",
                      "-v", f"{directory / 'cert.pem'}:/etc/nginx/e2e-cert.pem:ro",
                      "-v", f"{directory / 'key.pem'}:/etc/nginx/e2e-key.pem:ro"]
            run(*common, "--rm", IMAGE, "-t")  # Includes production ACME/njs syntax.
            # Docker Desktop reserves host.docker.internal for the host itself.
            # In this isolated stack, route the identical proxy contract to our echo fixture.
            config.write_text(local_tls(configuration).replace("host.docker.internal:8081", f"{upstream}:8081"))
            cleanup.callback(remove, "rm", "-f", container)
            run(*common, "-d", "--name", container,
                "-p", f"127.0.0.1:{port + 1 + index * 2}:8080",
                "-p", f"127.0.0.1:{port + 2 + index * 2}:8443", IMAGE, "-g", "daemon off;")
            for attempt in range(50):
                connection = http.client.HTTPSConnection("127.0.0.1", port + 2 + index * 2,
                    context=ssl.create_default_context(cafile=str(directory / "cert.pem")), timeout=1)
                try:
                    connection.request("GET", "/")
                    if connection.getresponse().status == 200:
                        break
                except (OSError, http.client.HTTPException):
                    if attempt == 49:
                        logs = subprocess.run(["docker", "logs", "--tail", "10", container], capture_output=True, text=True)
                        raise RuntimeError(f"Nginx {name} did not become ready: {logs.stderr}")
                finally:
                    connection.close()
                time.sleep(0.1)
            else:
                raise RuntimeError(f"Nginx {name} never returned a healthy HTTPS response")

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                is_json = self.path in ("/ready", "/config")
                body = json.dumps(sites).encode() if is_json else b'<!doctype html><h1>Cross-origin test page</h1>'
                self.send_response(200)
                self.send_header("Content-Type", "application/json" if is_json else "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        cleanup.callback(server.server_close)
        signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=server.shutdown, daemon=True).start())
        signal.signal(signal.SIGINT, lambda *_: threading.Thread(target=server.shutdown, daemon=True).start())
        print(f"Disposable Nginx E2E stack ready on {origin}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18700)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65528:
        parser.error("--port must be from 1024 to 65528")
    # ExitStack cleans containers even if Playwright stops us during startup.
    def stop_startup(*_):
        raise SystemExit(143)
    signal.signal(signal.SIGTERM, stop_startup)
    try:
        serve(args.port)
    except (OSError, RuntimeError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f"E2E stack failed: {error}\n{getattr(error, 'stderr', '')}")
