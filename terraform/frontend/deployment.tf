locals {
  frontend_source_dir = abspath(var.frontend_source_dir != null ? var.frontend_source_dir : "${path.module}/../../../OpenStudy-Frontend")
  frontend_source_files = var.deploy_frontend ? setunion(
    fileset(local.frontend_source_dir, "{src,public}/**"),
    fileset(local.frontend_source_dir, "{package.json,package-lock.json,index.html,tsconfig*.json,vite.config.*,eslint.config.*,.npmrc,.env,.env.local,.env.live,.env.live.local}"),
    fileset(local.frontend_source_dir, "scripts/deploy-static.sh"),
  ) : toset([])
  frontend_source_hashes = {
    for source in local.frontend_source_files : source => filesha256("${local.frontend_source_dir}/${source}")
  }
}

resource "terraform_data" "frontend_deployment" {
  count = var.deploy_frontend ? 1 : 0

  triggers_replace = {
    source_hash     = sha256(jsonencode(local.frontend_source_hashes))
    script_hash     = filesha256("${path.module}/../../scripts/deploy-frontend.sh")
    bucket          = aws_s3_bucket.frontend.id
    distribution_id = aws_cloudfront_distribution.frontend.id
    aws_account_id  = var.aws_account_id
    aws_region      = var.aws_region
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for source in ["package.json", "package-lock.json", "index.html", "scripts/deploy-static.sh"] :
        fileexists("${local.frontend_source_dir}/${source}")
      ])
      error_message = "Check out OpenStudy-Frontend beside OpenStudy-Infra, or set frontend_source_dir. Set deploy_frontend = false for infrastructure-only deployment."
    }
  }

  provisioner "local-exec" {
    command = "bash \"$FRONTEND_DEPLOY_SCRIPT\""
    environment = {
      FRONTEND_DEPLOY_SCRIPT     = abspath("${path.module}/../../scripts/deploy-frontend.sh")
      FRONTEND_SOURCE_DIR        = local.frontend_source_dir
      AWS_ACCOUNT_ID             = var.aws_account_id
      AWS_REGION                 = var.aws_region
      S3_BUCKET                  = aws_s3_bucket.frontend.id
      CLOUDFRONT_DISTRIBUTION_ID = aws_cloudfront_distribution.frontend.id
    }
  }

  # The publisher verifies CloudFront reads, so the bucket policy must be ready.
  depends_on = [aws_s3_bucket_policy.frontend]
}
