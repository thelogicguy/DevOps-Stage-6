output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app_server.id
}

output "instance_public_ip" {
  description = "Public IP address of the instance"
  value       = aws_eip.app_server.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the instance"
  value       = aws_instance.app_server.public_dns
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.app_server.id
}

output "ssh_connection_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${aws_eip.app_server.public_ip}"
}

output "application_url" {
  description = "Application URL"
  value       = "https://${var.domain}"
}

output "ansible_inventory_path" {
  description = "Path to generated Ansible inventory"
  value       = local_file.ansible_inventory.filename
}
