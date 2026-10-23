#!/usr/bin/env python3
"""Check the real Nginx image, TLS, SPA routing, bcrypt login and API forwarding.

Uses disposable local Docker containers and a local test certificate. Does not
contact Let's Encrypt, read application credentials, or change AWS resources.
"""

import base64
import http.client
import json
from pathlib import Path
import re
import shutil
import ssl
import subprocess
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
IMAGE = "nginx:1.30.6"


def run(*args, timeout=120, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, check=True, timeout=timeout, **kwargs).stdout.strip()


def render_config(demo, backend):
    expression = 'base64encode(templatefile("templates/nginx.conf.tftpl", {hostname="openstudy.example.test", cors_allowed_origins=["https://openstudy.example.test", "http://localhost:5173"], test_login_enabled=%s, backend_enabled=%s}))' % (
        str(demo).lower(), str(backend).lower(),
    )
    rendered = run("terraform", f"-chdir={ROOT / 'terraform/aws'}", "console", "-no-color",
                   "-var=aws_account_id=123456789012", input=expression + "\n")
    return base64.b64decode(json.loads(rendered)).decode()


def request(port, route, *, tls=True, headers=None, method="GET", trusted=True, ca=None):
    if tls:
        context = ssl.create_default_context(cafile=str(ca) if trusted else None)
        connection = http.client.HTTPSConnection("127.0.0.1", port, context=context, timeout=5)
    else:
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        connection.request(method, route, headers={"Host": "openstudy.example.test", **(headers or {})})
        response = connection.getresponse()
        for name in ("Access-Control-Allow-Origin", "Access-Control-Allow-Credentials"):
            assert len(response.headers.get_all(name, [])) <= 1, (name, response.getheaders())
        return response.status, dict((key.lower(), value) for key, value in response.getheaders()), response.read()
    finally:
        connection.close()


