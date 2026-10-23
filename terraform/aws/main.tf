locals {
  architecture             = startswith(var.instance_type, "t4g.") ? "arm64" : "x86_64"
  rpm_arch                 = startswith(var.instance_type, "t4g.") ? "aarch64" : "x86_64"
  token_path               = "/${var.name_prefix}/cloudflared/token"
  duckdns_path             = "/${var.name_prefix}/duckdns/token"
  server_availability_zone = coalesce(var.server_availability_zone, data.aws_availability_zones.available.names[0])
  database_availability_zones = concat([local.server_availability_zone], [
    for zone in data.aws_availability_zones.available.names : zone if zone != local.server_availability_zone
  ])

  user_data = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    aws_region            = var.aws_region
    swap_size_mib         = var.swap_size_mib
    cloudflared_version   = var.cloudflared_version
    rpm_arch              = local.rpm_arch
    token_path            = local.token_path
    enable_duckdns        = var.enable_duckdns
    duckdns_subdomain     = var.duckdns_subdomain
    duckdns_path          = local.duckdns_path
    duckdns_update_script = file("${path.module}/../../scripts/duckdns-update.py")
    enable_frontend       = var.enable_frontend
    frontend_nginx_image  = var.frontend_nginx_image
    frontend_nginx_config = local.frontend_nginx_config
    test_login_script     = file("${path.module}/templates/test-login.js")
    enable_test_login     = local.frontend_test_login
    test_login_path       = "/${var.name_prefix}/frontend/test-login"
    enable_ecs            = var.enable_ecs
    ecs_cluster_name      = "${var.name_prefix}-apps"
  })
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${local.architecture}"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name_prefix }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.42.1.0/24"
  availability_zone = local.server_availability_zone
  tags              = { Name = "${var.name_prefix}-public" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = var.name_prefix }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "server" {
  name_prefix = "${var.name_prefix}-"
  description = "Optional direct HTTP/HTTPS; management uses outbound SSM."
  vpc_id      = aws_vpc.main.id

  ingress = [for port in length(var.web_ingress_cidrs) > 0 ? [80, 443] : [] : {
    description      = "Direct web access."
    from_port        = port
    to_port          = port
    protocol         = "tcp"
    cidr_blocks      = var.web_ingress_cidrs
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    security_groups  = []
    self             = false
  }]

  egress {
    description = "Package updates, SSM, DuckDNS and Cloudflare Tunnel."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = var.name_prefix }
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
      Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter${local.token_path}"
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
      Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter${local.duckdns_path}"
    }]
  })
}

resource "aws_instance" "server" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.server.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.server.name
  disable_api_termination     = false
  monitoring                  = false
  user_data                   = local.user_data
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
      condition     = contains(data.aws_availability_zones.available.names, local.server_availability_zone)
      error_message = "Choose an available AZ in the target region."
    }

    precondition {
      condition     = !var.enable_frontend || (var.enable_duckdns && contains(var.web_ingress_cidrs, "0.0.0.0/0"))
      error_message = "DuckDNS static hosting requires enable_duckdns = true and public HTTP/HTTPS via web_ingress_cidrs = [\"0.0.0.0/0\"]."
    }
  }

  depends_on = [
    aws_route_table_association.public,
    aws_iam_role_policy.session_manager,
    aws_iam_role_policy.tunnel_token,
    aws_iam_role_policy.duckdns,
    aws_iam_role_policy.frontend_test_login,
    aws_iam_role_policy_attachment.ecs_host,
    aws_ecs_cluster.apps,
  ]

  tags = { Name = var.name_prefix }
}
