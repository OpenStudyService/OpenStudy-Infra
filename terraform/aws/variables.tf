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
  description = "Server size. The two-container ECS budget profile uses the account-eligible c7i-flex.large."
  type        = string
  default     = "t4g.small"

  validation {
    condition     = contains(["t4g.small", "t4g.medium", "t3.micro", "c7i-flex.large"], var.instance_type)
    error_message = "Choose t4g.small, t4g.medium, t3.micro or c7i-flex.large."
  }
}

variable "server_availability_zone" {
  description = "AZ supporting the selected instance. Null uses the first available AZ."
  type        = string
  default     = null
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
  description = "Serve and deploy the Frontend over HTTPS at the DuckDNS hostname."
  type        = bool
  default     = false
}

variable "frontend_source_dir" {
  description = "Frontend checkout path. Null uses the sibling OpenStudy-Frontend checkout."
  type        = string
  default     = null
}

variable "frontend_api_mode" {
  description = "Frontend API mode: live for the backend, mock for the isolated browser demo."
  type        = string
  default     = "live"

  validation {
    condition     = contains(["live", "mock"], var.frontend_api_mode)
    error_message = "Choose live or mock for frontend_api_mode."
  }
}

variable "frontend_cors_allowed_origins" {
  description = "Additional exact browser origins allowed to call /api with cookies. The DuckDNS HTTPS origin is always included."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([for origin in var.frontend_cors_allowed_origins :
      length(origin) <= 267 &&
      can(regex("^https?://([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)*[a-z0-9]([a-z0-9-]*[a-z0-9])?(:[1-9][0-9]{0,4})?$", origin)) &&
      try(tonumber(regex(":([0-9]+)$", origin)[0]) <= 65535, true)
    ])
    error_message = "Use exact lowercase HTTP(S) origins such as http://localhost:5173, with ports 1-65535. Paths, trailing slashes, wildcards, credentials and IPv6 literals are not supported."
  }
}

variable "frontend_nginx_image" {
  description = "Pinned official Debian Nginx image with ACME and njs modules for HTTPS and server-only demo login."
  type        = string
  default     = "nginx:1.30.6"

  validation {
    condition     = can(regex("^nginx:[0-9]+\\.[0-9]+\\.[0-9]+$", var.frontend_nginx_image))
    error_message = "Use an explicit official Nginx version, such as nginx:1.30.6 (Debian, with ACME and njs)."
  }
}

variable "enable_database" {
  description = "Create one private Single-AZ RDS MySQL 8.4 primary. RDS and Secrets Manager incur separate charges."
  type        = bool
  default     = false
}

variable "apply_database_migrations" {
  description = "Run Flyway only after the dedicated database accounts and SecureString passwords have been prepared."
  type        = bool
  default     = false
}

variable "database_name" {
  description = "Initial MySQL database name."
  type        = string
  default     = "openstudy"
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]{0,63}$", var.database_name))
    error_message = "Use 1-64 letters and digits, starting with a letter."
  }
}

variable "database_engine_version" {
  description = "RDS MySQL 8.4 release available in the selected region."
  type        = string
  default     = "8.4.11"
  validation {
    condition     = can(regex("^8\\.4\\.[0-9]+$", var.database_engine_version))
    error_message = "The schema requires an explicit MySQL 8.4 patch release."
  }
}

variable "database_instance_class" {
  description = "Small Graviton RDS instance for this test service."
  type        = string
  default     = "db.t4g.micro"
  validation {
    condition     = contains(["db.t4g.micro", "db.t4g.small"], var.database_instance_class)
    error_message = "Choose db.t4g.micro or db.t4g.small."
  }
}

variable "database_storage_gib" {
  description = "Encrypted gp3 database storage in GiB; storage autoscaling is disabled."
  type        = number
  default     = 20
  validation {
    condition     = var.database_storage_gib >= 20 && var.database_storage_gib <= 100 && floor(var.database_storage_gib) == var.database_storage_gib
    error_message = "Choose an integer from 20 to 100 GiB."
  }
}

variable "database_backup_retention_days" {
  description = "Automated backup retention in days. OpenStudy defaults to 0, with backups disabled."
  type        = number
  default     = 0
  validation {
    condition     = var.database_backup_retention_days >= 0 && var.database_backup_retention_days <= 35 && floor(var.database_backup_retention_days) == var.database_backup_retention_days
    error_message = "Choose an integer from 0 to 35 days. Use 0 to disable automated backups."
  }
}

variable "database_apply_immediately" {
  description = "Apply approved RDS modifications immediately instead of waiting for the maintenance window."
  type        = bool
  default     = false
}

variable "database_deletion_protection" {
  description = "Disable and apply this setting before a deliberate database teardown."
  type        = bool
  default     = true
}

variable "database_skip_final_snapshot" {
  description = "Skip a final backup when deleting the database, as requested for OpenStudy."
  type        = bool
  default     = true
}

variable "database_final_snapshot_identifier" {
  description = "Unique final snapshot name. Null uses <name_prefix>-mysql-final."
  type        = string
  default     = null
  validation {
    condition     = var.database_final_snapshot_identifier == null ? true : can(regex("^[a-z][a-z0-9-]{0,253}[a-z0-9]$", var.database_final_snapshot_identifier)) && !strcontains(var.database_final_snapshot_identifier, "--")
    error_message = "Use 2-255 lowercase letters, digits or single hyphens, starting with a letter and ending with a letter or digit."
  }
}
