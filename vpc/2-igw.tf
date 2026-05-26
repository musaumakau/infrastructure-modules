# Internet gateway for the VPC
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(module.tags.tags, {
    Name = "${var.env}-igw"
    Type = "InternetGateway"
  })
}
