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
  service_environment = {
    DB_URL          = "jdbc:mysql://database.example:3306/openstudy?sslMode=VERIFY_IDENTITY"
    TRUSTED_PROXIES = "172.17.0.1/32"
  }
}

run "prepare_without_future_images" {
  command = plan
  assert {
    condition     = length(aws_ecs_cluster.apps) == 1 && length(aws_ecr_repository.apps) == 1 && length(aws_ecs_task_definition.apps) == 0 && length(aws_ecs_service.apps) == 0 && output.application_images_required
    error_message = "Prepare ECS and the Backend repository without deploying placeholder applications."
  }
  assert {
    condition     = output.container_platform == "linux/arm64" && strcontains(local.user_data, "ECS_RESERVED_MEMORY=768") && !strcontains(local.frontend_nginx_config, "proxy_pass")
    error_message = "Reserve host memory and enable routing only after real images are supplied."
  }
}

run "single_backend_on_existing_host" {
  command = plan
  variables {
    enable_frontend     = true
    frontend_source_dir = "../frontend/tests/fixtures/frontend"
    web_ingress_cidrs   = ["0.0.0.0/0"]
    service_image       = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/openstudy-prod/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
  assert {
    condition     = aws_ecs_service.apps[0].desired_count == 1 && aws_ecs_service.apps[0].launch_type == "EC2" && aws_ecs_task_definition.apps[0].network_mode == "bridge" && length(jsondecode(aws_ecs_task_definition.apps[0].container_definitions)) == 1
    error_message = "One EC2 task must run exactly the real Backend."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.apps[0].container_definitions)[0].portMappings[0].containerPort == 8080 && jsondecode(aws_ecs_task_definition.apps[0].container_definitions)[0].portMappings[0].hostPort == 8081 && alltrue([for rule in aws_security_group.server.ingress : contains([80, 443], rule.from_port)]) && strcontains(local.frontend_nginx_config, "proxy_pass http://host.docker.internal:8081")
    error_message = "Publish the Backend to the Nginx host route; public ingress must remain HTTP/HTTPS."
  }
}

