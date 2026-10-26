#!/usr/bin/env python3
"""Compare a flat AWS configuration from Git with the current modules using mocks."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import uuid


ROOT = Path(__file__).resolve().parents[1]
AWS = ROOT / "terraform/aws"


def run(*arguments):
    result = subprocess.run(arguments, cwd=AWS, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"Command failed: {' '.join(arguments)}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def check_moves(base_ref, api_mode):
    token = uuid.uuid4().hex[:10]
    test = AWS / "tests" / f"module_moves_{token}.tftest.hcl"
    try:
        with tempfile.TemporaryDirectory(prefix=".module-move-", dir=AWS) as temporary:
            legacy = Path(temporary) / "legacy"
            legacy.mkdir()
            paths = run("git", "ls-tree", "--full-tree", "--name-only", f"{base_ref}:terraform/aws").splitlines()
            for name in paths:
                if name.endswith(".tf"):
                    content = run("git", "show", f"{base_ref}:terraform/aws/{name}")
                    # Run the historical root module against the same local assets.
                    content = content.replace("${path.module}", ".")
                    # Provisioners are local side effects, even with mock providers.
                    content = re.sub(r'^  provisioner "[^\"]+" \{.*?^  }\n', '', content, flags=re.M | re.S)
                    if 'provisioner "' in content:
                        raise RuntimeError("Cannot safely disable a historical provisioner.")
                    (legacy / name).write_text(content)
            source = legacy.relative_to(AWS).as_posix()
            test.write_text('''mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-northeast-2a", "ap-northeast-2c"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_resource "aws_ssm_document" {
    defaults = { latest_version = "1" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-role" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:ap-northeast-2:123456789012:function:test" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:ap-northeast-2:123456789012:task-definition/test:1", revision = 1 }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      address = "openstudy.example.ap-northeast-2.rds.amazonaws.com"
      endpoint = "openstudy.example.ap-northeast-2.rds.amazonaws.com:3306"
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:test", kms_key_id = "test", secret_status = "active" }]
    }
  }
}
mock_provider "archive" {
  mock_data "archive_file" {
    defaults = { output_base64sha256 = "dGVzdA==" }
  }
}
variables {
  aws_account_id = "123456789012"
  aws_region = "ap-northeast-2"
  name_prefix = "openstudy-prod"
  free_tier_confirmed = true
  instance_type = "t4g.medium"
  root_volume_size_gib = 30
  server_availability_zone = null
  swap_size_mib = 1024
  cloudflared_version = "2026.10.2"
  enable_frontend = true
  frontend_api_mode = "API_MODE"
  enable_duckdns = true
  duckdns_subdomain = "openstudy"
  frontend_cors_allowed_origins = []
  frontend_nginx_image = "nginx:1.30.6"
  frontend_source_dir = "../frontend/tests/fixtures/frontend"
  web_ingress_cidrs = ["0.0.0.0/0"]
  enable_database = true
  apply_database_migrations = true
  database_name = "openstudy"
  database_engine_version = "8.4.11"
  database_instance_class = "db.t4g.micro"
  database_storage_gib = 20
  database_backup_retention_days = 0
  database_apply_immediately = false
  database_deletion_protection = true
  database_skip_final_snapshot = true
  database_final_snapshot_identifier = null
  enable_ecs = true
  enable_operating_schedule = true
  gateway_environment = {}
  service_environment = {}
  service_secret_parameters = {}
  gateway_image = GATEWAY_IMAGE
  service_image = SERVICE_IMAGE
}
run "before" {
  command = apply
  state_key = "migration"
  module {
    source = "./SOURCE"
  }
  override_resource {
    target = terraform_data.frontend_deployment[0]
    values = { id = "test-frontend-release" }
  }
}
run "after" {
  command = plan
  state_key = "migration"
  plan_options { refresh = false }
  override_resource {
    target = module.frontend.terraform_data.frontend_deployment[0]
    values = { id = "test-frontend-release" }
  }
  assert {
    condition = output.instance_id == run.before.instance_id && output.database_endpoint == run.before.database_endpoint
    error_message = "Module moves must preserve EC2 and RDS identities."
  }
}
'''.replace("SOURCE", source).replace("API_MODE", api_mode)
                .replace("GATEWAY_IMAGE", json.dumps("example.com/gateway@sha256:" + "a" * 64) if api_mode == "live" else "null")
                .replace("SERVICE_IMAGE", json.dumps("example.com/service@sha256:" + "b" * 64) if api_mode == "live" else "null"))
            run("terraform", "init", "-backend=false", "-input=false", "-no-color")
            output = run("terraform", "test", f"-filter=tests/{test.name}", "-json", "-verbose")
            events = [json.loads(line) for line in output.splitlines() if line.startswith("{")]
            plans = [event["test_plan"] for event in events if event.get("type") == "test_plan"]
            if len(plans) != 1:
                raise RuntimeError(f"Expected one migration plan, received {len(plans)}.\n{output}")
            changes = [change for change in plans[0].get("resource_changes", []) if change["mode"] == "managed"]
            unexpected = [change for change in changes if change["change"]["actions"] != ["no-op"] and not (
                change["address"] == "module.database.terraform_data.server_instance[0]" and change["change"]["actions"] == ["create"]
            )]
            if unexpected:
                details = []
                for resource in unexpected:
                    change = resource["change"]
                    before, after = change["before"] or {}, change["after"] or {}
                    changed = [key for key in before.keys() | after.keys()
                               if before.get(key) != after.get(key) or change.get("after_unknown", {}).get(key)]
                    details.append({"address": resource["address"], "actions": change["actions"], "changed_attributes": sorted(changed)})
                raise RuntimeError(f"Module split changes existing resources:\n{json.dumps(details, indent=2)}")
            outputs = plans[0].get("output_changes", {})
            changed_outputs = [name for name, change in outputs.items() if change["actions"] != ["no-op"]]
            if changed_outputs:
                raise RuntimeError(f"Module split changes public outputs: {changed_outputs}")
            bookkeeping = [change for change in changes if change["address"] == "module.database.terraform_data.server_instance[0]" and change["change"]["actions"] == ["create"]]
            if len(bookkeeping) != 1:
                raise RuntimeError("Expected one local Terraform bookkeeping record.")
            moved = [change for change in changes if change.get("previous_address")]
            aws_changes = [change for change in changes if change["type"].startswith("aws_")]
            if not aws_changes or any(not change.get("previous_address") for change in aws_changes):
                raise RuntimeError("Every existing AWS resource must be connected by a moved block.")
            return {
                "base_ref": base_ref,
                "frontend_api_mode": api_mode,
                "aws_resources_preserved": len(aws_changes),
                "resource_instances_moved": len(moved),
                "public_outputs_preserved": len(outputs),
                "aws_creates": 0,
                "aws_updates": 0,
                "aws_replacements": 0,
                "aws_deletes": 0,
                "new_terraform_bookkeeping": len(bookkeeping),
                "_checked_moves": [re.sub(r'\[.*?\]', '', change["previous_address"]) for change in moved],
            }
    finally:
        test.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-ref", required=True, help="Git ref containing the flat AWS configuration.")
    parser.add_argument("--api-mode", choices=["live", "mock", "both"], default="both")
    args = parser.parse_args()
    try:
        modes = ["live", "mock"] if args.api_mode == "both" else [args.api_mode]
        results = [check_moves(args.base_ref, mode) for mode in modes]
        checked = {address for result in results for address in result.pop("_checked_moves")}
        expected = set(re.findall(r'^\s*from\s*=\s*(\S+)', (AWS / "moved.tf").read_text(), re.M))
        if args.api_mode == "both" and checked != expected:
            raise RuntimeError(f"Unchecked or unexpected resource moves: {sorted(checked ^ expected)}")
        print(json.dumps({"moved_declarations_checked": len(checked), "scenarios": results}, indent=2))
    except (OSError, ValueError, RuntimeError) as error:
        parser.exit(1, f"Module migration check failed: {error}\n")
