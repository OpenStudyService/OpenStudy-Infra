resource "aws_ecr_repository" "apps" {
  for_each             = var.enable_ecs ? toset(["gateway", "service"]) : toset([])
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
  assume_role_policy = var.ecs_trust_policy
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
  assume_role_policy = var.ecs_trust_policy
}

resource "aws_ecs_task_definition" "apps" {
  count                    = var.apps_enabled ? 1 : 0
  family                   = "${var.name_prefix}-apps"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = "1024"
  memory                   = "2560"
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.architecture == "arm64" ? "ARM64" : "X86_64"
  }
  lifecycle {
    precondition {
      condition = !var.database_schema_enabled || (
        lower(lookup(var.service_environment, "SPRING_FLYWAY_ENABLED", "false")) == "false" &&
        !contains(keys(var.service_secret_parameters), "SPRING_FLYWAY_ENABLED")
      )
      error_message = "Infra owns database migrations while apply_database_migrations is enabled. Keep Service Flyway disabled and do not inject SPRING_FLYWAY_ENABLED as a secret."
    }
  }
  container_definitions = jsonencode([
    {
      name = "service", image = var.service_image, essential = true, cpu = 768, memory = 2048
      environment = [for key, value in merge({
        SERVER_PORT = "8080", SPRING_FLYWAY_ENABLED = "false"
      }, var.service_environment) : { name = key, value = value }]
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
    {
      name         = "gateway", image = var.gateway_image, essential = true, cpu = 256, memory = 512
      links        = ["service:service"]
      dependsOn    = [{ containerName = "service", condition = "HEALTHY" }]
      portMappings = [{ containerPort = 8080, hostPort = 8081, protocol = "tcp" }]
      environment = [for key, value in merge({
        SERVER_PORT = "8080", SERVICE_URL = "http://service:8080"
      }, var.gateway_environment) : { name = key, value = value }]
      healthCheck = {
        command  = ["CMD-SHELL", "curl -fsS http://localhost:8080/actuator/health >/dev/null || exit 1"]
        interval = 30, timeout = 5, retries = 3, startPeriod = 60
      }
      logConfiguration = {
        logDriver = "awslogs"
        options   = { awslogs-group = aws_cloudwatch_log_group.apps[0].name, awslogs-region = var.aws_region, awslogs-stream-prefix = "gateway" }
      }
    },
  ])
}

resource "aws_ecs_service" "apps" {
  count                              = var.apps_enabled ? 1 : 0
  name                               = "${var.name_prefix}-apps"
  cluster                            = var.ecs_cluster_apps_id
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
  depends_on = [aws_iam_role_policy.ecs_execution]
}