run "reject_backend_without_live_frontend" {
  command = plan
  variables {
    service_image = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
  expect_failures = [aws_ecs_cluster.apps]
}

run "infra_owns_schema_initialization" {
  command = plan
  variables {
    enable_database           = true
    apply_database_migrations = true
    service_secret_parameters = { DB_PASSWORD = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/db-password" }
    enable_frontend           = true
    frontend_source_dir       = "../frontend/tests/fixtures/frontend"
    web_ingress_cidrs         = ["0.0.0.0/0"]
    service_image             = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
  assert {
    condition     = contains(jsondecode(aws_ecs_task_definition.apps[0].container_definitions)[0].environment, { name = "SPRING_FLYWAY_ENABLED", value = "false" }) && length(aws_ssm_association.database_migrations) == 1
    error_message = "Run Flyway through Infra only; Service must start with Flyway disabled."
  }
}

run "reject_service_flyway_when_infra_migrates" {
  command = plan
  variables {
    enable_database           = true
    apply_database_migrations = true
    service_secret_parameters = { DB_PASSWORD = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/db-password" }
    enable_frontend           = true
    frontend_source_dir       = "../frontend/tests/fixtures/frontend"
    web_ingress_cidrs         = ["0.0.0.0/0"]
    service_image             = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    service_environment       = { SPRING_FLYWAY_ENABLED = "true", DB_URL = "jdbc:mysql://database.example:3306/openstudy?sslMode=VERIFY_IDENTITY", TRUSTED_PROXIES = "172.17.0.1/32" }
  }
  expect_failures = [aws_ecs_task_definition.apps]
}

run "reject_secret_flyway_override_when_infra_migrates" {
  command = plan
  variables {
    enable_database           = true
    apply_database_migrations = true
    enable_frontend           = true
    frontend_source_dir       = "../frontend/tests/fixtures/frontend"
    web_ingress_cidrs         = ["0.0.0.0/0"]
    service_image             = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    service_secret_parameters = { DB_PASSWORD = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/db-password", SPRING_FLYWAY_ENABLED = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/flyway" }
  }
  expect_failures = [aws_ecs_task_definition.apps]
}

run "eligible_x86_host_in_supported_zone" {
  command = plan
  variables {
    instance_type             = "c7i-flex.large"
    server_availability_zone  = "ap-northeast-2b"
    service_secret_parameters = { DB_PASSWORD = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/db-password" }
    enable_database           = true
    apply_database_migrations = false
    enable_frontend           = true
    frontend_source_dir       = "../frontend/tests/fixtures/frontend"
    web_ingress_cidrs         = ["0.0.0.0/0"]
    service_image             = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
  override_data {
    target = data.aws_availability_zones.available
    values = { names = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c", "ap-northeast-2d"] }
  }
  assert {
    condition     = output.container_platform == "linux/amd64" && aws_ecs_task_definition.apps[0].runtime_platform[0].cpu_architecture == "X86_64" && length(aws_instance.server.credit_specification) == 0
    error_message = "The eligible non-burstable host must use AMD64 images without T-family CPU credits."
  }
  assert {
    condition     = aws_subnet.public.availability_zone == "ap-northeast-2b" && aws_db_instance.database[0].availability_zone == "ap-northeast-2b" && aws_subnet.database[0].availability_zone == "ap-northeast-2b" && aws_subnet.database[1].availability_zone != "ap-northeast-2b"
    error_message = "Keep EC2 and the single RDS primary together in the selected supported AZ, with a second DB subnet in another AZ."
  }
}

run "reject_small_ecs_host" {
  command = plan
  variables { instance_type = "t4g.small" }
  expect_failures = [aws_ecs_cluster.apps]
}

run "weekday_schedule" {
  command = plan
  variables {
    enable_database           = true
    apply_database_migrations = false
    enable_operating_schedule = true
  }
  assert {
    condition     = aws_scheduler_schedule.operating["start"].schedule_expression == "cron(0 11 ? * MON-FRI *)" && aws_scheduler_schedule.operating["start"].schedule_expression_timezone == "Asia/Seoul" && aws_scheduler_schedule.operating["stop"].schedule_expression == "cron(0 18 * * ? *)" && length(aws_scheduler_schedule.operating) == 3 && aws_lambda_function_event_invoke_config.operating_schedule[0].maximum_retry_attempts == 2
    error_message = "Start weekdays at 11 KST and retry the daily 18 KST stop at 18:30."
  }
}

run "reject_database_admin_for_service" {
  command = plan
  variables {
    enable_database           = true
    enable_frontend           = true
    frontend_source_dir       = "../frontend/tests/fixtures/frontend"
    web_ingress_cidrs         = ["0.0.0.0/0"]
    service_image             = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    service_environment       = { DB_USERNAME = "openstudy_admin", DB_URL = "jdbc:mysql://database.example:3306/openstudy?sslMode=VERIFY_IDENTITY", TRUSTED_PROXIES = "172.17.0.1/32" }
    service_secret_parameters = { DB_PASSWORD = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/db-password" }
  }
  expect_failures = [aws_ecs_task_definition.apps]
}

run "reject_plaintext_database_password_for_service" {
  command = plan
  variables {
    enable_database           = true
    enable_frontend           = true
    frontend_source_dir       = "../frontend/tests/fixtures/frontend"
    web_ingress_cidrs         = ["0.0.0.0/0"]
    service_image             = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    service_environment       = { DB_PASSWORD = "not-a-secret", DB_URL = "jdbc:mysql://database.example:3306/openstudy?sslMode=VERIFY_IDENTITY", TRUSTED_PROXIES = "172.17.0.1/32" }
    service_secret_parameters = { DB_PASSWORD = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/db-password" }
  }
  expect_failures = [aws_ecs_task_definition.apps]
}

run "reject_missing_prod_environment" {
  command = plan
  variables {
    enable_frontend     = true
    frontend_source_dir = "../frontend/tests/fixtures/frontend"
    web_ingress_cidrs   = ["0.0.0.0/0"]
    service_image       = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    service_environment = {}
  }
  expect_failures = [aws_ecs_task_definition.apps]
}
