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
  cloudflared_version = "2026.10.1"
  free_tier_confirmed = true
  enable_duckdns      = true
  duckdns_subdomain   = "openstudy"
  web_ingress_cidrs   = []
}

run "server_security" {
  command = plan

  assert {
    condition     = length(aws_security_group.server.ingress) == 0
    error_message = "The server must not expose any inbound ports."
  }

  assert {
    condition     = aws_instance.server.metadata_options[0].http_tokens == "required" && aws_instance.server.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Require IMDSv2 and keep metadata responses to one network hop."
  }

  assert {
    condition     = aws_instance.server.disable_api_termination && !aws_instance.server.root_block_device[0].delete_on_termination && aws_instance.server.root_block_device[0].encrypted
    error_message = "Protect the instance from termination and retain the encrypted root volume."
  }

  assert {
    condition     = aws_instance.server.credit_specification[0].cpu_credits == "standard"
    error_message = "Use standard CPU credits to avoid unlimited-mode surplus charges."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.tunnel_token.policy).Statement[0].Resource == "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/cloudflared/token" && !contains(jsondecode(aws_iam_role_policy.session_manager.policy).Statement[0].Action, "ssm:GetParameter")
    error_message = "Token access must remain limited to the dedicated SSM parameter."
  }

  assert {
    condition     = output.container_platform == "linux/arm64" && strcontains(data.aws_ssm_parameter.al2023.name, "arm64") && strcontains(local.user_data, "cloudflared-linux-aarch64.rpm")
    error_message = "The AMI, cloudflared RPM and application images must match Graviton."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.duckdns[0].policy).Statement[0].Resource == "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/duckdns/token" && output.duckdns_hostname == "openstudy.duckdns.org" && strcontains(local.user_data, "Environment=DUCKDNS_SUBDOMAIN=openstudy") && strcontains(local.user_data, "openstudy-duckdns.timer")
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

run "require_free_tier_review" {
  command = plan

  variables {
    free_tier_confirmed = false
  }

  expect_failures = [aws_instance.server]
}

run "direct_web_ports" {
  command = plan

  variables {
    web_ingress_cidrs = ["0.0.0.0/0"]
  }

  assert {
    condition     = toset([for rule in aws_security_group.server.ingress : rule.from_port]) == toset([80, 443]) && alltrue([for rule in aws_security_group.server.ingress : rule.from_port == rule.to_port && rule.protocol == "tcp" && rule.cidr_blocks == tolist(["0.0.0.0/0"])])
    error_message = "Direct access must expose only HTTP/HTTPS for the configured CIDRs."
  }
}

run "disable_duckdns" {
  command = plan

  variables {
    enable_duckdns = false
  }

  assert {
    condition     = length(aws_iam_role_policy.duckdns) == 0 && output.duckdns_token_parameter_name == null && !strcontains(local.user_data, "Environment=DUCKDNS_SUBDOMAIN=") && strcontains(local.user_data, "systemctl disable --now openstudy-duckdns.timer")
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

  assert {
    condition     = !aws_instance.server.user_data_replace_on_change && aws_ssm_association.server.targets[0].values == tolist([aws_instance.server.id]) && aws_ssm_association.server.document_version == aws_ssm_document.server.latest_version && aws_ssm_association.server.wait_for_success_timeout_seconds == 1800
    error_message = "Terraform must apply the exact document version only to its server and wait for configuration success."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.server_configuration.policy).Statement[1].Resource == "arn:aws:ssm:ap-northeast-2:123456789012:document/openstudy-prod-configure-server" && alltrue([for statement in jsondecode(aws_iam_role_policy.server_configuration.policy).Statement : !contains(statement.Action, "ssm:GetParameter") && !contains(statement.Action, "ssm:GetParameters")])
    error_message = "State Manager permissions must not grant broad Parameter Store access."
  }
}

run "configuration_update_keeps_server" {
  command = plan

  variables {
    cloudflared_version = "2026.10.2"
  }

  assert {
    condition     = aws_instance.server.id == run.configuration_seed.instance_id
    error_message = "Changing the install version must preserve the existing instance."
  }

  assert {
    condition     = strcontains(aws_ssm_document.server.content, "/download/2026.10.2/") && !strcontains(aws_ssm_document.server.content, "/download/2026.10.1/")
    error_message = "The configuration change must be delivered through the SSM document."
  }
}
