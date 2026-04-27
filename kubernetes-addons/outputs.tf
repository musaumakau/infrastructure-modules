output "aws_lbc_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = try(aws_iam_role.aws_lbc[0].arn, null)
}