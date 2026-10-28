mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-northeast-2a", "ap-northeast-2c"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_resource "aws_ssm_document" {
    defaults = { latest_version = "1" }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      address  = "openstudy-mysql.example.ap-northeast-2.rds.amazonaws.com"
      endpoint = "openstudy-mysql.example.ap-northeast-2.rds.amazonaws.com:3306"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:rds!db-test"
        kms_key_id    = "test-key"
        secret_status = "active"
      }]
    }
  }
}

variables {
  aws_account_id      = "123456789012"
  free_tier_confirmed = true
  enable_frontend     = false
}

run "database_disabled_by_default" {
  command = apply
  assert {
    condition     = length(aws_db_instance.database) == 0 && length(aws_subnet.database) == 0 && length(aws_s3_bucket.database_migrations) == 0 && output.database_endpoint == null && output.database_multi_az == null
    error_message = "Existing deployments must not create a database until explicitly enabled."
  }
}

run "private_database_and_migrations" {
  command = apply
  variables { enable_database = true }

  assert {
    condition     = aws_instance.server.id == run.database_disabled_by_default.instance_id
    error_message = "Enabling RDS must preserve the existing web server."
  }
  assert {
    condition     = length(aws_subnet.database) == 2 && aws_subnet.database[0].availability_zone != aws_subnet.database[1].availability_zone && length(aws_route_table.database[0].route) == 0 && alltrue([for subnet in aws_subnet.database : !subnet.map_public_ip_on_launch])
    error_message = "RDS must use two private subnets in different zones without an internet route."
  }
  assert {
    condition     = length(aws_db_instance.database) == 1 && !aws_db_instance.database[0].multi_az && !output.database_multi_az && aws_db_instance.database[0].availability_zone == "ap-northeast-2a" && aws_db_subnet_group.database[0].subnet_ids == toset(aws_subnet.database[*].id)
    error_message = "Create one Single-AZ primary; the second subnet must not create a standby."
  }
  assert {
    condition     = !aws_db_instance.database[0].publicly_accessible && length(aws_security_group.database[0].ingress) == 1 && alltrue([for rule in aws_security_group.database[0].ingress : rule.from_port == 3306 && rule.to_port == 3306 && rule.security_groups == toset([aws_security_group.server.id]) && (rule.cidr_blocks == null ? true : length(rule.cidr_blocks) == 0)])
    error_message = "Only the EC2 server security group may connect to MySQL."
  }
  assert {
    condition     = aws_db_instance.database[0].engine_version == "8.4.11" && aws_db_instance.database[0].manage_master_user_password && aws_db_instance.database[0].password == null && aws_db_instance.database[0].storage_encrypted && aws_db_instance.database[0].deletion_protection && aws_db_instance.database[0].skip_final_snapshot && aws_db_instance.database[0].backup_retention_period == 0
    error_message = "Use MySQL 8.4, managed credentials, encryption and deletion protection, with backups disabled as requested."
  }
  assert {
    condition     = alltrue([for parameter in aws_db_parameter_group.database[0].parameter : parameter.name == "require_secure_transport" ? parameter.value == "1" : parameter.name == "time_zone" ? parameter.value == "UTC" : true])
    error_message = "Enforce encrypted connections and UTC database sessions."
  }
  assert {
    condition     = length(aws_s3_object.database_migrations) == 2 && aws_s3_bucket_public_access_block.database_migrations[0].block_public_policy && jsondecode(aws_iam_role_policy.database_migrations[0].policy).Statement[0].Resource == output.database_master_secret_arn && strcontains(aws_ssm_document.database_migrations[0].content, local.database_source_hash) && aws_ssm_association.database_migrations[0].wait_for_success_timeout_seconds == 1800
    error_message = "Apply immutable SQL through private S3 and SSM with access only to this database secret."
  }
  assert {
    condition = alltrue([for name in ["V1__init_schema.sql"] :
      contains(keys(aws_s3_object.database_migrations), "migrations/${name}") && strcontains(aws_ssm_document.database_migrations[0].content, name)
    ])
    error_message = "Publish the consolidated Backend V1 and include it in the SSM command."
  }
}

run "database_without_schema_application" {
  command = plan
  variables {
    enable_database           = true
    apply_database_migrations = false
  }
  assert {
    condition     = length(aws_db_instance.database) == 1 && length(aws_ssm_association.database_migrations) == 0 && length(aws_iam_role_policy.database_migrations) == 0 && length(aws_s3_bucket.database_migrations) == 0
    error_message = "Schema application must be independently disableable."
  }
}

run "reject_unsupported_mysql" {
  command = plan
  variables { database_engine_version = "8.0.40" }
  expect_failures = [var.database_engine_version]
}

run "reject_unsafe_database_name" {
  command = plan
  variables { database_name = "openstudy; DROP DATABASE mysql" }
  expect_failures = [var.database_name]
}

run "reject_small_database_storage" {
  command = plan
  variables { database_storage_gib = 8 }
  expect_failures = [var.database_storage_gib]
}

run "disable_backups_by_request" {
  command = plan
  variables {
    enable_database                = true
    apply_database_migrations      = false
    database_backup_retention_days = 0
    database_skip_final_snapshot   = true
    database_apply_immediately     = true
  }
  assert {
    condition     = aws_db_instance.database[0].backup_retention_period == 0 && aws_db_instance.database[0].skip_final_snapshot && aws_db_instance.database[0].final_snapshot_identifier == null && aws_db_instance.database[0].apply_immediately && aws_db_instance.database[0].deletion_protection
    error_message = "Disable automated and final backups as requested, apply immediately and preserve deletion protection."
  }
}

run "reject_negative_backup_retention" {
  command = plan
  variables { database_backup_retention_days = -1 }
  expect_failures = [var.database_backup_retention_days]
}
