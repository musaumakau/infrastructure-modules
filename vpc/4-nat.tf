resource "aws_eip" "this" {
  domain = "vpc"

  tags = merge(var.common_tags, {
    "Name" = "${var.env}-nat"
    "Type" = "EIP"
  })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.this.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.common_tags, {
    "Name" = "${var.env}-nat"
    "Type" = "NATGateway"
  })
  depends_on = [aws_internet_gateway.this]

}