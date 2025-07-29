resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr_block

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.env}-main"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id

  # Remove all default ingress rules
  ingress = []

  # Remove all default egress rules  
  egress = []

  tags = {
    Name = "${var.env}-default-sg-restricted"
  }
}

