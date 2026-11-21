locals {
  hosts = {
    "rhel9-canary" = { ami = data.aws_ami.rhel9.id, ring = "canary", os = "rhel9" }
    "rhel8-canary" = { ami = data.aws_ami.rhel8.id, ring = "canary", os = "rhel8" }
    "rhel9-r1"     = { ami = data.aws_ami.rhel9.id, ring = "ring1", os = "rhel9" }
    "rhel8-r1"     = { ami = data.aws_ami.rhel8.id, ring = "ring1", os = "rhel8" }
  }
}

resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.public_key_path))
}

resource "aws_instance" "fleet" {
  for_each = local.hosts

  ami                    = each.value.ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.patch_demo.id]
  key_name               = aws_key_pair.this.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name      = each.key
    Project   = "lm-demo"
    PatchRing = each.value.ring
    OS        = each.value.os
  }

  # Newer AMIs matching the filter shouldn't trigger instance replacement mid-demo.
  lifecycle {
    ignore_changes = [ami]
  }
}
