resource "samsungcloudplatformv2_vpc_vpc" "main" {
  name        = "${var.name_prefix}-vpc"
  cidr        = var.vpc_cidr
  description = "Terraform SSH demo VPC"
  tags        = var.tags
}

resource "samsungcloudplatformv2_vpc_subnet" "public" {
  name        = "${var.name_prefix}-subnet"
  vpc_id      = samsungcloudplatformv2_vpc_vpc.main.id
  type        = "GENERAL"
  cidr        = var.subnet_cidr
  description = "General subnet for the SSH demo VM"
  tags        = var.tags
}

resource "samsungcloudplatformv2_vpc_internet_gateway" "main" {
  vpc_id            = samsungcloudplatformv2_vpc_vpc.main.id
  type              = var.gateway_type
  description       = "Internet gateway for the SSH demo VM"
  firewall_enabled  = true
  firewall_loggable = false
  tags              = var.tags
}

resource "samsungcloudplatformv2_firewall_firewall_rule" "ssh" {
  firewall_id = samsungcloudplatformv2_vpc_internet_gateway.main.internet_gateway.firewall_id

  firewall_rule_create = {
    action              = "ALLOW"
    description         = "Allow SSH only from the caller public IP"
    destination_address = [var.subnet_cidr]
    direction           = "INBOUND"
    service = [{
      service_type  = "TCP"
      service_value = "22"
    }]
    source_address = [var.ssh_allowed_cidr]
    status         = "ENABLE"
  }
}

resource "samsungcloudplatformv2_firewall_firewall_rule" "allow_all_outbound" {
  firewall_id = samsungcloudplatformv2_vpc_internet_gateway.main.internet_gateway.firewall_id

  firewall_rule_create = {
    direction           = "OUTBOUND"
    action              = "ALLOW"
    source_address      = [var.subnet_cidr]
    destination_address = ["0.0.0.0/0"]
    description         = "Allow all outbound Internet traffic"
    service = [{
      service_type  = "ALL"
      service_value = "ALL"
    }]
    status = "ENABLE"
  }
}

resource "samsungcloudplatformv2_security_group_security_group" "vm" {
  name        = "${var.name_prefix}-sg"
  description = "SSH restricted to one public IPv4 address"
  loggable    = false
  tags        = var.tags
}

resource "samsungcloudplatformv2_security_group_security_group_rule" "ssh_ingress" {
  security_group_id = samsungcloudplatformv2_security_group_security_group.vm.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_allowed_cidr
  description       = "Allow SSH only from the caller public IP"
}

resource "samsungcloudplatformv2_security_group_security_group_rule" "allow_all_egress" {
  security_group_id = samsungcloudplatformv2_security_group_security_group.vm.id
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  description       = "Allow all outbound IPv4 traffic"
}

resource "samsungcloudplatformv2_vpc_publicip" "vm" {
  description = "Public IP for the SSH demo VM"
  type        = var.gateway_type
  tags        = var.tags
}

