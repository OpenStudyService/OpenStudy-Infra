variable "aws_account_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "enable_frontend" {
  type = bool
}

variable "frontend_api_mode" {
  type = string
}

variable "frontend_hostname" {
  type = string
}

variable "frontend_nginx_config" {
  type = string
}

variable "frontend_source_dir" {
  type = string
}

variable "frontend_source_hash" {
  type = string
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

variable "ssm_association_server_association_id" {
  type = string
}
