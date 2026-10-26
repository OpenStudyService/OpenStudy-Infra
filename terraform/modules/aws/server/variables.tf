variable "ami" {
  type = string
}

variable "apps_enabled" {
  type = bool
}

variable "available_zone_names" {
  type = list(string)
}

variable "aws_account_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "duckdns_path" {
  type = string
}

variable "enable_duckdns" {
  type = bool
}

variable "enable_ecs" {
  type = bool
}

variable "enable_frontend" {
  type = bool
}

variable "free_tier_confirmed" {
  type = bool
}

variable "frontend_api_mode" {
  type = string
}

variable "frontend_test_login" {
  type = bool
}

variable "gateway_image" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "root_volume_size_gib" {
  type = number
}

variable "security_group_server_id" {
  type = string
}

variable "server_availability_zone" {
  type = string
}

variable "service_image" {
  type = string
}

variable "subnet_public_id" {
  type = string
}

variable "token_path" {
  type = string
}

variable "user_data" {
  type = string
}

variable "web_ingress_cidrs" {
  type = list(string)
}
