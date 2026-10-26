variable "aws_account_id" {
  type = string
}

variable "db_instance_database_arn" {
  type = string
}

variable "db_instance_database_identifier" {
  type = string
}

variable "enable_database" {
  type = bool
}

variable "enable_operating_schedule" {
  type = bool
}

variable "instance_server_arn" {
  type = string
}

variable "instance_server_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "operating_schedules" {
  type = map(object({ expression = string, action = string }))
}


variable "archive_output_path" {
  type = string
}

variable "archive_source_hash" {
  type = string
}
