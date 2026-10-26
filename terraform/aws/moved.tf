# Keep these mappings so existing state keeps its resource identities.

moved {
  from = aws_ecs_cluster.apps
  to   = module.server.aws_ecs_cluster.apps
}

moved {
  from = aws_iam_role_policy_attachment.ecs_host
  to   = module.server.aws_iam_role_policy_attachment.ecs_host
}

moved {
  from = aws_ecr_repository.apps
  to   = module.applications.aws_ecr_repository.apps
}

moved {
  from = aws_ecr_lifecycle_policy.apps
  to   = module.applications.aws_ecr_lifecycle_policy.apps
}

moved {
  from = aws_cloudwatch_log_group.apps
  to   = module.applications.aws_cloudwatch_log_group.apps
}

moved {
  from = aws_iam_role.ecs_execution
  to   = module.applications.aws_iam_role.ecs_execution
}

moved {
  from = aws_iam_role_policy.ecs_execution
  to   = module.applications.aws_iam_role_policy.ecs_execution
}

moved {
  from = aws_iam_role.ecs_task
  to   = module.applications.aws_iam_role.ecs_task
}

moved {
  from = aws_ecs_task_definition.apps
  to   = module.applications.aws_ecs_task_definition.apps
}

moved {
  from = aws_ecs_service.apps
  to   = module.applications.aws_ecs_service.apps
}

moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.main
}

moved {
  from = aws_subnet.public
  to   = module.network.aws_subnet.public
}

moved {
  from = aws_internet_gateway.main
  to   = module.network.aws_internet_gateway.main
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route_table_association.public
  to   = module.network.aws_route_table_association.public
}

moved {
  from = aws_security_group.server
  to   = module.network.aws_security_group.server
}

moved {
  from = aws_iam_role.server
  to   = module.server.aws_iam_role.server
}

moved {
  from = aws_iam_role_policy.session_manager
  to   = module.server.aws_iam_role_policy.session_manager
}

moved {
  from = aws_iam_role_policy.tunnel_token
  to   = module.server.aws_iam_role_policy.tunnel_token
}

moved {
  from = aws_iam_instance_profile.server
  to   = module.server.aws_iam_instance_profile.server
}

moved {
  from = aws_iam_role_policy.duckdns
  to   = module.server.aws_iam_role_policy.duckdns
}

moved {
  from = aws_instance.server
  to   = module.server.aws_instance.server
}

moved {
  from = aws_cloudwatch_log_group.operating_schedule
  to   = module.schedule.aws_cloudwatch_log_group.operating_schedule
}

moved {
  from = aws_iam_role.operating_schedule
  to   = module.schedule.aws_iam_role.operating_schedule
}

moved {
  from = aws_iam_role_policy.operating_schedule
  to   = module.schedule.aws_iam_role_policy.operating_schedule
}

moved {
  from = aws_lambda_function.operating_schedule
  to   = module.schedule.aws_lambda_function.operating_schedule
}

moved {
  from = aws_lambda_function_event_invoke_config.operating_schedule
  to   = module.schedule.aws_lambda_function_event_invoke_config.operating_schedule
}

moved {
  from = aws_iam_role.scheduler
  to   = module.schedule.aws_iam_role.scheduler
}

moved {
  from = aws_iam_role_policy.scheduler
  to   = module.schedule.aws_iam_role_policy.scheduler
}

moved {
  from = aws_scheduler_schedule.operating
  to   = module.schedule.aws_scheduler_schedule.operating
}

moved {
  from = aws_s3_bucket.frontend_artifacts
  to   = module.frontend.aws_s3_bucket.frontend_artifacts
}

moved {
  from = aws_s3_bucket_public_access_block.frontend_artifacts
  to   = module.frontend.aws_s3_bucket_public_access_block.frontend_artifacts
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.frontend_artifacts
  to   = module.frontend.aws_s3_bucket_server_side_encryption_configuration.frontend_artifacts
}

moved {
  from = aws_s3_bucket_policy.frontend_artifacts
  to   = module.frontend.aws_s3_bucket_policy.frontend_artifacts
}

moved {
  from = aws_iam_role_policy.frontend_artifacts
  to   = module.frontend.aws_iam_role_policy.frontend_artifacts
}

moved {
  from = aws_iam_role_policy.frontend_test_login
  to   = module.server.aws_iam_role_policy.frontend_test_login
}

moved {
  from = terraform_data.frontend_deployment
  to   = module.frontend.terraform_data.frontend_deployment
}

moved {
  from = aws_subnet.database
  to   = module.database.aws_subnet.database
}

moved {
  from = aws_route_table.database
  to   = module.database.aws_route_table.database
}

moved {
  from = aws_route_table_association.database
  to   = module.database.aws_route_table_association.database
}

moved {
  from = aws_db_subnet_group.database
  to   = module.database.aws_db_subnet_group.database
}

moved {
  from = aws_security_group.database
  to   = module.database.aws_security_group.database
}

moved {
  from = aws_db_parameter_group.database
  to   = module.database.aws_db_parameter_group.database
}

moved {
  from = aws_db_instance.database
  to   = module.database.aws_db_instance.database
}

moved {
  from = aws_s3_bucket.database_migrations
  to   = module.database.aws_s3_bucket.database_migrations
}

moved {
  from = aws_s3_bucket_public_access_block.database_migrations
  to   = module.database.aws_s3_bucket_public_access_block.database_migrations
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.database_migrations
  to   = module.database.aws_s3_bucket_server_side_encryption_configuration.database_migrations
}

moved {
  from = aws_s3_bucket_policy.database_migrations
  to   = module.database.aws_s3_bucket_policy.database_migrations
}

moved {
  from = aws_s3_object.database_migrations
  to   = module.database.aws_s3_object.database_migrations
}

moved {
  from = aws_iam_role_policy.database_migrations
  to   = module.database.aws_iam_role_policy.database_migrations
}

moved {
  from = aws_ssm_document.database_migrations
  to   = module.database.aws_ssm_document.database_migrations
}

moved {
  from = aws_ssm_association.database_migrations
  to   = module.database.aws_ssm_association.database_migrations
}

moved {
  from = aws_ssm_document.server
  to   = module.server.aws_ssm_document.server
}

moved {
  from = aws_iam_role_policy.server_configuration
  to   = module.server.aws_iam_role_policy.server_configuration
}

moved {
  from = aws_ssm_association.server
  to   = module.server.aws_ssm_association.server
}
