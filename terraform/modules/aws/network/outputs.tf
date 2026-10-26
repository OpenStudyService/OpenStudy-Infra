output "vpc_main" {
  value = {
    cidr_block           = aws_vpc.main.cidr_block
    enable_dns_hostnames = aws_vpc.main.enable_dns_hostnames
    enable_dns_support   = aws_vpc.main.enable_dns_support
    id                   = aws_vpc.main.id
    tags                 = aws_vpc.main.tags
  }
}

output "subnet_public" {
  value = {
    availability_zone = aws_subnet.public.availability_zone
    cidr_block        = aws_subnet.public.cidr_block
    id                = aws_subnet.public.id
    tags              = aws_subnet.public.tags
    vpc_id            = aws_subnet.public.vpc_id
  }
}

output "security_group_server" {
  value = {
    description = aws_security_group.server.description
    egress      = aws_security_group.server.egress
    id          = aws_security_group.server.id
    ingress     = aws_security_group.server.ingress
    name_prefix = aws_security_group.server.name_prefix
    tags        = aws_security_group.server.tags
    vpc_id      = aws_security_group.server.vpc_id
  }
}
