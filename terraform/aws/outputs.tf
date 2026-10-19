output "instance_id" {
  description = "EC2 instance ID for Session Manager."
  value       = aws_instance.server.id
}

output "aws_account_id" {
  value = var.aws_account_id
}

output "aws_region" {
  value = var.aws_region
}

output "tunnel_token_parameter_name" {
  description = "Store the token here with scripts/configure-tunnel.py; the token is not managed by Terraform."
  value       = local.token_path
}

output "container_platform" {
  description = "Required platform for application images."
  value       = var.instance_type == "t4g.small" ? "linux/arm64" : "linux/amd64"
}

output "public_ipv4" {
  description = "Current EC2 public IPv4 observed by Terraform. Runtime DDNS reads IMDSv2 after every start."
  value       = aws_instance.server.public_ip
}

output "duckdns_token_parameter_name" {
  description = "Store the DuckDNS account token as a SecureString here; the token is not managed by Terraform."
  value       = var.enable_duckdns ? local.duckdns_path : null
}

output "duckdns_hostname" {
  value = var.enable_duckdns ? "${var.duckdns_subdomain}.duckdns.org" : null
}

output "server_configuration_association_id" {
  description = "State Manager association that applies the Terraform server configuration."
  value       = aws_ssm_association.server.association_id
}
