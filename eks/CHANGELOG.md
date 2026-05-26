# Changelog

## v0.0.3
- Replaced hardcoded IAM ARNs with `admin_principal_arns` and `github_actions_role_arn` variables
- Added `taint`, `label`, and `ami_type` support to node groups variable
- Fixed `SecurtityGroup` typo in security group resource tags
- Removed dead code — commented out `node_groups` variable block

## v0.0.2
- Added KMS encryption for EKS secrets at rest
- Added custom security groups for cluster and nodes
- Enabled all five control plane log types
- Added IMDSv2 enforcement on launch template
- Added EKS access entries for admin and GitHub Actions principals
- Added IRSA support via OpenID Connect provider

## v0.0.1
- Initial release# pipeline test
