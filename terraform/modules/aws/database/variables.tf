variable "available_zone_names" {
  type = list(string)
}

variable "aws_account_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "database_apply_immediately" {
  type = bool
}

variable "database_availability_zones" {
  type = list(string)
}

variable "database_backup_retention_days" {
  type = number
}

variable "database_deletion_protection" {
  type = bool
}

variable "database_engine_version" {
  type = string
}

variable "database_final_snapshot_identifier" {
  type = string
}

variable "database_instance_class" {
  type = string
}

variable "database_migrations" {
  type = set(string)
}

variable "database_migrations_dir" {
  type = string
}

variable "database_name" {
  type = string
}

variable "database_schema_enabled" {
  type = bool
}

variable "database_skip_final_snapshot" {
  type = bool
}

variable "database_source_hash" {
  type = string
}

variable "database_sources" {
  type = map(string)
}

variable "database_storage_gib" {
  type = number
}

variable "enable_database" {
  type = bool
}

variable "iam_role_server_id" {
  type = string
}

variable "instance_server_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "root_dir" {
  type = string
}

variable "security_group_server_id" {
  type = string
}

variable "server_availability_zone" {
  type = string
}

variable "server_instance_revision" {
  type = any
}

variable "vpc_main_id" {
  type = string
}
