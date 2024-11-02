# VPC Endpoints for Systems Manager
resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.vpc_endpoints.id]
  subnet_ids         = [data.aws_subnets.default.ids[0]]

  private_dns_enabled = true

  tags = {
    Name        = "ssm-endpoint"
    Environment = var.environment
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.vpc_endpoints.id]
  subnet_ids         = [data.aws_subnets.default.ids[0]]

  private_dns_enabled = true

  tags = {
    Name        = "ssmmessages-endpoint"
    Environment = var.environment
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.vpc_endpoints.id]
  subnet_ids         = [data.aws_subnets.default.ids[0]]

  private_dns_enabled = true

  tags = {
    Name        = "ec2messages-endpoint"
    Environment = var.environment
  }
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  tags = {
    Name        = "vpc-endpoints-sg"
    Environment = var.environment
  }
} 