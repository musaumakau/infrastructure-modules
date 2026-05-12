
output "bucket_name" {
  value = aws_s3_bucket.plan_manifests.id
}

output "bucket_arn" {
  value = aws_s3_bucket.plan_manifests.arn
}

output "plan_role_policy_arn" {
  value = aws_iam_policy.plan_role.arn
}

output "deploy_role_policy_arn" {
  value = aws_iam_policy.deploy_role.arn
}