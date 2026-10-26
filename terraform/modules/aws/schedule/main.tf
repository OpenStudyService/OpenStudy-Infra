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
      { Effect = "Allow", Action = ["ec2:StartInstances", "ec2:StopInstances"], Resource = var.instance_server_arn },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.operating_schedule[0].arn}:*" },
      ], !var.enable_database ? [] : [
      { Effect = "Allow", Action = ["rds:DescribeDBInstances", "rds:StartDBInstance", "rds:StopDBInstance"], Resource = var.db_instance_database_arn },
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
  filename         = var.archive_output_path
  source_code_hash = var.archive_source_hash
  timeout          = 60
  memory_size      = 128
  environment {
    variables = {
      INSTANCE_ID         = var.instance_server_id
      DATABASE_IDENTIFIER = var.enable_database ? var.db_instance_database_identifier : ""
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
  for_each                     = var.operating_schedules
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
  depends_on = [aws_iam_role_policy.scheduler, aws_lambda_function_event_invoke_config.operating_schedule]
}
