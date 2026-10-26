output "lambda_function_event_invoke_config_operating_schedule" {
  value = [for item in aws_lambda_function_event_invoke_config.operating_schedule : {
    function_name                = item.function_name
    id                           = item.id
    maximum_event_age_in_seconds = item.maximum_event_age_in_seconds
    maximum_retry_attempts       = item.maximum_retry_attempts
  }]
}

output "scheduler_schedule_operating" {
  value = { for key, item in aws_scheduler_schedule.operating : key => {
    flexible_time_window         = item.flexible_time_window
    id                           = item.id
    name                         = item.name
    schedule_expression          = item.schedule_expression
    schedule_expression_timezone = item.schedule_expression_timezone
    target                       = item.target
  } }
}
