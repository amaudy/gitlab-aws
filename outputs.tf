output "instance_id" {
  description = "ID of the GitLab EC2 instance"
  value       = aws_instance.gitlab.id
}

output "public_ip" {
  description = "Public IP address of the GitLab instance"
  value       = aws_eip.gitlab.public_ip
}

output "gitlab_url" {
  description = "URL of the GitLab instance"
  value       = "https://${var.gitlab_domain}"
} 