output "vm_id" {
  description = "ID of the created Virtual Server."
  value       = samsungcloudplatformv2_virtualserver_server.vm.id
}

output "ubuntu_image" {
  description = "Configured Ubuntu 24.04 standard-image ID."
  value       = var.ubuntu_image_id
}

output "public_ip" {
  description = "Public IPv4 address attached to the Virtual Server."
  value       = samsungcloudplatformv2_vpc_publicip.vm.publicip.ip_address
}

output "ssh_command" {
  description = "SSH command for the Ubuntu image."
  value       = "ssh -i ${var.private_key_filename} ubuntu@${samsungcloudplatformv2_vpc_publicip.vm.publicip.ip_address}"
}

output "private_key_file" {
  description = "Local path of the generated private key. This file is excluded from Git."
  value       = local_sensitive_file.private_key.filename
}

