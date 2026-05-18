# Changelog

## v0.0.1
- Initial release
- S3 bucket for Terraform plan manifests with KMS encryption, versioning, and lifecycle rules
- KMS key policy granting root admin access and OIDC role encrypt/decrypt
- IAM policy for plan pipeline role — write access scoped to pr-* and deploy-pointer/* prefixes
- IAM policy for deploy pipeline role — read-only access across bucket