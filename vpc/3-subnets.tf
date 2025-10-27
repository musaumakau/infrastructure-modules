#subnet.tf
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(
    {
      Name = "${var.env}-private-${count.index + 1}"
    },
    var.private_subnet_tags
  )

}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(
    {
      Name = "${var.env}-public-${count.index + 1}"
    },
    var.public_subnet_tags
  )

}