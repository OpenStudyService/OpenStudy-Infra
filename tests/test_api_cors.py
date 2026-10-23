"""Exercise rendered Nginx CORS over HTTP without Docker or AWS.

Set TEST_NGINX_BINARY to a native Nginx 1.29.3+ executable. TLS/ACME and njs
are replaced with local fixtures; scripts/check-nginx.py checks those modules.
"""

import base64
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
PRODUCTION_ORIGIN = "https://openstudy.example.test"
DEVELOPMENT_ORIGIN = "http://localhost:5173"
VARIANTS = ((False, False), (True, False), (False, True))


class Upstream(BaseHTTPRequestHandler):
    calls = []

    def do_GET(self):
        self.calls.append(self.path)
        status = int(self.path.rsplit("/", 1)[-1]) if self.path.startswith("/api/status/") else 200
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Credentials", "false")
        self.send_header("Vary", "Accept-Encoding")
        self.send_header("Set-Cookie", "SESSION=fixture; Path=/; HttpOnly; Secure")
        self.end_headers()
        self.wfile.write(json.dumps({
            "uri": self.path, "method": self.command,
            "cookie": self.headers.get("Cookie"),
            "csrf": self.headers.get("X-CSRF-Token"),
        }).encode())

    do_POST = do_GET

    def log_message(self, *args):
        pass


