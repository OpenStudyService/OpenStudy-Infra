resource "aws_vpc" "main" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name_prefix }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.42.1.0/24"
  availability_zone = var.server_availability_zone
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
