output "ecs_cluster_apps" {
  value = [for item in aws_ecs_cluster.apps : {
    id      = item.id
    name    = item.name
    setting = item.setting
  }]
}

output "iam_role_server" {
  value = {
    assume_role_policy = aws_iam_role.server.assume_role_policy
    id                 = aws_iam_role.server.id
    name               = aws_iam_role.server.name
  }
}

output "iam_role_policy_session_manager" {
  value = {
    id     = aws_iam_role_policy.session_manager.id
    name   = aws_iam_role_policy.session_manager.name
    policy = aws_iam_role_policy.session_manager.policy
    role   = aws_iam_role_policy.session_manager.role
  }
}

output "iam_role_policy_tunnel_token" {
  value = {
    id     = aws_iam_role_policy.tunnel_token.id
    name   = aws_iam_role_policy.tunnel_token.name
    policy = aws_iam_role_policy.tunnel_token.policy
    role   = aws_iam_role_policy.tunnel_token.role
  }
}

output "iam_role_policy_duckdns" {
  value = [for item in aws_iam_role_policy.duckdns : {
    id     = item.id
    name   = item.name
    policy = item.policy
    role   = item.role
  }]
}

output "instance_server" {
  value = {
    ami                         = aws_instance.server.ami
    arn                         = aws_instance.server.arn
    associate_public_ip_address = aws_instance.server.associate_public_ip_address
    credit_specification        = aws_instance.server.credit_specification
    disable_api_termination     = aws_instance.server.disable_api_termination
    iam_instance_profile        = aws_instance.server.iam_instance_profile
    id                          = aws_instance.server.id
    instance_type               = aws_instance.server.instance_type
    metadata_options            = aws_instance.server.metadata_options
    monitoring                  = aws_instance.server.monitoring
    public_ip                   = aws_instance.server.public_ip
    root_block_device           = aws_instance.server.root_block_device
    subnet_id                   = aws_instance.server.subnet_id
    tags                        = aws_instance.server.tags
    user_data                   = aws_instance.server.user_data
    user_data_replace_on_change = aws_instance.server.user_data_replace_on_change
    vpc_security_group_ids      = aws_instance.server.vpc_security_group_ids
  }
}

output "iam_role_policy_frontend_test_login" {
  value = [for item in aws_iam_role_policy.frontend_test_login : {
    id     = item.id
    name   = item.name
    policy = item.policy
    role   = item.role
  }]
}

output "ssm_document_server" {
  value = {
    content         = aws_ssm_document.server.content
    document_format = aws_ssm_document.server.document_format
    document_type   = aws_ssm_document.server.document_type
    id              = aws_ssm_document.server.id
    latest_version  = aws_ssm_document.server.latest_version
    name            = aws_ssm_document.server.name
  }
}

output "iam_role_policy_server_configuration" {
  value = {
    id     = aws_iam_role_policy.server_configuration.id
    name   = aws_iam_role_policy.server_configuration.name
    policy = aws_iam_role_policy.server_configuration.policy
    role   = aws_iam_role_policy.server_configuration.role
  }
}

output "ssm_association_server" {
  value = {
    association_id                   = aws_ssm_association.server.association_id
    association_name                 = aws_ssm_association.server.association_name
    document_version                 = aws_ssm_association.server.document_version
    id                               = aws_ssm_association.server.id
    name                             = aws_ssm_association.server.name
    targets                          = aws_ssm_association.server.targets
    wait_for_success_timeout_seconds = aws_ssm_association.server.wait_for_success_timeout_seconds
  }
}
