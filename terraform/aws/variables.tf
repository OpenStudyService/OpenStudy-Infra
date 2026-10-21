variable "aws_account_id" {
  description = "AWS account verified with STS before applying."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Set the 12-digit target AWS account ID."
  }
}

variable "aws_region" {
  description = "AWS deployment region."
  type        = string
  default     = "ap-northeast-2"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "Use an AWS region such as ap-northeast-2."
  }
}

variable "name_prefix" {
  description = "Resource name prefix, also used for the SSM token path."
  type        = string
  default     = "openstudy-prod"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,31}$", var.name_prefix))
    error_message = "Use 3-32 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "instance_type" {
  description = "Use t4g.small after checking account eligibility; t3.micro is the x86 alternative."
  type        = string
  default     = "t4g.small"

  validation {
    condition     = contains(["t4g.small", "t3.micro"], var.instance_type)
    error_message = "Choose t4g.small or t3.micro and review the account's Free Tier eligibility."
  }
}

variable "free_tier_confirmed" {
  description = "Set true only after checking the account plan, credit balance and selected instance."
  type        = bool
  default     = false
}

variable "swap_size_mib" {
  description = "Swap size in MiB. Keep space available on the 8 GiB root volume."
  type        = number
  default     = 1024

  validation {
    condition     = contains([1024, 2048], var.swap_size_mib)
    error_message = "Swap must be 1024 or 2048 MiB."
  }
}

variable "root_volume_size_gib" {
  description = "Encrypted gp3 root volume size in GiB."
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size_gib >= 8 && floor(var.root_volume_size_gib) == var.root_volume_size_gib
    error_message = "Use an integer volume size of at least 8 GiB."
  }
}

variable "cloudflared_version" {
  description = "Pinned official cloudflared RPM release."
  type        = string
  default     = "2026.10.2"

  validation {
    condition     = can(regex("^[0-9]{4}\\.[0-9]{1,2}\\.[0-9]+$", var.cloudflared_version))
    error_message = "Use a cloudflared release such as 2026.10.2."
  }
}

variable "enable_duckdns" {
  description = "Synchronize the DuckDNS A record with the instance public IPv4 at boot and after IP changes."
  type        = bool
  default     = true
}

variable "duckdns_subdomain" {
  description = "DuckDNS subdomain registered by the token owner, without .duckdns.org."
  type        = string
  default     = "openstudy"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.duckdns_subdomain))
    error_message = "Use a single lowercase DNS label such as openstudy, without .duckdns.org."
  }
}

variable "web_ingress_cidrs" {
  description = "IPv4 CIDRs allowed to access TCP 80/443 directly. Empty keeps all inbound ports closed for Tunnel operation."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.web_ingress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Use IPv4 CIDR ranges, or an empty list for no inbound web access."
  }
}

variable "enable_frontend" {
  description = "Serve and deploy the live Frontend over HTTPS at the DuckDNS hostname."
  type        = bool
  default     = false
}

variable "frontend_source_dir" {
  description = "Frontend checkout path. Null uses the sibling OpenStudy-Frontend checkout."
  type        = string
  default     = null
}

variable "frontend_caddy_image" {
  description = "Pinned official Caddy image used for static hosting and automatic HTTPS."
  type        = string
  default     = "caddy:2.11.7-alpine"

  validation {
    condition     = can(regex("^caddy:[0-9]+\\.[0-9]+\\.[0-9]+-alpine$", var.frontend_caddy_image))
    error_message = "Use an explicit official Caddy version, such as caddy:2.11.7-alpine."
  }
}
