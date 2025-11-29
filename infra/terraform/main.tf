# infra/terraform/main.tf

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source for latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group
resource "aws_security_group" "app_server" {
  name        = "${var.project_name}-sg"
  description = "Security group for TODO app server"

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_ips
    description = "SSH access"
  }

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access"
  }

  # Outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# Local values for SSH key handling
locals {
  # Use ssh_public_key if provided (CI/CD), otherwise try to read from file (local)
  # Use try() to gracefully handle missing files in CI
  ssh_public_key_content = var.ssh_public_key != "" ? var.ssh_public_key : try(file(var.ssh_public_key_path), "")
}

# Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-key"
  public_key = local.ssh_public_key_content

  tags = {
    Name    = "${var.project_name}-key"
    Project = var.project_name
  }

  lifecycle {
    ignore_changes = [public_key]
  }
}

# EC2 Instance specification
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name

  vpc_security_group_ids = [aws_security_group.app_server.id]

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    hostname = var.project_name
  })

  tags = {
    Name    = "${var.project_name}-server"
    Project = var.project_name
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# Elastic IP
resource "aws_eip" "app_server" {
  instance = aws_instance.app_server.id
  domain   = "vpc"

  tags = {
    Name    = "${var.project_name}-eip"
    Project = var.project_name
  }

  depends_on = [aws_instance.app_server]
}

# Generate Ansible Inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    server_ip    = aws_eip.app_server.public_ip
    ssh_user     = var.ssh_user
    ssh_key_path = var.ssh_private_key_path
  })
  filename        = "${path.module}/../ansible/inventory/hosts"
  file_permission = "0644"

  depends_on = [aws_eip.app_server]
}

# Wait for instance to be ready using reliable remote-exec
resource "null_resource" "wait_for_instance" {
  # Ensures this resource only runs after the instance is provisioned 
  # and the EIP is associated.
  depends_on = [
    aws_instance.app_server, 
    aws_eip.app_server,
    local_file.ansible_inventory,
  ]

  # === Connection Block: Tells Terraform how to connect via SSH ===
  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    # Use the public IP from the EIP resource
    host        = aws_eip.app_server.public_ip
    timeout     = "10m" # Terraform will retry connection for up to 10 minutes
  }

  # === Remote-Exec: The actual command to run on the instance ===
  provisioner "remote-exec" {
    inline = [
      "echo 'Successfully connected via SSH.'",
      "echo 'Waiting for cloud-init to complete...'",
      # Wait for the package manager lock to clear, signaling initial setup is done.
      "while sudo lsof /var/lib/dpkg/lock-frontend >/dev/null; do sleep 5; done", 
      "echo 'Instance is ready for configuration.'",
    ]
  }

  triggers = {
    public_ip = aws_eip.app_server.public_ip
  }
}

# Run Ansible Playbook
resource "null_resource" "run_ansible" {
  triggers = {
    instance_id = aws_instance.app_server.id
    inventory   = local_file.ansible_inventory.content
  }

  provisioner "local-exec" {
    command     = "ansible-playbook -i inventory/hosts playbook.yml"
    working_dir = "${path.module}/../ansible"
    environment = {
      DOMAIN           = var.domain
      CF_API_EMAIL     = var.cloudflare_email
      CF_DNS_API_TOKEN = var.cloudflare_api_token
      JWT_SECRET       = var.jwt_secret
      APP_REPO_URL     = var.app_repo_url
      APP_REPO_BRANCH  = var.app_repo_branch
    }
  }

  depends_on = [
    null_resource.wait_for_instance
  ]
}