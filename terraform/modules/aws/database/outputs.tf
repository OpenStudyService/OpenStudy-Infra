output "subnet_database" {
  value = [for item in aws_subnet.database : {
    availability_zone       = item.availability_zone
    cidr_block              = item.cidr_block
    id                      = item.id
    map_public_ip_on_launch = item.map_public_ip_on_launch
    tags                    = item.tags
    vpc_id                  = item.vpc_id
  }]
}

output "route_table_database" {
  value = [for item in aws_route_table.database : {
    id     = item.id
    route  = item.route
    tags   = item.tags
    vpc_id = item.vpc_id
  }]
}

output "db_subnet_group_database" {
  value = [for item in aws_db_subnet_group.database : {
    id         = item.id
    name       = item.name
    subnet_ids = item.subnet_ids
  }]
}

output "security_group_database" {
  value = [for item in aws_security_group.database : {
    description = item.description
    egress      = item.egress
    id          = item.id
    ingress     = item.ingress
    name_prefix = item.name_prefix
    vpc_id      = item.vpc_id
  }]
}

output "db_parameter_group_database" {
  value = [for item in aws_db_parameter_group.database : {
    family      = item.family
    id          = item.id
    name        = item.name
    name_prefix = item.name_prefix
    parameter   = item.parameter
  }]
}

output "db_instance_database" {
  value = [for item in aws_db_instance.database : {
    address                     = item.address
    allocated_storage           = item.allocated_storage
    allow_major_version_upgrade = item.allow_major_version_upgrade
    apply_immediately           = item.apply_immediately
    arn                         = item.arn
    auto_minor_version_upgrade  = item.auto_minor_version_upgrade
    availability_zone           = item.availability_zone
    backup_retention_period     = item.backup_retention_period
    copy_tags_to_snapshot       = item.copy_tags_to_snapshot
    db_name                     = item.db_name
    db_subnet_group_name        = item.db_subnet_group_name
    delete_automated_backups    = item.delete_automated_backups
    deletion_protection         = item.deletion_protection
    endpoint                    = item.endpoint
    engine                      = item.engine
    engine_version              = item.engine_version
    final_snapshot_identifier   = item.final_snapshot_identifier
    id                          = item.id
    identifier                  = item.identifier
    instance_class              = item.instance_class
    manage_master_user_password = item.manage_master_user_password
    master_user_secret          = item.master_user_secret
    multi_az                    = item.multi_az
    parameter_group_name        = item.parameter_group_name
    port                        = item.port
    publicly_accessible         = item.publicly_accessible
    skip_final_snapshot         = item.skip_final_snapshot
    storage_encrypted           = item.storage_encrypted
    storage_type                = item.storage_type
    username                    = item.username
    vpc_security_group_ids      = item.vpc_security_group_ids
  }]
}

output "s3_bucket_database_migrations" {
  value = [for item in aws_s3_bucket.database_migrations : {
    arn           = item.arn
    bucket        = item.bucket
    force_destroy = item.force_destroy
    id            = item.id
  }]
}

output "s3_bucket_public_access_block_database_migrations" {
  value = [for item in aws_s3_bucket_public_access_block.database_migrations : {
    block_public_acls       = item.block_public_acls
    block_public_policy     = item.block_public_policy
    bucket                  = item.bucket
    id                      = item.id
    ignore_public_acls      = item.ignore_public_acls
    restrict_public_buckets = item.restrict_public_buckets
  }]
}

output "s3_object_database_migrations" {
  value = { for key, item in aws_s3_object.database_migrations : key => {
    bucket                 = item.bucket
    id                     = item.id
    key                    = item.key
    server_side_encryption = item.server_side_encryption
    source                 = item.source
    source_hash            = item.source_hash
  } }
}

output "iam_role_policy_database_migrations" {
  value = [for item in aws_iam_role_policy.database_migrations : {
    id     = item.id
    name   = item.name
    policy = item.policy
    role   = item.role
  }]
}

output "ssm_document_database_migrations" {
  value = [for item in aws_ssm_document.database_migrations : {
    content         = item.content
    document_format = item.document_format
    document_type   = item.document_type
    id              = item.id
    latest_version  = item.latest_version
    name            = item.name
  }]
}

output "ssm_association_database_migrations" {
  value = [for item in aws_ssm_association.database_migrations : {
    association_id                   = item.association_id
    association_name                 = item.association_name
    document_version                 = item.document_version
    id                               = item.id
    name                             = item.name
    targets                          = item.targets
    wait_for_success_timeout_seconds = item.wait_for_success_timeout_seconds
  }]
}
