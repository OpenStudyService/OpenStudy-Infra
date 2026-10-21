#!/usr/bin/env python3
"""Render each supported platform and check shell syntax without executing bootstrap."""

import ast
import base64
import json
from pathlib import Path
import subprocess


root = Path(__file__).resolve().parents[1]
for instance_type, enable_frontend in (("t4g.small", False), ("t3.micro", False), ("t4g.small", True), ("t3.micro", True)):
    result = subprocess.run(
        [
            "terraform", f"-chdir={root / 'terraform/aws'}", "console", "-no-color",
            "-var=aws_account_id=123456789012", f"-var=instance_type={instance_type}",
            f"-var=enable_frontend={str(enable_frontend).lower()}",
        ],
        input="base64encode(local.user_data)\n",
        capture_output=True,
        text=True,
        check=True,
    )
    script = base64.b64decode(json.loads(result.stdout)).decode()
    subprocess.run(["bash", "-n"], input=script, text=True, check=True)
    runner = script.split("<<'RUNNER'\n", 1)[1].split("\nRUNNER", 1)[0]
    subprocess.run(["bash", "-n"], input=runner, text=True, check=True)
    if "<<'DUCKDNS_PY'\n" in script:
        updater = script.split("<<'DUCKDNS_PY'\n", 1)[1].split("\nDUCKDNS_PY", 1)[0]
        ast.parse(updater)
    if len(script.encode()) > 16384:
        raise SystemExit("EC2 user data exceeds the 16 KiB limit.")
    if "${" in script:
        raise SystemExit("Bootstrap contains an unresolved template expression.")
    print(f"Bootstrap syntax and size passed: {instance_type}, frontend={enable_frontend}")
