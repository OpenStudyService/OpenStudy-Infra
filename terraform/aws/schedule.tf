variable "enable_operating_schedule" {
  description = "Start EC2/RDS weekdays at 11:00 KST; stop daily at 18:00 with an 18:30 retry. Start-up takes additional time."
  type        = bool
  default     = false
}

locals {
  operating_schedules = var.enable_operating_schedule ? {
    start      = { expression = "cron(0 11 ? * MON-FRI *)", action = "start" }
    stop       = { expression = "cron(0 18 * * ? *)", action = "stop" }
    stop_retry = { expression = "cron(30 18 * * ? *)", action = "stop" }
  } : {}
}

data "archive_file" "operating_schedule" {
  count       = var.enable_operating_schedule ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/operating_schedule.py"
  output_path = "${path.module}/.terraform/operating-schedule.zip"
}

resource "aws_cloudwatch_log_group" "operating_schedule" {
  count             = var.enable_operating_schedule ? 1 : 0
  name              = "/aws/lambda/${var.name_prefix}-operating-schedule"
  retention_in_days = 7
}

resource "aws_iam_role" "operating_schedule" {
  count = var.enable_operating_schedule ? 1 : 0
  name  = "${var.name_prefix}-operating-schedule"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "operating_schedule" {
  count = var.enable_operating_schedule ? 1 : 0
  name  = "start-stop-budget-resources"
  role  = aws_iam_role.operating_schedule[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      { Effect = "Allow", Action = ["ec2:DescribeInstances"], Resource = "*" },
      { Effect = "Allow", Action = ["ec2:StartInstances", "ec2:StopInstances"], Resource = aws_instance.server.arn },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.operating_schedule[0].arn}:*" },
      ], !var.enable_database ? [] : [
      { Effect = "Allow", Action = ["rds:DescribeDBInstances", "rds:StartDBInstance", "rds:StopDBInstance"], Resource = aws_db_instance.database[0].arn },
    ])
  })
}

resource "aws_lambda_function" "operating_schedule" {
  count            = var.enable_operating_schedule ? 1 : 0
  function_name    = "${var.name_prefix}-operating-schedule"
  role             = aws_iam_role.operating_schedule[0].arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "operating_schedule.handler"
  filename         = data.archive_file.operating_schedule[0].output_path
  source_code_hash = data.archive_file.operating_schedule[0].output_base64sha256
  timeout          = 60
  memory_size      = 128
  environment {
    variables = {
      INSTANCE_ID         = aws_instance.server.id
      DATABASE_IDENTIFIER = var.enable_database ? aws_db_instance.database[0].identifier : ""
    }
  }
  depends_on = [aws_iam_role_policy.operating_schedule]
}

resource "aws_lambda_function_event_invoke_config" "operating_schedule" {
  count                        = var.enable_operating_schedule ? 1 : 0
  function_name                = aws_lambda_function.operating_schedule[0].function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600
}

resource "aws_iam_role" "scheduler" {
  count = var.enable_operating_schedule ? 1 : 0
  name  = "${var.name_prefix}-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Principal = { Service = "scheduler.amazonaws.com" }, Action = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.aws_account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.enable_operating_schedule ? 1 : 0
  name  = "invoke-operating-schedule"
  role  = aws_iam_role.scheduler[0].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = aws_lambda_function.operating_schedule[0].arn }]
  })
}

resource "aws_scheduler_schedule" "operating" {
  for_each                     = local.operating_schedules
  name                         = "${var.name_prefix}-${each.key}"
  schedule_expression          = each.value.expression
  schedule_expression_timezone = "Asia/Seoul"
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = aws_lambda_function.operating_schedule[0].arn
    role_arn = aws_iam_role.scheduler[0].arn
    input    = jsonencode({ action = each.value.action })
    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }
  }
  depends_on = [
    aws_iam_role_policy.scheduler,
    aws_lambda_function_event_invoke_config.operating_schedule,
    aws_ssm_association.server,
    aws_ssm_association.database_migrations,
    terraform_data.frontend_deployment,
  ]
}

output "operating_schedule" {
  value = var.enable_operating_schedule ? {
    timezone = "Asia/Seoul", start = "Mon-Fri 11:00", stop = "Daily 18:00", stop_retry = "Daily 18:30"
  } : null
}
