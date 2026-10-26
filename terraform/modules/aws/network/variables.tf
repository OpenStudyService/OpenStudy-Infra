variable "name_prefix" {
  type = string
}

variable "server_availability_zone" {
  type = string
}

variable "web_ingress_cidrs" {
  type = list(string)
}
