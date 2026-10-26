mock_provider "aws" {}

variables {
  aws_account_id                        = "123456789012"
  aws_region                            = "ap-northeast-2"
  enable_frontend                       = true
  frontend_api_mode                     = "live"
  frontend_hostname                     = "openstudy.duckdns.org"
  frontend_nginx_config                 = "# test configuration"
  frontend_source_dir                   = "../../../frontend/tests/fixtures/frontend"
  frontend_source_hash                  = "test-source-hash"
  iam_role_server_id                    = "test-role"
  instance_server_id                    = "i-0123456789abcdef0"
  name_prefix                           = "openstudy-prod"
  root_dir                              = "../../../aws"
  ssm_association_server_association_id = "test-association"
}

run "reject_static_hosting_without_checkout" {
  command = plan
  variables { frontend_source_dir = "missing-frontend-checkout" }
  expect_failures = [terraform_data.frontend_deployment[0]]
}

run "reject_long_artifact_bucket_name" {
  command = plan
  variables { name_prefix = "openstudy-service-budget-project" }
  expect_failures = [aws_s3_bucket.frontend_artifacts[0]]
}