@unittest.skipUnless(os.environ.get("TEST_NGINX_BINARY"), "Set TEST_NGINX_BINARY for native Nginx CORS checks")
class APICORSTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        cls.thread = threading.Thread(target=cls.upstream.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.upstream.shutdown()
        cls.upstream.server_close()
        cls.thread.join()

    @contextmanager
    def web(self, demo=False, backend=False):
        with tempfile.TemporaryDirectory(prefix="openstudy-api-cors-") as directory:
            root = Path(directory)
            (root / "logs").mkdir()
            (root / "index.html").write_text("<html>Frontend fixture</html>")
            (root / "test-login.json").write_text('{"ok":true}')
            (root / "assets").mkdir()
            (root / "assets/app.js").write_text("/* fixture */")
            credentials = subprocess.run(["htpasswd", "-nbm", "demo", "fixture-password"], check=True, capture_output=True, text=True).stdout
            (root / "htpasswd").write_text(credentials)
            values = {"hostname": "openstudy.example.test", "cors_allowed_origins": [PRODUCTION_ORIGIN, DEVELOPMENT_ORIGIN], "test_login_enabled": demo, "backend_enabled": backend}
            expression = 'base64encode(templatefile(%s, jsondecode(%s)))' % (
                json.dumps(str(ROOT / "terraform/aws/templates/nginx.conf.tftpl")), json.dumps(json.dumps(values)),
            )
            # An empty Terraform directory prevents access to the real stack/state.
            rendered = subprocess.run([shutil.which("terraform"), f"-chdir={root}", "console", "-no-color"], input=expression + "\n", capture_output=True, text=True, check=True).stdout
            config = base64.b64decode(json.loads(rendered)).decode()
            config = re.sub(r"^load_module .*;\n", "", config, flags=re.M)
            config = re.sub(r"  acme_issuer letsencrypt \{.*?\n  \}\n", "", config, flags=re.S)
            config = re.sub(r"  server \{\n    listen 8080;.*?\n  \}\n", "", config, flags=re.S)
            config = re.sub(r"^.*(?:acme_certificate|ssl_certificate|ssl_protocols|http2 on|js_engine|js_import|js_header_filter).*\n", "", config, flags=re.M)
            config = config.replace("include /etc/nginx/mime.types;", "types { text/html html; application/javascript js; }")
            config = config.replace("/tmp/", str(root) + "/").replace("/srv/openstudy/current", str(root)).replace("/srv/openstudy", str(root))
            config = config.replace("/etc/nginx/auth/htpasswd", str(root / "htpasswd"))
            config = config.replace("js_content test_login.success;", "try_files /test-login.json =404;")
            config = config.replace("js_content test_login.denied;", "return 401 '{\"ok\":false}';")
            config = config.replace("http://host.docker.internal:8081", f"http://127.0.0.1:{self.upstream.server_port}")
            with socket.socket() as port_socket:
                port_socket.bind(("127.0.0.1", 0))
                port = port_socket.getsockname()[1]
            config = config.replace("listen 8443 ssl;", f"listen 127.0.0.1:{port};")
            config_path = root / "nginx.conf"
            config_path.write_text(config)
            with (root / "nginx.log").open("w+") as log:
                process = subprocess.Popen([os.environ["TEST_NGINX_BINARY"], "-p", str(root), "-c", str(config_path), "-g", "daemon off;"], stdout=log, stderr=log)
                try:
                    for _ in range(100):
                        if process.poll() is not None:
                            log.seek(0)
                            self.fail(log.read())
                        try:
                            self.request(port, "/")
                            break
                        except OSError:
                            time.sleep(0.02)
                    else:
                        self.fail("Nginx did not start")
                    yield port
                finally:
                    process.terminate()
                    process.wait(timeout=5)

    def request(self, port, route, method="GET", headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
        try:
            connection.request(method, route, headers=headers or {})
            response = connection.getresponse()
            for name in ("Access-Control-Allow-Origin", "Access-Control-Allow-Credentials"):
                self.assertLessEqual(len(response.headers.get_all(name, [])), 1, response.getheaders())
            result = {}
            for name, value in response.getheaders():
                key = name.lower()
                result[key] = result[key] + ", " + value if key in result else value
            return response.status, result, response.read()
        finally:
            connection.close()

    def assert_cors(self, headers, origin):
        self.assertEqual(headers["access-control-allow-origin"], origin)
        self.assertEqual(headers["access-control-allow-credentials"], "true")
        self.assertIn("Origin", headers["vary"])

    def test_preflight_needs_no_session_and_never_reaches_upstream(self):
        for demo, backend in VARIANTS:
            with self.subTest(demo=demo, backend=backend), self.web(demo, backend) as port:
                for origin in (PRODUCTION_ORIGIN, DEVELOPMENT_ORIGIN):
                    for route in ("/api", "/api?x=1", "/api/echo", "/api%2Fecho", "/api/test-login"):
                        before = len(Upstream.calls)
                        status, headers, body = self.request(port, route, "OPTIONS", {"Origin": origin, "Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "content-type,x-csrf-token"})
                        self.assertEqual((status, body, len(Upstream.calls)), (204, b"", before))
                        self.assert_cors(headers, origin)
                        self.assertIn("POST", headers["access-control-allow-methods"])
                        self.assertIn("X-CSRF-Token", headers["access-control-allow-headers"])
                        self.assertEqual(headers["access-control-max-age"], "600")

    def test_api_success_and_errors_keep_cors_headers(self):
        for demo, backend in VARIANTS:
            with self.subTest(demo=demo, backend=backend), self.web(demo, backend) as port:
                routes = [("/api/echo", 200 if backend else 503), ("/api/test-login", 401 if demo else (200 if backend else 503))]
                if backend:
                    routes += [(f"/api/status/{status}", status) for status in (401, 403, 500)]
                for route, expected in routes:
                    status, headers, _ = self.request(port, route, headers={"Origin": DEVELOPMENT_ORIGIN})
                    self.assertEqual(status, expected)
                    self.assert_cors(headers, DEVELOPMENT_ORIGIN)
                    if demo and route == "/api/test-login":
                        self.assertEqual(headers["cache-control"], "no-store")

    def test_untrusted_origins_are_rejected_before_proxy(self):
        with self.web(backend=True) as port:
            for origin in ("null", "https://evil.test", PRODUCTION_ORIGIN + ".evil.test", DEVELOPMENT_ORIGIN + "0"):
                for method in ("GET", "POST", "OPTIONS"):
                    before = len(Upstream.calls)
                    for route in ("/api/echo", "/api%2Fecho", "/other/../api/echo"):
                        status, headers, _ = self.request(port, route, method, {"Origin": origin})
                        self.assertEqual((status, len(Upstream.calls)), (403, before))
                        self.assertNotIn("access-control-allow-origin", headers)
                        self.assertNotIn("access-control-allow-credentials", headers)

    def test_cookies_csrf_and_full_api_path_are_forwarded(self):
        with self.web(backend=True) as port:
            status, headers, body = self.request(port, "/api/report.json?x=1", "POST", {"Origin": DEVELOPMENT_ORIGIN, "Cookie": "SESSION=fixture", "X-CSRF-Token": "fixture-token"})
            self.assertEqual(status, 200)
            self.assert_cors(headers, DEVELOPMENT_ORIGIN)
            self.assertEqual(json.loads(body), {"uri": "/api/report.json?x=1", "method": "POST", "cookie": "SESSION=fixture", "csrf": "fixture-token"})
            self.assertIn("SESSION=fixture", headers["set-cookie"])

    def test_static_routes_have_no_cors_and_originless_api_still_works(self):
        with self.web(backend=True) as port:
            for route in ("/", "/login", "/apiary", "/assets/app.js", "/api/../assets/app.js"):
                status, headers, _ = self.request(port, route, headers={"Origin": "https://evil.test"})
                self.assertEqual(status, 200)
                self.assertFalse(any(name.startswith("access-control-") for name in headers))
            status, headers, _ = self.request(port, "/api/echo")
            self.assertEqual(status, 200)
            self.assertNotIn("access-control-allow-origin", headers)
            self.assertNotIn("access-control-allow-credentials", headers)


if __name__ == "__main__":
    unittest.main()
