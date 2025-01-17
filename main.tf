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
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
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

# Add CloudWatch Log Group
resource "aws_cloudwatch_log_group" "gitlab" {
  name              = "/aws/ec2/gitlab"
  retention_in_days = 30

  tags = {
    Name        = "gitlab-logs"
    Environment = var.environment
  }
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
              
              # Install CloudWatch Agent first
              apt-get update
              apt-get install -y amazon-cloudwatch-agent

              # Install SSM Agent
              snap install amazon-ssm-agent --classic
              systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
              systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

              # Install GitLab
              apt-get install -y curl openssh-server ca-certificates tzdata perl
              curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh | bash
              EXTERNAL_URL="https://${var.gitlab_domain}" apt-get install gitlab-ee

              # Wait for GitLab logs directory to be created
              while [ ! -d "/var/log/gitlab" ]; do
                sleep 10
              done

              # Create CloudWatch Agent configuration
              cat > /opt/aws/amazon-cloudwatch-agent/config.json <<'CWAGENTCONFIG'
              {
                "agent": {
                  "metrics_collection_interval": 60,
                  "run_as_user": "root"
                },
                "logs": {
                  "logs_collected": {
                    "files": {
                      "collect_list": [
                        {
                          "file_path": "/var/log/gitlab/gitlab-rails/production.log",
                          "log_group_name": "${aws_cloudwatch_log_group.gitlab.name}",
                          "log_stream_name": "{instance_id}-gitlab-rails",
                          "timestamp_format": "%Y-%m-%d %H:%M:%S",
                          "timezone": "UTC"
                        },
                        {
                          "file_path": "/var/log/gitlab/nginx/gitlab_access.log",
                          "log_group_name": "${aws_cloudwatch_log_group.gitlab.name}",
                          "log_stream_name": "{instance_id}-nginx-access",
                          "timestamp_format": "%d/%b/%Y:%H:%M:%S %z",
                          "timezone": "UTC"
                        },
                        {
                          "file_path": "/var/log/gitlab/nginx/gitlab_error.log",
                          "log_group_name": "${aws_cloudwatch_log_group.gitlab.name}",
                          "log_stream_name": "{instance_id}-nginx-error",
                          "timestamp_format": "%Y/%m/%d %H:%M:%S",
                          "timezone": "UTC"
                        },
                        {
                          "file_path": "/var/log/gitlab/gitlab-rails/sidekiq.log",
                          "log_group_name": "${aws_cloudwatch_log_group.gitlab.name}",
                          "log_stream_name": "{instance_id}-sidekiq",
                          "timestamp_format": "%Y-%m-%d %H:%M:%S",
                          "timezone": "UTC"
                        },
                        {
                          "file_path": "/var/log/gitlab/gitlab-rails/application.log",
                          "log_group_name": "${aws_cloudwatch_log_group.gitlab.name}",
                          "log_stream_name": "{instance_id}-application",
                          "timestamp_format": "%Y-%m-%d %H:%M:%S",
                          "timezone": "UTC"
                        }
                      ]
                    }
                  }
                },
                "metrics": {
                  "metrics_collected": {
                    "mem": {
                      "measurement": ["mem_used_percent"]
                    },
                    "disk": {
                      "measurement": ["disk_used_percent"],
                      "resources": ["/"]
                    }
                  }
                }
              }
              CWAGENTCONFIG

              # Set proper permissions
              chmod 644 /opt/aws/amazon-cloudwatch-agent/config.json

              # Start CloudWatch Agent with new configuration
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/config.json
              systemctl enable amazon-cloudwatch-agent
              systemctl restart amazon-cloudwatch-agent

              # Wait for GitLab to be fully configured
              while ! curl -s http://localhost/-/health > /dev/null; do
                sleep 30
              done

              # Set root password
              gitlab-rails runner "user = User.find(1); user.password = '${var.gitlab_root_password}'; user.password_confirmation = '${var.gitlab_root_password}'; user.save!"

              # Verify CloudWatch Agent is running
              systemctl status amazon-cloudwatch-agent
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
  content = aws_eip.gitlab.public_ip
  type    = "A"
  proxied = false

  depends_on = [aws_eip.gitlab]
}

# Add CloudWatch monitoring permissions to the IAM role
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.gitlab_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Add additional IAM policy for CloudWatch Logs
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "gitlab-cloudwatch-logs-policy"
  role = aws_iam_role.gitlab_instance_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.gitlab.arn}",
          "${aws_cloudwatch_log_group.gitlab.arn}:*"
        ]
      }
    ]
  })
} 