output "s3_bucket_frontend_artifacts" {
  value = [for item in aws_s3_bucket.frontend_artifacts : {
    arn           = item.arn
    bucket        = item.bucket
    force_destroy = item.force_destroy
    id            = item.id
  }]
}

output "s3_bucket_public_access_block_frontend_artifacts" {
  value = [for item in aws_s3_bucket_public_access_block.frontend_artifacts : {
    block_public_acls       = item.block_public_acls
    block_public_policy     = item.block_public_policy
    bucket                  = item.bucket
    id                      = item.id
    ignore_public_acls      = item.ignore_public_acls
    restrict_public_buckets = item.restrict_public_buckets
  }]
}

output "terraform_data_frontend_deployment" {
  value = [for item in terraform_data.frontend_deployment : {
    id               = item.id
    triggers_replace = item.triggers_replace
  }]
}
