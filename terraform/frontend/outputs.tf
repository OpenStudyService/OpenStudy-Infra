output "frontend_url" {
  value = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "github_oidc_provider_arn" {
  description = "Reuse this provider in other stacks; do not create a second provider for the same URL."
  value       = local.github_oidc_provider_arn
}

output "github_actions_variables" {
  description = "Set these repository variables in OpenStudy-Frontend. No AWS access key is needed."
  value = {
    AWS_ACCOUNT_ID             = var.aws_account_id
    AWS_REGION                 = var.aws_region
    AWS_DEPLOY_ROLE_ARN        = aws_iam_role.frontend_deploy.arn
    S3_BUCKET                  = aws_s3_bucket.frontend.id
    CLOUDFRONT_DISTRIBUTION_ID = aws_cloudfront_distribution.frontend.id
  }
}
