data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "patch-demo-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "patch-demo-igw" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.20.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  # Accepted risk (demo): hosts need public IPs for operator SSH, which the
  # security group limits to var.my_ip_cidr. Production would use private
  # subnets with SSM Session Manager or a bastion. Re-review by expiry.
  #trivy:ignore:AWS-0164:exp:2027-05-22
  map_public_ip_on_launch = true

  tags = { Name = "patch-demo-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "patch-demo-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "patch_demo" {
  name        = "patch-demo-sg"
  description = "SSH from operator IP; all egress"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  # Accepted risk (demo): dnf must reach Red Hat RHUI/CDN endpoints, which
  # have no stable CIDR list. Production would route egress through a proxy
  # or VPC endpoints with an allowlist. Re-review by expiry.
  #trivy:ignore:AWS-0104:exp:2027-05-22
  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "patch-demo-sg" }
}
