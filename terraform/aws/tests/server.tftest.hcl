mock_provider "aws" {
  mock_resource "aws_ssm_document" {
    defaults = {
      latest_version = "1"
    }
  }

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-northeast-2a"]
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }
}

variables {
  aws_account_id      = "123456789012"
  aws_region          = "ap-northeast-2"
  name_prefix         = "openstudy-prod"
  instance_type       = "t4g.small"
  free_tier_confirmed = true
  enable_duckdns      = true
  duckdns_subdomain   = "openstudy"
  web_ingress_cidrs   = []
  enable_frontend     = false
}

run "server_security" {
  command = plan

  assert {
    condition     = length(module.network.security_group_server.ingress) == 0
    error_message = "The server must not expose any inbound ports."
  }

  assert {
    condition     = module.server.instance_server.metadata_options[0].http_tokens == "required" && module.server.instance_server.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Require IMDSv2 and keep metadata responses to one network hop."
  }

  assert {
    condition     = !module.server.instance_server.disable_api_termination && module.server.instance_server.root_block_device[0].delete_on_termination && module.server.instance_server.root_block_device[0].encrypted
    error_message = "The lab must allow teardown and delete its encrypted root volume on termination."
  }

  assert {
    condition     = module.server.instance_server.credit_specification[0].cpu_credits == "standard"
    error_message = "Use standard CPU credits to avoid unlimited-mode surplus charges."
  }

  assert {
    condition     = jsondecode(module.server.iam_role_policy_tunnel_token.policy).Statement[0].Resource == "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/cloudflared/token" && !contains(jsondecode(module.server.iam_role_policy_session_manager.policy).Statement[0].Action, "ssm:GetParameter")
    error_message = "Token access must remain limited to the dedicated SSM parameter."
  }

  assert {
    condition     = output.container_platform == "linux/arm64" && strcontains(data.aws_ssm_parameter.al2023.name, "arm64") && strcontains(local.user_data, "cloudflared-linux-aarch64.rpm")
    error_message = "The AMI, cloudflared RPM and application images must match Graviton."
  }

  assert {
    condition     = jsondecode(module.server.iam_role_policy_duckdns[0].policy).Statement[0].Resource == "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/duckdns/token" && output.duckdns_hostname == "openstudy.duckdns.org" && strcontains(local.user_data, "Environment=DUCKDNS_SUBDOMAIN=openstudy") && strcontains(local.user_data, "openstudy-duckdns.timer")
    error_message = "DuckDNS must use its own scoped SSM parameter and a boot-enabled update timer."
  }
}

run "legacy_x86" {
  command = plan

  variables {
    instance_type = "t3.micro"
  }

  assert {
    condition     = output.container_platform == "linux/amd64" && strcontains(data.aws_ssm_parameter.al2023.name, "x86_64") && strcontains(local.user_data, "cloudflared-linux-x86_64.rpm")
    error_message = "The t3.micro alternative must use x86 AMIs and binaries."
  }
}

run "direct_web_ports" {
  command = plan

  variables {
    web_ingress_cidrs = ["0.0.0.0/0"]
  }

  assert {
    condition     = toset([for rule in module.network.security_group_server.ingress : rule.from_port]) == toset([80, 443]) && alltrue([for rule in module.network.security_group_server.ingress : rule.from_port == rule.to_port && rule.protocol == "tcp" && rule.cidr_blocks == tolist(["0.0.0.0/0"])])
    error_message = "Direct access must expose only HTTP/HTTPS for the configured CIDRs."
  }
}

run "disable_duckdns" {
  command = plan

  variables {
    enable_duckdns = false
  }

  assert {
    condition     = length(module.server.iam_role_policy_duckdns) == 0 && output.duckdns_token_parameter_name == null && !strcontains(local.user_data, "Environment=DUCKDNS_SUBDOMAIN=") && strcontains(local.user_data, "systemctl disable --now openstudy-duckdns.timer")
    error_message = "Disabling DuckDNS must remove token access and stop an existing update timer."
  }
}

run "reject_full_hostname_as_subdomain" {
  command = plan

  variables {
    duckdns_subdomain = "openstudy.duckdns.org"
  }

  expect_failures = [var.duckdns_subdomain]
}

