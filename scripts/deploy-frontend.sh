#!/usr/bin/env bash
set -euo pipefail

: "${FRONTEND_SOURCE_DIR:?Set FRONTEND_SOURCE_DIR}"
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"
: "${AWS_REGION:?Set AWS_REGION}"
: "${S3_BUCKET:?Set S3_BUCKET}"
: "${CLOUDFRONT_DISTRIBUTION_ID:?Set CLOUDFRONT_DISTRIBUTION_ID}"

for required_command in node npm aws curl cmp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Install $required_command before applying the frontend stack." >&2
    exit 1
  fi
done

if [[ ! "$(node --version)" =~ ^v24\. ]]; then
  echo 'Frontend deployment requires Node.js 24.' >&2
  exit 1
fi

for source in package.json package-lock.json index.html scripts/deploy-static.sh; do
  if [[ ! -f "$FRONTEND_SOURCE_DIR/$source" ]]; then
    echo "Missing frontend source: $FRONTEND_SOURCE_DIR/$source" >&2
    exit 1
  fi
done

export AWS_PAGER=''
deployment_account=$(aws sts get-caller-identity --region "$AWS_REGION" --query Account --output text)
if [[ "$deployment_account" != "$AWS_ACCOUNT_ID" ]]; then
  echo 'AWS CLI account does not match the Terraform target account.' >&2
  exit 1
fi

cd "$FRONTEND_SOURCE_DIR"
export VITE_API_MODE=live
export VITE_API_BASE_URL=/api

npm ci --include=dev
npm run check
npm run build
bash scripts/deploy-static.sh
