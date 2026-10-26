variable "apps_enabled" {
  type = bool
}

variable "architecture" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "ecs_cluster_apps_id" {
  type = string
}

variable "ecs_trust_policy" {
  type = string
}

variable "enable_ecs" {
  type = bool
}

variable "gateway_environment" {
  type = map(string)
}

variable "gateway_image" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "service_environment" {
  type = map(string)
}

variable "service_image" {
  type = string
}

variable "service_secret_parameters" {
  type = map(string)
}

variable "database_schema_enabled" {
  type = bool
}
