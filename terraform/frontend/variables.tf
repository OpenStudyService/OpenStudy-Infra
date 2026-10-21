variable "aws_account_id" {
  description = "Target account ID verified with aws sts get-caller-identity."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Set the 12-digit target AWS account ID."
  }
}

variable "aws_region" {
  description = "S3 deployment region. CloudFront and IAM are global services."
  type        = string
  default     = "ap-northeast-2"
}

variable "name_prefix" {
  type    = string
  default = "openstudy-prod"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,31}$", var.name_prefix))
    error_message = "Use 3-32 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "deploy_frontend" {
  description = "Build and publish the local Frontend during apply. Disable when GitHub Actions owns publication."
  type        = bool
  default     = true
}

variable "frontend_source_dir" {
  description = "Frontend checkout path. Null uses OpenStudy-Frontend beside OpenStudy-Infra. Relative paths start at terraform/frontend."
  type        = string
  default     = null

  validation {
    condition     = var.frontend_source_dir == null || try(trimspace(var.frontend_source_dir) != "", false)
    error_message = "Use a non-empty Frontend checkout path, or null for the sibling checkout."
  }
}

variable "github_repository" {
  description = "Only this repository can assume the frontend publishing role."
  type        = string
  default     = "OpenStudyService/OpenStudy-Frontend"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use an exact owner/repository name without wildcards."
  }
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN. Null creates a provider owned by this stack."
  type        = string
  default     = null

  validation {
    condition     = var.github_oidc_provider_arn == null || var.github_oidc_provider_arn == "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
    error_message = "Use the GitHub OIDC provider ARN from the target AWS account."
  }
}

variable "api_origin_domain_name" {
  description = "Optional Backend HTTPS hostname, without scheme/path. Null makes /api return a service-unavailable response."
  type        = string
  default     = null

  validation {
    condition     = var.api_origin_domain_name == null || can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.api_origin_domain_name))
    error_message = "Use a DNS hostname such as openstudy.duckdns.org, without https:// or a path."
  }
}
