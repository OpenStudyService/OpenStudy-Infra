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
  value       = "linux/${local.architecture == "arm64" ? "arm64" : "amd64"}"
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

output "frontend_url" {
  description = "HTTPS static website served directly by the EC2 instance through DuckDNS."
  value       = var.enable_frontend ? "https://${local.frontend_hostname}" : null
}

output "database_endpoint" {
  description = "Private MySQL host:port; reachable from the EC2 server security group."
  value       = var.enable_database ? aws_db_instance.database[0].endpoint : null
}

output "database_name" {
  value = var.enable_database ? var.database_name : null
}

output "database_multi_az" {
  description = "Whether RDS maintains a synchronous standby in a different Availability Zone."
  value       = var.enable_database ? aws_db_instance.database[0].multi_az : null
}

output "database_master_secret_arn" {
  description = "RDS-managed master credential ARN. Terraform never reads the secret value."
  value       = var.enable_database ? aws_db_instance.database[0].master_user_secret[0].secret_arn : null
}

output "database_migration_association_id" {
  description = "SSM association that validates and applies versioned SQL."
  value       = local.database_schema_enabled ? aws_ssm_association.database_migrations[0].association_id : null
}
