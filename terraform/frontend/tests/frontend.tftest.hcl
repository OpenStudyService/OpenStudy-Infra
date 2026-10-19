mock_provider "aws" {
  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:function/openstudy-prod-frontend-spa"
    }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn                         = "arn:aws:s3:::openstudy-prod-frontend-123456789012-ap-northeast-2"
      bucket_regional_domain_name = "example.s3.ap-northeast-2.amazonaws.com"
    }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn         = "arn:aws:cloudfront::123456789012:distribution/EXAMPLE123"
      domain_name = "example123.cloudfront.net"
    }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

variables {
  aws_account_id = "123456789012"
}

run "private_static_site" {
  command = apply

  assert {
    condition     = aws_s3_bucket_public_access_block.frontend.block_public_acls && aws_s3_bucket_public_access_block.frontend.block_public_policy && aws_s3_bucket_public_access_block.frontend.ignore_public_acls && aws_s3_bucket_public_access_block.frontend.restrict_public_buckets && aws_s3_bucket_ownership_controls.frontend.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "S3 must remain private with ACLs disabled."
  }
  assert {
    condition     = jsondecode(aws_s3_bucket_policy.frontend.policy).Statement[0].Condition.StringEquals["AWS:SourceArn"] == aws_cloudfront_distribution.frontend.arn && aws_cloudfront_origin_access_control.frontend.signing_behavior == "always"
    error_message = "Only the configured CloudFront distribution may read S3 with OAC."
  }
  assert {
    condition     = aws_s3_bucket.frontend.force_destroy && !aws_cloudfront_distribution.frontend.retain_on_delete
    error_message = "Full teardown must delete static content and the distribution."
  }
  assert {
    condition     = length(aws_cloudfront_distribution.frontend.ordered_cache_behavior) == 0 && aws_cloudfront_distribution.frontend.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Static hosting must work without creating or opening a Backend server."
  }
  assert {
    condition     = jsondecode(aws_iam_role.frontend_deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:OpenStudyService/OpenStudy-Frontend:ref:refs/heads/main" && jsondecode(aws_iam_role.frontend_deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "Only the exact Frontend main branch and STS audience may assume the deployment role."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.frontend_deploy.policy).Statement[0].Resource == aws_s3_bucket.frontend.arn && jsondecode(aws_iam_role_policy.frontend_deploy.policy).Statement[2].Resource == aws_cloudfront_distribution.frontend.arn && !strcontains(aws_iam_role_policy.frontend_deploy.policy, "iam:") && !strcontains(aws_iam_role_policy.frontend_deploy.policy, "s3:DeleteObject")
    error_message = "The publisher must be scoped to its bucket/distribution without IAM or deletion rights."
  }
}

run "https_api_origin" {
  command = plan
  variables {
    api_origin_domain_name = "openstudy.duckdns.org"
  }
  assert {
    condition     = toset([for b in aws_cloudfront_distribution.frontend.ordered_cache_behavior : b.path_pattern]) == toset(["/api", "/api/*"]) && alltrue([for b in aws_cloudfront_distribution.frontend.ordered_cache_behavior : b.target_origin_id == "backend-https" && length(b.function_association) == 0 && length(b.allowed_methods) == 7])
    error_message = "Both API paths must preserve all methods and bypass SPA rewriting."
  }
  assert {
    condition     = alltrue([for o in aws_cloudfront_distribution.frontend.origin : o.custom_origin_config[0].origin_protocol_policy == "https-only" if o.origin_id == "backend-https"]) && data.aws_cloudfront_cache_policy.api[0].name == "Managed-CachingDisabled" && data.aws_cloudfront_origin_request_policy.api[0].name == "Managed-AllViewerExceptHostHeader"
    error_message = "API forwarding must use HTTPS, disable caching, and forward cookies/auth with the origin Host."
  }
}

run "reuse_shared_oidc_provider" {
  command = plan
  variables {
    github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  }
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0 && output.github_oidc_provider_arn == var.github_oidc_provider_arn
    error_message = "An existing account-wide provider must be reused without duplicate ownership."
  }
}

run "reject_wildcard_repository" {
  command = plan
  variables {
    github_repository = "OpenStudyService/*"
  }
  expect_failures = [var.github_repository]
}

run "reject_url_as_api_hostname" {
  command = plan
  variables {
    api_origin_domain_name = "https://openstudy.duckdns.org/api"
  }
  expect_failures = [var.api_origin_domain_name]
}