run "configuration_seed" {
  command = apply

  # Seed the previous release so the next run exercises a real upgrade.
  variables {
    cloudflared_version = "2026.10.1"
  }

  assert {
    condition     = !module.server.instance_server.user_data_replace_on_change && module.server.ssm_association_server.targets[0].values == tolist([module.server.instance_server.id]) && module.server.ssm_association_server.document_version == module.server.ssm_document_server.latest_version && module.server.ssm_association_server.wait_for_success_timeout_seconds == 1800
    error_message = "Terraform must apply the exact document version only to its server and wait for configuration success."
  }

  assert {
    condition     = jsondecode(module.server.iam_role_policy_server_configuration.policy).Statement[1].Resource == "arn:aws:ssm:ap-northeast-2:123456789012:document/openstudy-prod-configure-server" && alltrue([for statement in jsondecode(module.server.iam_role_policy_server_configuration.policy).Statement : !contains(statement.Action, "ssm:GetParameter") && !contains(statement.Action, "ssm:GetParameters")])
    error_message = "State Manager permissions must not grant broad Parameter Store access."
  }
}

run "configuration_update_keeps_server" {
  command = plan

  variables {
    cloudflared_version = "2026.10.2"
  }

  assert {
    condition     = module.server.instance_server.id == run.configuration_seed.instance_id
    error_message = "Changing the install version must preserve the existing instance."
  }

  assert {
    condition     = strcontains(module.server.ssm_document_server.content, "/download/2026.10.2/") && !strcontains(module.server.ssm_document_server.content, "/download/2026.10.1/")
    error_message = "The configuration change must be delivered through the SSM document."
  }
}

run "duckdns_static_hosting" {
  command = plan
  variables {
    enable_frontend     = true
    web_ingress_cidrs   = ["0.0.0.0/0"]
    frontend_source_dir = "../frontend/tests/fixtures/frontend"
  }
  assert {
    condition     = output.frontend_url == "https://openstudy.duckdns.org" && strcontains(local.user_data, "nginx:1.30.6") && strcontains(local.user_data, "systemctl start openstudy-duckdns.service") && strcontains(local.frontend_nginx_config, "root /srv/openstudy/current;")
    error_message = "The DuckDNS website must configure Nginx HTTPS and update DNS before starting the web server."
  }
  assert {
    condition     = length(module.frontend.terraform_data_frontend_deployment) == 1 && module.frontend.s3_bucket_frontend_artifacts[0].force_destroy && module.frontend.s3_bucket_public_access_block_frontend_artifacts[0].block_public_acls && module.frontend.s3_bucket_public_access_block_frontend_artifacts[0].block_public_policy
    error_message = "Static hosting must publish through a private artifact bucket that is deleted with the stack."
  }
}

run "explicit_demo_hosting" {
  command = plan
  variables {
    enable_frontend     = true
    frontend_api_mode   = "mock"
    web_ingress_cidrs   = ["0.0.0.0/0"]
    frontend_source_dir = "../frontend/tests/fixtures/frontend"
  }
  assert {
    condition     = module.frontend.terraform_data_frontend_deployment[0].triggers_replace.api_mode == "mock" && strcontains(local.frontend_nginx_config, "auth_basic") && strcontains(local.frontend_nginx_config, "auth_basic_user_file /etc/nginx/auth/htpasswd") && strcontains(local.user_data, "/etc/openstudy/nginx-auth/htpasswd.next") && jsondecode(module.server.iam_role_policy_frontend_test_login[0].policy).Statement[0].Resource == "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/frontend/test-login"
    error_message = "Demo login must use the server-only password hash loaded from its dedicated SSM parameter."
  }
}

run "reject_invalid_frontend_api_mode" {
  command = plan
  variables {
    frontend_api_mode = "invalid"
  }
  expect_failures = [var.frontend_api_mode]
}

run "api_cors_defaults_to_production_origin" {
  command = plan
  assert {
    condition     = local.frontend_cors_allowed_origins == tolist(["https://openstudy.duckdns.org"])
    error_message = "Credentialed API access must default to the exact production origin."
  }
}

run "api_cors_accepts_explicit_development_origins" {
  command = plan
  variables {
    frontend_cors_allowed_origins = ["http://localhost:5173", "http://127.0.0.1:5173", "https://openstudy.duckdns.org"]
  }
  assert {
    condition     = toset(local.frontend_cors_allowed_origins) == toset(["http://localhost:5173", "http://127.0.0.1:5173", "https://openstudy.duckdns.org"])
    error_message = "Explicit development origins must be merged with the production origin without duplicates."
  }
}

run "reject_unsafe_cors_origins" {
  command = plan
  variables {
    frontend_cors_allowed_origins = ["*", "null", "https://*.example.com", "https://example.com/", "https://example.com/api", "https://user@example.com", "http://localhost:65536", "https://example.com;return 200;", "https://$host"]
  }
  expect_failures = [var.frontend_cors_allowed_origins]
}
