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
      condition     = (var.gateway_image == null) == (var.service_image == null)
      error_message = "Supply both Gateway and Service images together, or leave both null."
    }
    precondition {
      condition     = !var.apps_enabled || (var.enable_frontend && var.frontend_api_mode == "live")
      error_message = "Application routing requires enable_frontend=true and frontend_api_mode=live."
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_host" {
  count      = var.enable_ecs ? 1 : 0
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role" "server" {
  name = "${var.name_prefix}-server"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "session_manager" {
  name = "session-manager"
  role = aws_iam_role.server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "tunnel_token" {
  name = "read-tunnel-token"
  role = aws_iam_role.server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter${var.token_path}"
    }]
  })
}

resource "aws_iam_instance_profile" "server" {
  name = "${var.name_prefix}-server"
  role = aws_iam_role.server.name
}

resource "aws_iam_role_policy" "duckdns" {
  count = var.enable_duckdns ? 1 : 0
  name  = "read-duckdns-token"
  role  = aws_iam_role.server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter${var.duckdns_path}"
    }]
  })
}

resource "aws_instance" "server" {
  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_public_id
  vpc_security_group_ids      = [var.security_group_server_id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.server.name
  disable_api_termination     = false
  monitoring                  = false
  user_data                   = var.user_data
  user_data_replace_on_change = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  dynamic "credit_specification" {
    for_each = startswith(var.instance_type, "t") ? [1] : []
    content {
      cpu_credits = "standard"
    }
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gib
    encrypted             = true
    delete_on_termination = true
    tags                  = { Name = "${var.name_prefix}-root" }
  }

  lifecycle {
    # After launch, configuration changes are delivered by the SSM association.
    ignore_changes = [ami, user_data]

    precondition {
      condition     = var.free_tier_confirmed
      error_message = "Check the AWS account plan, remaining credits and instance eligibility, then set free_tier_confirmed=true."
    }

    precondition {
      condition     = contains(var.available_zone_names, var.server_availability_zone)
      error_message = "Choose an available AZ in the target region."
    }

    precondition {
      condition     = !var.enable_frontend || (var.enable_duckdns && contains(var.web_ingress_cidrs, "0.0.0.0/0"))
      error_message = "DuckDNS static hosting requires enable_duckdns = true and public HTTP/HTTPS via web_ingress_cidrs = [\"0.0.0.0/0\"]."
    }
  }

  depends_on = [aws_iam_role_policy.session_manager, aws_iam_role_policy.tunnel_token, aws_iam_role_policy.duckdns, aws_iam_role_policy.frontend_test_login, aws_iam_role_policy_attachment.ecs_host, aws_ecs_cluster.apps]

  tags = { Name = var.name_prefix }
}

resource "aws_iam_role_policy" "frontend_test_login" {
  count = var.frontend_test_login ? 1 : 0
  name  = "read-frontend-test-login"
  role  = aws_iam_role.server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.name_prefix}/frontend/test-login"
    }]
  })
}

resource "aws_ssm_document" "server" {
  name            = "${var.name_prefix}-configure-server"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Apply the OpenStudy server configuration managed by Terraform."
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "configureServer"
      inputs = {
        timeoutSeconds = "1800"
        runCommand = [
          "set -eu",
          # Wait for the first boot to finish, including the failed-bootstrap case.
          "cloud-init status --wait || true",
          "install -d -m 0700 /var/lib/openstudy-bootstrap",
          "cat > /var/lib/openstudy-bootstrap/apply.sh <<'OPENSTUDY_BOOTSTRAP'\n${var.user_data}\nOPENSTUDY_BOOTSTRAP",
          "chmod 0700 /var/lib/openstudy-bootstrap/apply.sh",
          "bash /var/lib/openstudy-bootstrap/apply.sh",
        ]
      }
    }]
  })
}

resource "aws_iam_role_policy" "server_configuration" {
  name = "server-configuration"
  role = aws_iam_role.server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeAssociation",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:PutComplianceItems",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetDocument", "ssm:DescribeDocument"]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:document/${aws_ssm_document.server.name}"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_ssm_association" "server" {
  name                             = aws_ssm_document.server.name
  association_name                 = "${var.name_prefix}-configure-server"
  document_version                 = aws_ssm_document.server.latest_version
  wait_for_success_timeout_seconds = 1800

  targets {
    key    = "InstanceIds"
    values = [aws_instance.server.id]
  }

  # This provider waits for success only on creation, so replace the association
  # for each document change. The EC2 instance is kept in place.
  lifecycle {
    replace_triggered_by = [aws_ssm_document.server.content]
  }

  depends_on = [aws_iam_role_policy.server_configuration, aws_iam_role_policy.frontend_test_login]
}
