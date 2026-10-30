variable "enable_ecs" {
  description = "Prepare ECS on the existing EC2 host. No application runs until the Backend image digest is supplied."
  type        = bool
  default     = false
}

variable "service_image" {
  description = "Backend image matching container_platform, pinned by immutable digest."
  type        = string
  default     = null
  validation {
    condition     = var.service_image == null ? true : can(regex("^[a-zA-Z0-9./:_-]+@sha256:[a-f0-9]{64}$", var.service_image))
    error_message = "Supply an immutable image digest, or null until the image exists."
  }
}

variable "service_environment" {
  description = "Non-secret Service environment. Infra owns migrations unless explicitly handed over."
  type        = map(string)
  default     = {}
}

variable "service_secret_parameters" {
  description = "Service environment name => existing SSM SecureString ARN using the default SSM KMS key. Never supply secret values."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([for arn in values(var.service_secret_parameters) :
      startswith(arn, "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.name_prefix}/apps/")
    ])
    error_message = "Use this account's SSM parameter ARNs under /<name_prefix>/apps/."
  }
}

locals {
  apps_enabled = var.enable_ecs && var.service_image != null
  ecs_trust_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_ecs_cluster" "apps" {
  count = var.enable_ecs ? 1 : 0
  name  = "${var.name_prefix}-apps"
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
  lifecycle {
    precondition {
      condition     = contains(["t4g.medium", "c7i-flex.large"], var.instance_type) && var.root_volume_size_gib >= 30
      error_message = "The ECS profile requires a supported 4 GiB host and at least 30 GiB root storage."
    }
    precondition {
      condition     = !local.apps_enabled || (var.enable_frontend && var.frontend_api_mode == "live")
      error_message = "Application routing requires enable_frontend=true and frontend_api_mode=live."
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_host" {
  count      = var.enable_ecs ? 1 : 0
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_ecr_repository" "apps" {
  for_each             = var.enable_ecs ? toset(["service"]) : toset([])
  name                 = "${var.name_prefix}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "apps" {
  for_each   = aws_ecr_repository.apps
  repository = each.value.name
  policy = jsonencode({ rules = [{
    rulePriority = 1
    description  = "Remove untagged build leftovers after seven days; preserve tagged releases."
    selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }
    action       = { type = "expire" }
  }] })
}

resource "aws_cloudwatch_log_group" "apps" {
  count             = var.enable_ecs ? 1 : 0
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_execution" {
  count              = var.enable_ecs ? 1 : 0
  name               = "${var.name_prefix}-ecs-execution"
  assume_role_policy = local.ecs_trust_policy
}

resource "aws_iam_role_policy" "ecs_execution" {
  count = var.enable_ecs ? 1 : 0
  name  = "pull-images-and-write-logs"
  role  = aws_iam_role.ecs_execution[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"], Resource = [for repo in aws_ecr_repository.apps : repo.arn] },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.apps[0].arn}:*" },
      ], length(var.service_secret_parameters) == 0 ? [] : [
      { Effect = "Allow", Action = ["ssm:GetParameters"], Resource = values(var.service_secret_parameters) },
    ])
  })
}

resource "aws_iam_role" "ecs_task" {
  count              = var.enable_ecs ? 1 : 0
  name               = "${var.name_prefix}-ecs-task"
  assume_role_policy = local.ecs_trust_policy
}

resource "aws_ecs_task_definition" "apps" {
  count                    = local.apps_enabled ? 1 : 0
  family                   = "${var.name_prefix}-apps"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = local.architecture == "arm64" ? "ARM64" : "X86_64"
  }
  lifecycle {
    precondition {
      condition = alltrue([for key in ["DB_URL", "TRUSTED_PROXIES"] :
        trimspace(lookup(var.service_environment, key, "")) != ""
      ])
      error_message = "Set DB_URL and the measured TRUSTED_PROXIES for the prod Backend."
    }
    precondition {
      condition = !var.enable_database || (
        lookup(var.service_environment, "DB_USERNAME", "openstudy_app") == "openstudy_app" &&
        !contains(keys(var.service_environment), "DB_PASSWORD") &&
        !contains(keys(var.service_secret_parameters), "DB_USERNAME") &&
        contains(keys(var.service_secret_parameters), "DB_PASSWORD")
      )
      error_message = "Use the openstudy_app database account and inject DB_PASSWORD from an app SecureString."
    }
    precondition {
      condition = !local.database_schema_enabled || (
        lower(lookup(var.service_environment, "SPRING_FLYWAY_ENABLED", "false")) == "false" &&
        !contains(keys(var.service_secret_parameters), "SPRING_FLYWAY_ENABLED")
      )
      error_message = "Infra owns database migrations while apply_database_migrations is enabled. Keep Service Flyway disabled and do not inject SPRING_FLYWAY_ENABLED as a secret."
    }
  }
  container_definitions = jsonencode([
    {
      name         = "service", image = var.service_image, essential = true, cpu = 1024, memory = 2048
      portMappings = [{ containerPort = 8080, hostPort = 8081, protocol = "tcp" }]
      environment = [for key, value in merge({
        SERVER_PORT = "8080", SPRING_PROFILES_ACTIVE = "prod", SPRING_FLYWAY_ENABLED = "false"
      }, var.enable_database ? { DB_USERNAME = "openstudy_app" } : {}, var.service_environment) : { name = key, value = value }]
      secrets = [for key, arn in var.service_secret_parameters : { name = key, valueFrom = arn }]
      healthCheck = {
        command  = ["CMD-SHELL", "curl -fsS http://localhost:8080/actuator/health >/dev/null || exit 1"]
        interval = 30, timeout = 5, retries = 3, startPeriod = 120
      }
      logConfiguration = {
        logDriver = "awslogs"
        options   = { awslogs-group = aws_cloudwatch_log_group.apps[0].name, awslogs-region = var.aws_region, awslogs-stream-prefix = "service" }
      }
    },
  ])
}

resource "aws_ecs_service" "apps" {
  count                              = local.apps_enabled ? 1 : 0
  name                               = "${var.name_prefix}-apps"
  cluster                            = aws_ecs_cluster.apps[0].id
  task_definition                    = aws_ecs_task_definition.apps[0].arn
  desired_count                      = 1
  launch_type                        = "EC2"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  wait_for_steady_state              = true
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  depends_on = [aws_ssm_association.server, aws_iam_role_policy.ecs_execution, aws_db_instance.database, aws_ssm_association.database_migrations]
}

output "ecs_cluster_name" {
  value = var.enable_ecs ? aws_ecs_cluster.apps[0].name : null
}

output "application_images_required" {
  value = var.enable_ecs && !local.apps_enabled
}

output "ecr_repositories" {
  value = { for name, repo in aws_ecr_repository.apps : name => repo.repository_url }
}
