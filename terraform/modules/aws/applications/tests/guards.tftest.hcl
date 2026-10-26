mock_provider "aws" {}

variables {
  apps_enabled              = true
  architecture              = "arm64"
  aws_region                = "ap-northeast-2"
  database_schema_enabled   = true
  ecs_cluster_apps_id       = "test-cluster"
  ecs_trust_policy          = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  enable_ecs                = true
  gateway_environment       = {}
  gateway_image             = "example.com/gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  name_prefix               = "openstudy-prod"
  service_environment       = {}
  service_image             = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  service_secret_parameters = {}
}

run "reject_service_flyway_when_infra_migrates" {
  command = plan
  variables { service_environment = { SPRING_FLYWAY_ENABLED = "true" } }
  expect_failures = [aws_ecs_task_definition.apps]
}

run "reject_secret_flyway_override_when_infra_migrates" {
  command = plan
  variables {
    service_secret_parameters = { SPRING_FLYWAY_ENABLED = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/flyway" }
  }
  expect_failures = [aws_ecs_task_definition.apps]
}
