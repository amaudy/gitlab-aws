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

# Add IAM role and instance profile for Session Manager
resource "aws_iam_role" "gitlab_instance_role" {
  name = "gitlab-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "gitlab-instance-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "systems_manager" {
  role       = aws_iam_role.gitlab_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "gitlab_instance_profile" {
  name = "gitlab-instance-profile"
  role = aws_iam_role.gitlab_instance_role.name
}

resource "aws_instance" "gitlab" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = data.aws_subnets.default.ids[0] # Use first subnet from default VPC

  # Enable detailed monitoring
  monitoring = true

  # Add IAM instance profile
  iam_instance_profile = aws_iam_instance_profile.gitlab_instance_profile.name

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  vpc_security_group_ids = [aws_security_group.gitlab.id]

  user_data = <<-EOF
              #!/bin/bash
              # Install SSM Agent
              snap install amazon-ssm-agent --classic
              systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
              systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

              # Install CloudWatch Agent
              apt-get update
              apt-get install -y amazon-cloudwatch-agent
              systemctl enable amazon-cloudwatch-agent
              systemctl start amazon-cloudwatch-agent

              # Install GitLab
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

# Add CloudWatch monitoring permissions to the IAM role
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.gitlab_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
} 