def main():
    run("docker", "info", "--format", "{{.ServerVersion}}", timeout=10)
    run("docker", "pull", IMAGE, timeout=180)
    suffix = uuid.uuid4().hex[:10]
    network = f"openstudy-nginx-check-{suffix}"
    web, upstream = f"{network}-web", f"{network}-upstream"
    run("docker", "network", "create", network)
    try:
        with tempfile.TemporaryDirectory(prefix="openstudy-nginx-check-") as directory:
            workspace = Path(directory)
            workspace.chmod(0o755)
            for child in ("auth", "acme", "www", "www/current", "www/assets"):
                (workspace / child).mkdir(exist_ok=True)
            # The fixture contains disposable credentials only. Production uses
            # directories owned by UID 101 and a mode-600 htpasswd file.
            (workspace / "acme").chmod(0o777)
            (workspace / "www/current/index.html").write_text("<html>OpenStudy fixture</html>")
            (workspace / "www/assets/app-test.js").write_text("window.openstudyFixture = true;")
            password = "disposable-nginx-test-password"
            credentials = run("htpasswd", "-niB", "-C", "4", "demo@example.test", input=password + "\n")
            (workspace / "auth/htpasswd").write_text(credentials + "\n")
            shutil.copyfile(ROOT / "terraform/aws/templates/test-login.js", workspace / "test-login.js")
            run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                "-subj", "/CN=openstudy.example.test", "-addext", "subjectAltName=DNS:openstudy.example.test,IP:127.0.0.1",
                "-keyout", str(workspace / "key.pem"), "-out", str(workspace / "cert.pem"))
            (workspace / "key.pem").chmod(0o644)
            base = ["docker", "run", "--entrypoint", "nginx", "--user", "101:101",
                    "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
                    "--tmpfs", "/tmp:size=32m", "--network", network,
                    "-v", f"{workspace / 'nginx.conf'}:/etc/nginx/nginx.conf:ro",
                    "-v", f"{workspace / 'test-login.js'}:/etc/nginx/test-login.js:ro",
                    "-v", f"{workspace / 'auth'}:/etc/nginx/auth:ro",
                    "-v", f"{workspace / 'acme'}:/var/cache/nginx/acme",
                    "-v", f"{workspace / 'www'}:/srv/openstudy:ro",
                    "-v", f"{workspace / 'cert.pem'}:/etc/nginx/check-cert.pem:ro",
                    "-v", f"{workspace / 'key.pem'}:/etc/nginx/check-key.pem:ro"]
            (workspace / "upstream.conf").write_text('''worker_processes 1;
pid /tmp/nginx.pid;
error_log /dev/stderr;
events { worker_connections 32; }
http {
  access_log off;
  server {
    listen 8081;
    location /api {
      default_type application/json;
      add_header Access-Control-Allow-Origin "*" always;
      add_header Access-Control-Allow-Credentials "false" always;
      return 200 '{"uri":"$request_uri","proto":"$http_x_forwarded_proto","authorization":"$http_authorization","cookie":"$http_cookie"}';
    }
  }
}
''')
            run("docker", "run", "-d", "--name", upstream, "--network", network,
                "--network-alias", "host.docker.internal", "--entrypoint", "nginx", "--user", "101:101",
                "--read-only", "--cap-drop", "ALL", "--tmpfs", "/tmp:size=8m",
                "-v", f"{workspace / 'upstream.conf'}:/etc/nginx/nginx.conf:ro", IMAGE, "-g", "daemon off;")
            for demo, backend in ((False, False), (True, False), (False, True)):
                configuration = render_config(demo, backend)
                (workspace / "nginx.conf").write_text(configuration)
                run(*base, "--rm", IMAGE, "-t")  # Check the actual ACME and njs modules.
                # Only the local HTTP tests use a fixture certificate. Nginx
                # syntax above retains the production ACME configuration.
                fixture = configuration.replace("load_module /usr/lib/nginx/modules/ngx_http_acme_module.so;\n", "")
                fixture = re.sub(r"  acme_issuer letsencrypt \{.*?\n  \}\n", "", fixture, flags=re.S)
                fixture = fixture.replace("    acme_certificate letsencrypt;\n", "")
                fixture = fixture.replace("$acme_certificate_key", "/etc/nginx/check-key.pem")
                fixture = fixture.replace("$acme_certificate", "/etc/nginx/check-cert.pem")
                (workspace / "nginx.conf").write_text(fixture)
                run(*base, "-d", "--name", web, "-p", "127.0.0.1::8080", "-p", "127.0.0.1::8443", IMAGE, "-g", "daemon off;")
                try:
                    ports = json.loads(run("docker", "inspect", "--format", "{{json .NetworkSettings.Ports}}", web))
                    https_port = int(ports["8443/tcp"][0]["HostPort"])
                    http_port = int(ports["8080/tcp"][0]["HostPort"])
                    ca = workspace / "cert.pem"
                    for attempt in range(30):
                        try:
                            status, _, _ = request(https_port, "/", ca=ca)
                            break
                        except (OSError, http.client.HTTPException):
                            if attempt == 29:
                                raise
                            time.sleep(0.1)
                    assert status == 200
                    for route in ("/", "/login", "/invitations/accept?token=fixture"):
                        status, _, body = request(https_port, route, ca=ca)
                        assert status == 200 and b"OpenStudy fixture" in body, (route, status, body)
                    for route in ("/assets/missing.js", "/missing.css"):
                        assert request(https_port, route, ca=ca)[0] == 404, route
                    status, headers, _ = request(https_port, "/assets/app-test.js", ca=ca)
                    assert status == 200 and "immutable" in headers["cache-control"]
                    status, headers, _ = request(http_port, "/login?x=1", tls=False)
                    assert status == 308 and headers["location"] == "https://openstudy.example.test/login?x=1"
                    try:
                        request(https_port, "/", trusted=False)
                    except ssl.SSLCertVerificationError:
                        pass
                    else:
                        raise AssertionError("Untrusted TLS certificate was accepted")
                    for route in ("/api", "/api/echo", "/api/report.json?x=1"):
                        status, headers, body = request(https_port, route, headers={"Authorization": "Bearer fixture", "Cookie": "session=fixture"}, ca=ca)
                        assert headers["content-type"].startswith("application/json")
                        data = json.loads(body)
                        if backend:
                            assert status == 200 and data == {"uri": route, "proto": "https", "authorization": "Bearer fixture", "cookie": "session=fixture"}, data
                        else:
                            assert status == 503 and "message" in data, (status, data)
                    if demo:
                        for value, expected in ((None, 401), ("demo@example.test:wrong", 401), ("other@example.test:" + password, 401), ("demo@example.test:" + password, 200)):
                            auth = {} if value is None else {"Authorization": "Basic " + base64.b64encode(value.encode()).decode()}
                            status, headers, body = request(https_port, "/api/test-login", method="POST", headers=auth, ca=ca)
                            assert status == expected and json.loads(body) == {"ok": expected == 200}, (status, body)
                            assert "www-authenticate" not in headers
                            assert headers["cache-control"] == "no-store"
                    else:
                        assert request(https_port, "/api/test-login", ca=ca)[0] == (200 if backend else 503)
                    for origin in ("https://openstudy.example.test", "http://localhost:5173"):
                        for route in ("/api", "/api/echo", "/api/test-login"):
                            status, headers, body = request(https_port, route, method="OPTIONS", headers={
                                "Origin": origin, "Access-Control-Request-Method": "POST",
                                "Access-Control-Request-Headers": "content-type,x-csrf-token",
                            }, ca=ca)
                            assert status == 204 and not body, (status, body)
                            assert headers["access-control-allow-origin"] == origin
                            assert headers["access-control-allow-credentials"] == "true"
                            assert "POST" in headers["access-control-allow-methods"]
                            assert "X-CSRF-Token" in headers["access-control-allow-headers"]
                            assert headers["access-control-max-age"] == "600"
                        for route in ("/api/echo", "/api/test-login"):
                            status, headers, _ = request(https_port, route, headers={"Origin": origin}, ca=ca)
                            expected = 401 if demo and route == "/api/test-login" else (200 if backend else 503)
                            assert status == expected
                            assert headers["access-control-allow-origin"] == origin
                            assert headers["access-control-allow-credentials"] == "true"
                            assert "Origin" in headers["vary"]
                    for origin in ("https://untrusted.example.test", "null", "https://openstudy.example.test.evil.test"):
                        for method in ("GET", "POST", "OPTIONS"):
                            status, headers, _ = request(https_port, "/api/echo", method=method, headers={"Origin": origin}, ca=ca)
                            assert status == 403 and "access-control-allow-origin" not in headers
                    for route in ("/", "/apiary", "/assets/app-test.js"):
                        status, headers, _ = request(https_port, route, headers={"Origin": "http://localhost:5173"}, ca=ca)
                        assert status == 200 and not any(name.startswith("access-control-") for name in headers)
                    print(f"Nginx TLS/routing/auth checks passed: demo={demo}, backend={backend}")
                finally:
                    run("docker", "rm", "-f", web)
    finally:
        subprocess.run(["docker", "rm", "-f", web, upstream], capture_output=True, timeout=15)
        subprocess.run(["docker", "network", "rm", network], capture_output=True, timeout=15)


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f"Nginx check failed: {error}\n{getattr(error, 'stderr', '')}")
