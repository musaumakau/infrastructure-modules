resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr_block

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.env}-main"
    Type = "VPC"
  })
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id


  ingress = []

  egress = [
    {
      description      = "HTTPS outbound for EKS API calls"
      from_port        = 443
      to_port          = 443
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  tags = merge(var.common_tags, {
    Name = "${var.env}-default-sg-restricted"
    Type = "SecurityGroup"
  })
}

