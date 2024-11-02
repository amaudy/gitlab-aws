# Add data source for default VPC
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "gitlab" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = data.aws_subnets.default.ids[0] # Use first subnet from default VPC

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  vpc_security_group_ids = [aws_security_group.gitlab.id]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y curl openssh-server ca-certificates tzdata perl
              curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh | bash
              EXTERNAL_URL="https://${var.gitlab_domain}" apt-get install gitlab-ee
              EOF

  tags = {
    Name        = "gitlab-server"
    Environment = var.environment
  }
}

resource "aws_eip" "gitlab" {
  instance = aws_instance.gitlab.id
  domain   = "vpc"

  tags = {
    Name        = "gitlab-eip"
    Environment = var.environment
  }
}

# Cloudflare DNS Record
resource "cloudflare_record" "gitlab" {
  zone_id = var.cloudflare_zone_id
  name    = var.gitlab_domain
  value   = aws_eip.gitlab.public_ip
  type    = "A"
  proxied = false
} 