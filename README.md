# GitLab Server on AWS

Terraform configuration to deploy GitLab Enterprise Edition on AWS with Cloudflare DNS integration.

## Quick Start

1. **Prepare terraform.tfvars**:
```hcl
# AWS
aws_region    = "us-east-1"
instance_type = "t3.large"
environment   = "production"

# GitLab
gitlab_domain        = "gitlab.yourdomain.com"
gitlab_root_password = "xxxxxxxxxx"  # Change this!
volume_size         = 100

# Cloudflare
cloudflare_zone_id   = "your-zone-id"
cloudflare_api_token = "your-api-token"
```

2. **Deploy**:
```bash
terraform init
terraform apply
```

3. **Access GitLab**:
- URL: https://gitlab.yourdomain.com
- Username: root
- Password: [value from gitlab_root_password]

## Prerequisites
- AWS CLI configured
- Terraform installed
- Cloudflare account with domain

## Monitoring
CloudWatch logs available at `/aws/ec2/gitlab`

## Server Access
```bash
aws ssm start-session --target <instance-id>
```

## Cleanup
```bash
terraform destroy
```