output "ecr_repository_apps" {
  value = { for key, item in aws_ecr_repository.apps : key => {
    encryption_configuration     = item.encryption_configuration
    force_delete                 = item.force_delete
    id                           = item.id
    image_scanning_configuration = item.image_scanning_configuration
    image_tag_mutability         = item.image_tag_mutability
    name                         = item.name
    repository_url               = item.repository_url
  } }
}

output "ecs_task_definition_apps" {
  value = [for item in aws_ecs_task_definition.apps : {
    arn                      = item.arn
    container_definitions    = item.container_definitions
    cpu                      = item.cpu
    execution_role_arn       = item.execution_role_arn
    family                   = item.family
    id                       = item.id
    memory                   = item.memory
    network_mode             = item.network_mode
    requires_compatibilities = item.requires_compatibilities
    runtime_platform         = item.runtime_platform
    task_role_arn            = item.task_role_arn
  }]
}

output "ecs_service_apps" {
  value = [for item in aws_ecs_service.apps : {
    cluster                            = item.cluster
    deployment_circuit_breaker         = item.deployment_circuit_breaker
    deployment_maximum_percent         = item.deployment_maximum_percent
    deployment_minimum_healthy_percent = item.deployment_minimum_healthy_percent
    desired_count                      = item.desired_count
    id                                 = item.id
    launch_type                        = item.launch_type
    name                               = item.name
    task_definition                    = item.task_definition
    wait_for_steady_state              = item.wait_for_steady_state
  }]
}
