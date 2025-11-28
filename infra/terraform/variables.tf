variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "todo-app"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 30
}

variable "ssh_user" {
  description = "SSH user for connecting to instance"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
}

variable "ssh_allowed_ips" {
  description = "List of IPs allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "domain" {
  description = "Domain name for the application"
  type        = string
}

variable "cloudflare_email" {
  description = "Cloudflare email for SSL"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token for SSL"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT secret for authentication"
  type        = string
  sensitive   = true
}

variable "app_repo_url" {
  description = "Git repository URL for the application"
  type        = string
  default     = "https://github.com/thelogicguy/DevOps-Stage-6.git"
}

variable "app_repo_branch" {
  description = "Git branch to deploy"
  type        = string
  default     = "main"
}
