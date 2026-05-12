
output "bucket_name" {
  value = aws_s3_bucket.plan_manifests.id
}

output "bucket_arn" {
  value = aws_s3_bucket.plan_manifests.arn
}

output "plan_role_policy_arn" {
  value = aws_iam_policy.plan_role_s3.arn
  description = "Attach this to your GitHub Actions plan IAM role"
}

output "deploy_role_policy_arn" {
  value = aws_iam_policy.deploy_role_s3.arn
  description = "Attach this to your GitHub Actions deploy IAM role"
}