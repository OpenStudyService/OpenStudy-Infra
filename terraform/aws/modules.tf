module "network" {
  source                   = "../modules/aws/network"
  name_prefix              = var.name_prefix
  server_availability_zone = local.server_availability_zone
  web_ingress_cidrs        = var.web_ingress_cidrs
}

module "server" {
  source                   = "../modules/aws/server"
  ami                      = nonsensitive(data.aws_ssm_parameter.al2023.value)
  apps_enabled             = local.apps_enabled
  available_zone_names     = data.aws_availability_zones.available.names
  aws_account_id           = var.aws_account_id
  aws_region               = var.aws_region
  duckdns_path             = local.duckdns_path
  enable_duckdns           = var.enable_duckdns
  enable_ecs               = var.enable_ecs
  enable_frontend          = var.enable_frontend
  free_tier_confirmed      = var.free_tier_confirmed
  frontend_api_mode        = var.frontend_api_mode
  frontend_test_login      = local.frontend_test_login
  gateway_image            = var.gateway_image
  instance_type            = var.instance_type
  name_prefix              = var.name_prefix
  root_volume_size_gib     = var.root_volume_size_gib
  security_group_server_id = module.network.security_group_server.id
  server_availability_zone = local.server_availability_zone
  service_image            = var.service_image
  subnet_public_id         = module.network.subnet_public.id
  token_path               = local.token_path
  user_data                = local.user_data
  web_ingress_cidrs        = var.web_ingress_cidrs
  depends_on               = [module.network]
}

module "database" {
  source                             = "../modules/aws/database"
  available_zone_names               = data.aws_availability_zones.available.names
  aws_account_id                     = var.aws_account_id
  aws_region                         = var.aws_region
  database_apply_immediately         = var.database_apply_immediately
  database_availability_zones        = local.database_availability_zones
  database_backup_retention_days     = var.database_backup_retention_days
  database_deletion_protection       = var.database_deletion_protection
  database_engine_version            = var.database_engine_version
  database_final_snapshot_identifier = var.database_final_snapshot_identifier
  database_instance_class            = var.database_instance_class
  database_migrations                = local.database_migrations
  database_migrations_dir            = local.database_migrations_dir
  database_name                      = var.database_name
  database_schema_enabled            = local.database_schema_enabled
  database_skip_final_snapshot       = var.database_skip_final_snapshot
  database_source_hash               = local.database_source_hash
  database_sources                   = local.database_sources
  database_storage_gib               = var.database_storage_gib
  enable_database                    = var.enable_database
  iam_role_server_id                 = module.server.iam_role_server.id
  instance_server_id                 = module.server.instance_server.id
  name_prefix                        = var.name_prefix
  root_dir                           = path.module
  security_group_server_id           = module.network.security_group_server.id
  server_availability_zone           = local.server_availability_zone
  server_instance_revision           = module.server.instance_server
  vpc_main_id                        = module.network.vpc_main.id
  depends_on                         = [module.server]
}

module "applications" {
  database_schema_enabled   = local.database_schema_enabled
  source                    = "../modules/aws/applications"
  apps_enabled              = local.apps_enabled
  architecture              = local.architecture
  aws_region                = var.aws_region
  ecs_cluster_apps_id       = try(module.server.ecs_cluster_apps[0].id, null)
  ecs_trust_policy          = local.ecs_trust_policy
  enable_ecs                = var.enable_ecs
  gateway_environment       = var.gateway_environment
  gateway_image             = var.gateway_image
  name_prefix               = var.name_prefix
  service_environment       = var.service_environment
  service_image             = var.service_image
  service_secret_parameters = var.service_secret_parameters
  depends_on                = [module.server, module.database]
}

module "frontend" {
  source                                = "../modules/aws/frontend"
  aws_account_id                        = var.aws_account_id
  aws_region                            = var.aws_region
  enable_frontend                       = var.enable_frontend
  frontend_api_mode                     = var.frontend_api_mode
  frontend_hostname                     = local.frontend_hostname
  frontend_nginx_config                 = local.frontend_nginx_config
  frontend_source_dir                   = local.frontend_source_dir
  frontend_source_hash                  = local.frontend_source_hash
  iam_role_server_id                    = module.server.iam_role_server.id
  instance_server_id                    = module.server.instance_server.id
  name_prefix                           = var.name_prefix
  root_dir                              = path.module
  ssm_association_server_association_id = module.server.ssm_association_server.association_id
  depends_on                            = [module.server]
}

module "schedule" {
  archive_output_path             = var.enable_operating_schedule ? data.archive_file.operating_schedule[0].output_path : null
  archive_source_hash             = var.enable_operating_schedule ? data.archive_file.operating_schedule[0].output_base64sha256 : null
  source                          = "../modules/aws/schedule"
  aws_account_id                  = var.aws_account_id
  db_instance_database_arn        = try(module.database.db_instance_database[0].arn, null)
  db_instance_database_identifier = try(module.database.db_instance_database[0].identifier, null)
  enable_database                 = var.enable_database
  enable_operating_schedule       = var.enable_operating_schedule
  instance_server_arn             = module.server.instance_server.arn
  instance_server_id              = module.server.instance_server.id
  name_prefix                     = var.name_prefix
  operating_schedules             = local.operating_schedules
  depends_on                      = [module.server, module.database, module.frontend]
}
