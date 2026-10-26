resource "terraform_data" "server_instance" {
  count = var.database_schema_enabled ? 1 : 0
  input = var.server_instance_revision
}

resource "aws_subnet" "database" {
  count                   = var.enable_database ? 2 : 0
  vpc_id                  = var.vpc_main_id
  cidr_block              = "10.42.${20 + count.index}.0/24"
  availability_zone       = try(var.database_availability_zones[count.index], null)
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-database-${count.index + 1}" }

  lifecycle {
    precondition {
      condition     = length(var.available_zone_names) >= 2
      error_message = "RDS requires two available Availability Zones."
    }
  }
}

resource "aws_route_table" "database" {
  count  = var.enable_database ? 1 : 0
  vpc_id = var.vpc_main_id
  tags   = { Name = "${var.name_prefix}-database-private" }
}

resource "aws_route_table_association" "database" {
  count          = var.enable_database ? 2 : 0
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database[0].id
}

resource "aws_db_subnet_group" "database" {
  count      = var.enable_database ? 1 : 0
  name       = "${var.name_prefix}-mysql"
  subnet_ids = aws_subnet.database[*].id
}

resource "aws_security_group" "database" {
  count       = var.enable_database ? 1 : 0
  name_prefix = "${var.name_prefix}-mysql-"
  description = "MySQL from the OpenStudy server only."
  vpc_id      = var.vpc_main_id

  ingress {
    description     = "MySQL from the server security group."
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.security_group_server_id]
  }

  egress = []
}

resource "aws_db_parameter_group" "database" {
  count       = var.enable_database ? 1 : 0
  name_prefix = "${var.name_prefix}-mysql84-"
  family      = "mysql8.4"

  parameter {
    name  = "require_secure_transport"
    value = "1"
  }
  parameter {
    name  = "time_zone"
    value = "UTC"
  }
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
  parameter {
    name  = "collation_server"
    value = "utf8mb4_0900_ai_ci"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "database" {
  count                       = var.enable_database ? 1 : 0
  identifier                  = "${var.name_prefix}-mysql"
  engine                      = "mysql"
  engine_version              = var.database_engine_version
  instance_class              = var.database_instance_class
  allocated_storage           = var.database_storage_gib
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.database_name
  username                    = "openstudy_admin"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.database[0].name
  vpc_security_group_ids      = [aws_security_group.database[0].id]
  parameter_group_name        = aws_db_parameter_group.database[0].name
  publicly_accessible         = false
  multi_az                    = false
  availability_zone           = var.server_availability_zone
  port                        = 3306
  backup_retention_period     = var.database_backup_retention_days
  apply_immediately           = var.database_apply_immediately
  delete_automated_backups    = true
  auto_minor_version_upgrade  = false
  allow_major_version_upgrade = false
  copy_tags_to_snapshot       = true
  deletion_protection         = var.database_deletion_protection
  skip_final_snapshot         = var.database_skip_final_snapshot
  final_snapshot_identifier   = var.database_skip_final_snapshot ? null : coalesce(var.database_final_snapshot_identifier, "${var.name_prefix}-mysql-final")

  lifecycle {
    precondition {
      condition     = !strcontains(var.name_prefix, "--") && !endswith(var.name_prefix, "-")
      error_message = "The RDS identifier requires a name_prefix without consecutive or trailing hyphens."
    }
  }

  depends_on = [aws_route_table_association.database]
}

resource "aws_s3_bucket" "database_migrations" {
  count         = var.database_schema_enabled ? 1 : 0
  bucket        = "${var.name_prefix}-db-${var.aws_account_id}-${var.aws_region}"
  force_destroy = true

  lifecycle {
    precondition {
      condition     = length("${var.name_prefix}-db-${var.aws_account_id}-${var.aws_region}") <= 63
      error_message = "Use a shorter name_prefix so the database artifact bucket name is at most 63 characters."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "database_migrations" {
  count                   = var.database_schema_enabled ? 1 : 0
  bucket                  = aws_s3_bucket.database_migrations[0].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "database_migrations" {
  count  = var.database_schema_enabled ? 1 : 0
  bucket = aws_s3_bucket.database_migrations[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "database_migrations" {
  count  = var.database_schema_enabled ? 1 : 0
  bucket = aws_s3_bucket.database_migrations[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.database_migrations[0].arn, "${aws_s3_bucket.database_migrations[0].arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_s3_object" "database_migrations" {
  for_each               = var.database_schema_enabled ? var.database_sources : {}
  bucket                 = aws_s3_bucket.database_migrations[0].id
  key                    = "schema/${var.database_source_hash}/${each.key}"
  source                 = each.value
  source_hash            = filesha256(each.value)
  server_side_encryption = "AES256"
}

resource "aws_iam_role_policy" "database_migrations" {
  count = var.database_schema_enabled ? 1 : 0
  name  = "database-migrations"
  role  = var.iam_role_server_id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_db_instance.database[0].master_user_secret[0].secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.database_migrations[0].arn}/schema/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetDocument", "ssm:DescribeDocument"]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:document/${var.name_prefix}-migrate-database"
      },
    ]
  })
}

resource "aws_ssm_document" "database_migrations" {
  count           = var.database_schema_enabled ? 1 : 0
  name            = "${var.name_prefix}-migrate-database"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Validate and migrate the OpenStudy MySQL schema without reading credentials into Terraform."
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "migrateDatabase"
      inputs = {
        timeoutSeconds = "1800"
        runCommand = [templatefile("${var.root_dir}/templates/migrate-database.sh.tftpl", {
          region        = var.aws_region
          bucket        = aws_s3_bucket.database_migrations[0].id
          source_hash   = var.database_source_hash
          script_hash   = filesha256("${var.root_dir}/../../scripts/migrate-database.py")
          host          = aws_db_instance.database[0].address
          database_name = var.database_name
          secret_arn    = aws_db_instance.database[0].master_user_secret[0].secret_arn
          migrations    = jsonencode({ for source in var.database_migrations : source => filesha256("${var.database_migrations_dir}/${source}") })
        })]
      }
    }]
  })
}

resource "aws_ssm_association" "database_migrations" {
  count                            = var.database_schema_enabled ? 1 : 0
  name                             = aws_ssm_document.database_migrations[0].name
  association_name                 = "${var.name_prefix}-migrate-database"
  document_version                 = aws_ssm_document.database_migrations[0].latest_version
  wait_for_success_timeout_seconds = 1800

  targets {
    key    = "InstanceIds"
    values = [var.instance_server_id]
  }

  lifecycle {
    replace_triggered_by = [aws_ssm_document.database_migrations[0].content, aws_db_instance.database[0], terraform_data.server_instance[0]]
    precondition {
      condition     = length(var.database_migrations) > 0 && alltrue([for source in var.database_migrations : can(regex("^V[0-9]+(_[0-9]+)*__[A-Za-z0-9_]+\\.sql$", source))])
      error_message = "Use SQL filenames such as V1__initial_schema.sql without subdirectories or special characters."
    }
  }

  depends_on = [aws_iam_role_policy.database_migrations, aws_s3_object.database_migrations, aws_s3_bucket_policy.database_migrations, aws_s3_bucket_public_access_block.database_migrations, aws_s3_bucket_server_side_encryption_configuration.database_migrations]
}
