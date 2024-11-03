variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "gitlab_domain" {
  description = "Domain name for GitLab instance"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "volume_size" {
  description = "Size of the EBS volume in GB"
  type        = number
  default     = 100
}

variable "gitlab_root_password" {
  description = "Default password for GitLab root user"
  type        = string
  sensitive   = true
} 