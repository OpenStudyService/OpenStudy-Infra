locals {
  frontend_hostname   = "${var.duckdns_subdomain}.duckdns.org"
  frontend_caddyfile  = templatefile("${path.module}/templates/Caddyfile.tftpl", { hostname = local.frontend_hostname })
  frontend_source_dir = abspath(var.frontend_source_dir != null ? var.frontend_source_dir : "${path.module}/../../../OpenStudy-Frontend")
  frontend_sources = var.enable_frontend ? setunion(
    fileset(local.frontend_source_dir, "{src,public}/**"),
    fileset(local.frontend_source_dir, "{package.json,package-lock.json,index.html,tsconfig*.json,vite.config.*,eslint.config.*,.npmrc,.env,.env.local,.env.live,.env.live.local}"),
  ) : toset([])
  frontend_source_hash = sha256(jsonencode({
    for source in local.frontend_sources : source => filesha256("${local.frontend_source_dir}/${source}")
  }))
}

resource "aws_s3_bucket" "frontend_artifacts" {
  count         = var.enable_frontend ? 1 : 0
  bucket        = "${var.name_prefix}-web-${var.aws_account_id}-${var.aws_region}"
  force_destroy = true

  lifecycle {
    precondition {
      condition     = length("${var.name_prefix}-web-${var.aws_account_id}-${var.aws_region}") <= 63
      error_message = "Use a shorter name_prefix so the artifact bucket name is at most 63 characters."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_artifacts" {
  count                   = var.enable_frontend ? 1 : 0
  bucket                  = aws_s3_bucket.frontend_artifacts[0].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend_artifacts" {
  count  = var.enable_frontend ? 1 : 0
  bucket = aws_s3_bucket.frontend_artifacts[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "frontend_artifacts" {
  count  = var.enable_frontend ? 1 : 0
  bucket = aws_s3_bucket.frontend_artifacts[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.frontend_artifacts[0].arn, "${aws_s3_bucket.frontend_artifacts[0].arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_iam_role_policy" "frontend_artifacts" {
  count = var.enable_frontend ? 1 : 0
  name  = "read-frontend-release"
  role  = aws_iam_role.server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.frontend_artifacts[0].arn}/releases/*"
    }]
  })
}

resource "terraform_data" "frontend_deployment" {
  count = var.enable_frontend ? 1 : 0
  triggers_replace = {
    instance_id        = aws_instance.server.id
    association_id     = aws_ssm_association.server.association_id
    artifact_bucket    = aws_s3_bucket.frontend_artifacts[0].id
    source_hash        = local.frontend_source_hash
    script_hash        = filesha256("${path.module}/../../scripts/deploy-frontend-ec2.py")
    configuration_hash = sha256(local.frontend_caddyfile)
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for source in ["package.json", "package-lock.json", "index.html"] :
        fileexists("${local.frontend_source_dir}/${source}")
      ])
      error_message = "Check out OpenStudy-Frontend beside OpenStudy-Infra, or set frontend_source_dir."
    }
  }

  provisioner "local-exec" {
    command = "python3 \"$FRONTEND_DEPLOY_SCRIPT\""
    environment = {
      FRONTEND_DEPLOY_SCRIPT   = abspath("${path.module}/../../scripts/deploy-frontend-ec2.py")
      FRONTEND_SOURCE_DIR      = local.frontend_source_dir
      FRONTEND_HOSTNAME        = local.frontend_hostname
      FRONTEND_INSTANCE_ID     = aws_instance.server.id
      FRONTEND_ASSOCIATION_ID  = aws_ssm_association.server.association_id
      FRONTEND_ARTIFACT_BUCKET = aws_s3_bucket.frontend_artifacts[0].id
      AWS_ACCOUNT_ID           = var.aws_account_id
      AWS_REGION               = var.aws_region
    }
  }

  depends_on = [
    aws_ssm_association.server,
    aws_iam_role_policy.frontend_artifacts,
    aws_s3_bucket_public_access_block.frontend_artifacts,
    aws_s3_bucket_server_side_encryption_configuration.frontend_artifacts,
    aws_s3_bucket_policy.frontend_artifacts,
  ]
}
