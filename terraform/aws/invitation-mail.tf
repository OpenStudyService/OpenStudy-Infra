variable "invitation_smtp" {
  description = "Gmail STARTTLS configuration for the existing Backend. Null leaves SMTP unconfigured."
  type = object({
    from_address        = string
    enabled             = optional(bool, false)
    credentials_version = optional(number, 1)
  })
  default = null
  validation {
    condition = var.invitation_smtp == null ? true : (
      can(regex("^[^[:space:]@<>]+@[^[:space:]@<>]+\\.[^[:space:]@<>]+$", var.invitation_smtp.from_address)) &&
      var.invitation_smtp.credentials_version >= 1 && floor(var.invitation_smtp.credentials_version) == var.invitation_smtp.credentials_version
    )
    error_message = "Set one sender email address and a positive integer credentials_version."
  }
}

variable "invitation_smtp_credentials" {
  description = "Runtime-only SMTP credentials. Use scripts/terraform-smtp.py; values never enter plan or state."
  type        = object({ username = string, password = string })
  sensitive   = true
  ephemeral   = true
  default     = null
  validation {
    condition = var.invitation_smtp == null ? true : (
      var.invitation_smtp_credentials == null ? false : (
        trimspace(var.invitation_smtp_credentials.username) != "" && var.invitation_smtp_credentials.password != ""
      )
    )
    error_message = "Provide runtime-only SMTP credentials through scripts/terraform-smtp.py."
  }
}

resource "aws_ssm_parameter" "invitation_smtp" {
  for_each = var.invitation_smtp == null ? toset([]) : toset(["username", "password"])
  name     = "/${var.name_prefix}/apps/smtp-${each.key}"
  type     = "SecureString"
  tier     = "Standard"

  value_wo         = try(var.invitation_smtp_credentials[each.key], null)
  value_wo_version = var.invitation_smtp.credentials_version

  lifecycle {
    precondition {
      condition     = local.apps_enabled && !contains(keys(var.service_environment), "SPRING_APPLICATION_JSON") && !contains(keys(var.service_secret_parameters), "SPRING_APPLICATION_JSON")
      error_message = "SMTP requires the real Backend. Its mail configuration owns SPRING_APPLICATION_JSON."
    }
  }
}

locals {
  invitation_smtp_environment = var.invitation_smtp == null ? {} : {
    # ECS reads SecureStrings at task start; a new credential version must restart it.
    OPENSTUDY_SMTP_CREDENTIALS_VERSION = tostring(var.invitation_smtp.credentials_version)
    SPRING_APPLICATION_JSON = jsonencode({
      management = { health = { mail = { enabled = false } } }
      spring = {
        mail = {
          host              = "smtp.gmail.com"
          port              = 587
          "test-connection" = true
          properties = {
            "mail.smtp.auth"                    = "true"
            "mail.smtp.starttls.enable"         = "true"
            "mail.smtp.starttls.required"       = "true"
            "mail.smtp.ssl.checkserveridentity" = "true"
            "mail.smtp.connectiontimeout"       = "5000"
            "mail.smtp.timeout"                 = "10000"
            "mail.smtp.writetimeout"            = "10000"
            "mail.debug"                        = "false"
            "mail.debug.auth"                   = "false"
          }
        }
      }
      openstudy = {
        "invitation-mail" = {
          enabled          = var.invitation_smtp.enabled
          from             = var.invitation_smtp.from_address
          "acceptance-url" = "https://${local.frontend_hostname}/invitations/accept"
        }
      }
    })
  }
  app_secret_parameters = merge(var.service_secret_parameters, var.invitation_smtp == null ? {} : {
    SPRING_MAIL_USERNAME = aws_ssm_parameter.invitation_smtp["username"].arn
    SPRING_MAIL_PASSWORD = aws_ssm_parameter.invitation_smtp["password"].arn
  })
}
