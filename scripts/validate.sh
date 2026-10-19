#!/bin/bash
set -euo pipefail

task_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$task_root"

terraform fmt -check -recursive terraform
for task_stack in aws cloudflare frontend; do
  terraform -chdir="terraform/$task_stack" init -backend=false -input=false -no-color
  terraform -chdir="terraform/$task_stack" validate -no-color
  terraform -chdir="terraform/$task_stack" test -no-color
done
node --test tests/frontend-routing.test.cjs
python3 scripts/check-bootstrap.py
python3 -m unittest discover -s tests -v
