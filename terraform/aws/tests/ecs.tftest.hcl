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
}

variables {
  enable_frontend           = false
  frontend_api_mode         = "live"
  enable_database           = false
  enable_operating_schedule = false
  aws_account_id            = "123456789012"
  free_tier_confirmed       = true
  instance_type             = "t4g.medium"
  root_volume_size_gib      = 30
  enable_ecs                = true
}

run "prepare_without_future_images" {
  command = plan
  assert {
    condition     = length(module.server.ecs_cluster_apps) == 1 && length(module.applications.ecr_repository_apps) == 2 && length(module.applications.ecs_task_definition_apps) == 0 && length(module.applications.ecs_service_apps) == 0 && output.application_images_required
    error_message = "Prepare ECS and two repositories without deploying placeholder applications."
  }
  assert {
    condition     = output.container_platform == "linux/arm64" && strcontains(local.user_data, "ECS_RESERVED_MEMORY=768") && !strcontains(local.frontend_nginx_config, "proxy_pass")
    error_message = "Reserve host memory and enable routing only after real images are supplied."
  }
}

run "two_containers_on_one_host" {
  command = plan
  variables {
    enable_frontend     = true
    frontend_source_dir = "../frontend/tests/fixtures/frontend"
    web_ingress_cidrs   = ["0.0.0.0/0"]
    gateway_image       = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/openstudy-prod/gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    service_image       = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/openstudy-prod/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
  assert {
    condition     = module.applications.ecs_service_apps[0].desired_count == 1 && module.applications.ecs_service_apps[0].launch_type == "EC2" && module.applications.ecs_task_definition_apps[0].network_mode == "bridge" && length(jsondecode(module.applications.ecs_task_definition_apps[0].container_definitions)) == 2
    error_message = "One EC2 task must contain exactly Gateway and modular Service."
  }
  assert {
    condition     = try(length(jsondecode(module.applications.ecs_task_definition_apps[0].container_definitions)[0].portMappings), 0) == 0 && jsondecode(module.applications.ecs_task_definition_apps[0].container_definitions)[1].portMappings[0].hostPort == 8081 && alltrue([for rule in module.network.security_group_server.ingress : contains([80, 443], rule.from_port)]) && strcontains(local.frontend_nginx_config, "proxy_pass http://host.docker.internal:8081")
    error_message = "Publish only the Gateway internally; public ingress must remain HTTP/HTTPS."
  }
}

run "infra_owns_schema_initialization" {
  command = plan
  variables {
    enable_database           = true
    apply_database_migrations = true
    enable_frontend           = true
    frontend_source_dir       = "../frontend/tests/fixtures/frontend"
    web_ingress_cidrs         = ["0.0.0.0/0"]
    gateway_image             = "example.com/gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    service_image             = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
  assert {
    condition     = contains(jsondecode(module.applications.ecs_task_definition_apps[0].container_definitions)[0].environment, { name = "SPRING_FLYWAY_ENABLED", value = "false" }) && length(module.database.ssm_association_database_migrations) == 1
    error_message = "Run Flyway through Infra only; Service must start with Flyway disabled."
  }
}

run "eligible_x86_host_in_supported_zone" {
  command = plan
  variables {
    instance_type             = "c7i-flex.large"
    server_availability_zone  = "ap-northeast-2b"
    enable_database           = true
    apply_database_migrations = false
    enable_frontend           = true
    frontend_source_dir       = "../frontend/tests/fixtures/frontend"
    web_ingress_cidrs         = ["0.0.0.0/0"]
    gateway_image             = "example.com/gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    service_image             = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
  override_data {
    target = data.aws_availability_zones.available
    values = { names = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c", "ap-northeast-2d"] }
  }
  assert {
    condition     = output.container_platform == "linux/amd64" && module.applications.ecs_task_definition_apps[0].runtime_platform[0].cpu_architecture == "X86_64" && length(module.server.instance_server.credit_specification) == 0
    error_message = "The eligible non-burstable host must use AMD64 images without T-family CPU credits."
  }
  assert {
    condition     = module.network.subnet_public.availability_zone == "ap-northeast-2b" && module.database.db_instance_database[0].availability_zone == "ap-northeast-2b" && module.database.subnet_database[0].availability_zone == "ap-northeast-2b" && module.database.subnet_database[1].availability_zone != "ap-northeast-2b"
    error_message = "Keep EC2 and the single RDS primary together in the selected supported AZ, with a second DB subnet in another AZ."
  }
}

run "weekday_schedule" {
  command = plan
  variables {
    enable_database           = true
    apply_database_migrations = false
    enable_operating_schedule = true
  }
  assert {
    condition     = module.schedule.scheduler_schedule_operating["start"].schedule_expression == "cron(0 11 ? * MON-FRI *)" && module.schedule.scheduler_schedule_operating["start"].schedule_expression_timezone == "Asia/Seoul" && module.schedule.scheduler_schedule_operating["stop"].schedule_expression == "cron(0 18 * * ? *)" && length(module.schedule.scheduler_schedule_operating) == 3 && module.schedule.lambda_function_event_invoke_config_operating_schedule[0].maximum_retry_attempts == 2
    error_message = "Start weekdays at 11 KST and retry the daily 18 KST stop at 18:30."
  }
}
