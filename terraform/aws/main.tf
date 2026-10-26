locals {
  apps_enabled = var.enable_ecs && var.gateway_image != null && var.service_image != null
  ecs_trust_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

locals {
  architecture             = startswith(var.instance_type, "t4g.") ? "arm64" : "x86_64"
  rpm_arch                 = startswith(var.instance_type, "t4g.") ? "aarch64" : "x86_64"
  token_path               = "/${var.name_prefix}/cloudflared/token"
  duckdns_path             = "/${var.name_prefix}/duckdns/token"
  server_availability_zone = coalesce(var.server_availability_zone, data.aws_availability_zones.available.names[0])
  database_availability_zones = concat([local.server_availability_zone], [
    for zone in data.aws_availability_zones.available.names : zone if zone != local.server_availability_zone
  ])

  user_data = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    aws_region            = var.aws_region
    swap_size_mib         = var.swap_size_mib
    cloudflared_version   = var.cloudflared_version
    rpm_arch              = local.rpm_arch
    token_path            = local.token_path
    enable_duckdns        = var.enable_duckdns
    duckdns_subdomain     = var.duckdns_subdomain
    duckdns_path          = local.duckdns_path
    duckdns_update_script = file("${path.module}/../../scripts/duckdns-update.py")
    enable_frontend       = var.enable_frontend
    frontend_nginx_image  = var.frontend_nginx_image
    frontend_nginx_config = local.frontend_nginx_config
    test_login_script     = file("${path.module}/templates/test-login.js")
    enable_test_login     = local.frontend_test_login
    test_login_path       = "/${var.name_prefix}/frontend/test-login"
    enable_ecs            = var.enable_ecs
    ecs_cluster_name      = "${var.name_prefix}-apps"
  })
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${local.architecture}"
}

locals {
  operating_schedules = var.enable_operating_schedule ? {
    start      = { expression = "cron(0 11 ? * MON-FRI *)", action = "start" }
    stop       = { expression = "cron(0 18 * * ? *)", action = "stop" }
    stop_retry = { expression = "cron(30 18 * * ? *)", action = "stop" }
  } : {}
}

locals {
  frontend_hostname   = "${var.duckdns_subdomain}.duckdns.org"
  frontend_test_login = var.enable_frontend && var.frontend_api_mode == "mock"
  frontend_cors_allowed_origins = sort(tolist(setunion(
    toset(["https://${local.frontend_hostname}"]), var.frontend_cors_allowed_origins,
  )))
  frontend_nginx_config = templatefile("${path.module}/templates/nginx.conf.tftpl", {
    hostname             = local.frontend_hostname
    test_login_enabled   = local.frontend_test_login
    backend_enabled      = local.apps_enabled
    cors_allowed_origins = local.frontend_cors_allowed_origins
  })
  frontend_source_dir = abspath(var.frontend_source_dir != null ? var.frontend_source_dir : "${path.module}/../../../OpenStudy-Frontend")
  frontend_sources = var.enable_frontend ? setunion(
    fileset(local.frontend_source_dir, "{src,public}/**"),
    fileset(local.frontend_source_dir, "{package.json,package-lock.json,index.html,tsconfig*.json,vite.config.*,eslint.config.*,.npmrc,.env,.env.local,.env.live,.env.live.local,.env.mock,.env.mock.local}"),
  ) : toset([])
  frontend_source_hash = sha256(jsonencode({
    for source in local.frontend_sources : source => filesha256("${local.frontend_source_dir}/${source}")
  }))
}

locals {
  database_migrations_dir = abspath("${path.module}/../../database/migrations")
  database_migrations     = fileset(local.database_migrations_dir, "V*__*.sql")
  database_sources = merge(
    { for source in local.database_migrations : "migrations/${source}" => "${local.database_migrations_dir}/${source}" },
    { "migrate-database.py" = abspath("${path.module}/../../scripts/migrate-database.py") },
  )
  database_source_hash = sha256(jsonencode({
    for name, source in local.database_sources : name => filesha256(source)
  }))
  database_schema_enabled = var.enable_database && var.apply_database_migrations
}

data "archive_file" "operating_schedule" {
  count       = var.enable_operating_schedule ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/operating_schedule.py"
  output_path = "${path.module}/.terraform/operating-schedule.zip"
}
