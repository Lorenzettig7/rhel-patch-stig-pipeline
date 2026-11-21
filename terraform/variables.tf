variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "my_ip_cidr" {
  description = "CIDR allowed to SSH to the fleet (e.g. 203.0.113.10/32)."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.my_ip_cidr))
    error_message = "my_ip_cidr must be a valid IPv4 CIDR, e.g. 203.0.113.10/32."
  }
}

variable "public_key_path" {
  description = "Path to the SSH public key to register as the EC2 key pair."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "key_name" {
  description = "Name for the EC2 key pair."
  type        = string
  default     = "patch-demo-key"
}

variable "instance_type" {
  description = "EC2 instance type for all fleet hosts."
  type        = string
  default     = "t3.medium"
}
