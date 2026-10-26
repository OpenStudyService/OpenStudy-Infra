mock_provider "aws" {}

variables {
  ami                      = "ami-0123456789abcdef0"
  apps_enabled             = false
  available_zone_names     = ["ap-northeast-2a", "ap-northeast-2c"]
  aws_account_id           = "123456789012"
  aws_region               = "ap-northeast-2"
  duckdns_path             = "/openstudy-prod/duckdns/token"
  enable_duckdns           = true
  enable_ecs               = false
  enable_frontend          = false
  free_tier_confirmed      = true
  frontend_api_mode        = "live"
  frontend_test_login      = false
  gateway_image            = null
  instance_type            = "t4g.medium"
  name_prefix              = "openstudy-prod"
  root_volume_size_gib     = 30
  security_group_server_id = "sg-0123456789abcdef0"
  server_availability_zone = "ap-northeast-2a"
  service_image            = null
  subnet_public_id         = "subnet-0123456789abcdef0"
  token_path               = "/openstudy-prod/cloudflared/token"
  user_data                = "#!/bin/bash\ntrue\n"
  web_ingress_cidrs        = []
}

run "require_free_tier_review" {
  command = plan
  variables { free_tier_confirmed = false }
  expect_failures = [aws_instance.server]
}

run "reject_static_hosting_without_public_https" {
  command = plan
  variables { enable_frontend = true }
  expect_failures = [aws_instance.server]
}

run "reject_partial_images" {
  command = plan
  variables {
    enable_ecs    = true
    gateway_image = "example.com/gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
  expect_failures = [aws_ecs_cluster.apps]
}

run "reject_small_ecs_host" {
  command = plan
  variables {
    enable_ecs    = true
    instance_type = "t3.micro"
  }
  expect_failures = [aws_ecs_cluster.apps]
}
