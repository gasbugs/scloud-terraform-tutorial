variable "name_prefix" {
  description = "Prefix used for resources created by this project."
  type        = string
  default     = "tf-ssh"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,12}$", var.name_prefix))
    error_message = "name_prefix must be 3-12 characters containing only letters, numbers, and hyphens."
  }
}

variable "vpc_cidr" {
  description = "CIDR for the VPC. SCP accepts prefixes from /16 through /24."
  type        = string
  default     = "10.10.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 24
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix between /16 and /24."
  }
}

variable "subnet_cidr" {
  description = "CIDR for the General subnet attached to the Internet Gateway."
  type        = string
  default     = "10.10.1.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid IPv4 CIDR."
  }
}

variable "zone" {
  description = "SCP availability zone, for example kr-west1-a."
  type        = string
}

variable "gateway_type" {
  description = "Internet Gateway and Public IP type. GGW is used for SCP for Samsung; use the type appropriate for your environment."
  type        = string
  default     = "GGW"

  validation {
    condition     = contains(["IGW", "GGW", "SIGW"], var.gateway_type)
    error_message = "gateway_type must be IGW, GGW, or SIGW."
  }
}

variable "ssh_allowed_cidr" {
  description = "The caller's current public IPv4 address as a single-host /32 CIDR."
  type        = string

  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.ssh_allowed_cidr)) && can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be one valid IPv4 host with a /32 prefix, for example 203.0.113.10/32."
  }
}

variable "ubuntu_image_id" {
  description = "SCP standard-image ID for Ubuntu 24.04 in the target service zone. Replace the placeholder before apply."
  type        = string
  default     = "REPLACE_WITH_UBUNTU_24_04_STANDARD_IMAGE_ID"

  validation {
    condition     = length(trimspace(var.ubuntu_image_id)) > 0
    error_message = "ubuntu_image_id must not be empty."
  }
}

variable "server_type_id" {
  description = "ID of the Virtual Server type. Defaults to the smallest Standard V3 type (1 vCPU, 2 GiB)."
  type        = string
  default     = "s3v1m2"

  validation {
    condition     = length(trimspace(var.server_type_id)) > 0
    error_message = "server_type_id must not be empty."
  }
}

variable "private_key_filename" {
  description = "Local path where the generated SCP private key is written with mode 0600."
  type        = string
  default     = "./tf-ssh.pem"

  validation {
    condition     = length(trimspace(var.private_key_filename)) > 0
    error_message = "private_key_filename must not be empty."
  }
}

variable "boot_volume_size" {
  description = "Ubuntu boot volume size in GiB. SCP requires a multiple of 8."
  type        = number
  default     = 16

  validation {
    condition     = var.boot_volume_size >= 8 && var.boot_volume_size % 8 == 0
    error_message = "boot_volume_size must be at least 8 GiB and a multiple of 8."
  }
}

variable "tags" {
  description = "Tags applied to resources that support tags."
  type        = map(string)
  default = {
    managed-by = "terraform"
    project    = "scloud-ssh-demo"
  }
}

