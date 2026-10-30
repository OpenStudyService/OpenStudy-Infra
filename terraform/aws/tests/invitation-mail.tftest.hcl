mock_provider "aws" {
  mock_data "aws_availability_zones" { defaults = { names = ["ap-northeast-2a", "ap-northeast-2c"] } }
  mock_data "aws_ssm_parameter" { defaults = { value = "ami-0123456789abcdef0" } }
  mock_resource "aws_ssm_document" { defaults = { latest_version = "1" } }
}

variables {
  aws_account_id       = "123456789012"
  free_tier_confirmed  = true
  instance_type        = "t4g.medium"
  root_volume_size_gib = 30
  enable_ecs           = true
  enable_frontend      = true
  frontend_api_mode    = "live"
  frontend_source_dir  = "../frontend/tests/fixtures/frontend"
  web_ingress_cidrs    = ["0.0.0.0/0"]
  service_image        = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  service_environment  = { DB_URL = "jdbc:mysql://db.example:3306/openstudy?sslMode=VERIFY_IDENTITY", TRUSTED_PROXIES = "172.17.0.1/32" }
}

run "mail_absent_by_default" {
  command = plan
  assert {
    condition     = length(aws_ssm_parameter.invitation_smtp) == 0 && length(local.invitation_smtp_environment) == 0
    error_message = "Existing deployments must not enable mail or create SMTP secrets by default."
  }
}

run "smtp_uses_write_only_secrets_and_verified_starttls" {
  command = plan
  variables {
    invitation_smtp             = { from_address = "sender@example.test", enabled = true, credentials_version = 3 }
    invitation_smtp_credentials = { username = "sender@example.test", password = "test-only-smtp-secret" }
  }
  assert {
    condition     = length(aws_ssm_parameter.invitation_smtp) == 2 && alltrue([for p in aws_ssm_parameter.invitation_smtp : p.type == "SecureString" && p.tier == "Standard" && p.value_wo_version == 3 && startswith(p.name, "/openstudy-prod/apps/smtp-")])
    error_message = "SMTP credentials require two standard encrypted parameters with explicit rotation version."
  }
  assert {
    condition     = jsondecode(local.invitation_smtp_environment.SPRING_APPLICATION_JSON).management.health.mail.enabled == false && jsondecode(local.invitation_smtp_environment.SPRING_APPLICATION_JSON).spring.mail.port == 587 && jsondecode(local.invitation_smtp_environment.SPRING_APPLICATION_JSON).spring.mail.properties["mail.smtp.starttls.required"] == "true" && jsondecode(local.invitation_smtp_environment.SPRING_APPLICATION_JSON).spring.mail.properties["mail.smtp.ssl.checkserveridentity"] == "true" && jsondecode(local.invitation_smtp_environment.SPRING_APPLICATION_JSON).spring.mail.properties["mail.debug.auth"] == "false"
    error_message = "Gmail requires verified STARTTLS and bounded, non-debug SMTP transport."
  }
  assert {
    condition     = jsondecode(local.invitation_smtp_environment.SPRING_APPLICATION_JSON).openstudy["invitation-mail"]["acceptance-url"] == "https://openstudy.duckdns.org/invitations/accept" && jsondecode(local.invitation_smtp_environment.SPRING_APPLICATION_JSON).openstudy["invitation-mail"].enabled && contains(keys(local.app_secret_parameters), "SPRING_MAIL_PASSWORD") && contains(keys(local.app_secret_parameters), "SPRING_MAIL_USERNAME")
    error_message = "Send links to the actual HTTPS domain and inject SMTP credentials via secret ARNs."
  }
}

run "reject_missing_smtp_credentials" {
  command = plan
  variables { invitation_smtp = { from_address = "sender@example.test" } }
  expect_failures = [var.invitation_smtp_credentials]
}

run "reject_invalid_sender" {
  command = plan
  variables {
    invitation_smtp             = { from_address = "not-an-email" }
    invitation_smtp_credentials = { username = "sender@example.test", password = "test-only-smtp-secret" }
  }
  expect_failures = [var.invitation_smtp]
}

run "reject_competing_json_configuration" {
  command = plan
  variables {
    invitation_smtp             = { from_address = "sender@example.test" }
    invitation_smtp_credentials = { username = "sender@example.test", password = "test-only-smtp-secret" }
    service_environment         = { DB_URL = "jdbc:mysql://db.example:3306/openstudy", TRUSTED_PROXIES = "172.17.0.1/32", SPRING_APPLICATION_JSON = "{}" }
  }
  expect_failures = [aws_ssm_parameter.invitation_smtp]
}

run "credential_rotation_restarts_the_task" {
  command = plan
  variables {
    invitation_smtp             = { from_address = "sender@example.test", enabled = true, credentials_version = 4 }
    invitation_smtp_credentials = { username = "sender@example.test", password = "rotated-test-only-smtp-secret" }
  }
  assert {
    condition     = local.invitation_smtp_environment.OPENSTUDY_SMTP_CREDENTIALS_VERSION == "4" && aws_ssm_parameter.invitation_smtp["password"].value_wo_version == 4
    error_message = "A new secret version must also change task environment so ECS reads the new SecureString."
  }
}
