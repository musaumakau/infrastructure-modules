# Subnets
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  # module.tags.tags provides the base governance tags
  # var.private_subnet_tags allows EKS-required labels (e.g. kubernetes.io/role/internal-elb)
  # Name is always set last and is not overridable via subnet tags
  tags = merge(module.tags.tags, var.private_subnet_tags, {
    Name = "${var.env}-private-${count.index + 1}"
    Type = "PrivateSubnet"
  })
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(module.tags.tags, var.public_subnet_tags, {
    Name = "${var.env}-public-${count.index + 1}"
    Type = "PublicSubnet"
  })
}
