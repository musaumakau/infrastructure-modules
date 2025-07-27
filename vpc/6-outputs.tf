output "vpc_id" {
  description = "The ID of the VPC created in the Dev environment"
  value       = aws_vpc.this.id

}

output "private_subnet_ids" {
  value = aws_subnet.private.*.id

}

output "public_subnet_ids" {
  value = aws_subnet.public.*.id

}