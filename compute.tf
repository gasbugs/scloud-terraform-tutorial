resource "samsungcloudplatformv2_virtualserver_keypair" "vm" {
  name = "${var.name_prefix}-key"
  tags = var.tags
}

resource "local_sensitive_file" "private_key" {
  filename             = var.private_key_filename
  content              = samsungcloudplatformv2_virtualserver_keypair.vm.private_key
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "samsungcloudplatformv2_virtualserver_server" "vm" {
  name           = "${var.name_prefix}-vm"
  state          = "ACTIVE"
  image_id       = var.ubuntu_image_id
  server_type_id = var.server_type_id
  keypair_name   = samsungcloudplatformv2_virtualserver_keypair.vm.name
  zone           = var.zone

  product_category = "compute"
  product_offering = "virtual_server"
  security_groups  = [samsungcloudplatformv2_security_group_security_group.vm.id]

  boot_volume = {
    size                  = var.boot_volume_size
    type                  = "SSD"
    delete_on_termination = true
  }

  networks = {
    primary = {
      subnet_id    = samsungcloudplatformv2_vpc_subnet.public.id
      public_ip_id = samsungcloudplatformv2_vpc_publicip.vm.id
    }
  }

  tags = var.tags

  depends_on = [
    local_sensitive_file.private_key,
    samsungcloudplatformv2_firewall_firewall_rule.ssh,
    samsungcloudplatformv2_security_group_security_group_rule.ssh_ingress,
  ]
}

