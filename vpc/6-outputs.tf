output "vpc_id" {
  description = "The ID of the VPC created in the Dev environment"
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  value = [for subnet in aws_subnet.private : subnet.id]
}

output "public_subnet_ids" {
  value = [for subnet in aws_subnet.public : subnet.id]
}
