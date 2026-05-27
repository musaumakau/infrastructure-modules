# =============================================================================
# MODULE: cicd-state
# =============================================================================
# Creates the shared S3 bucket used to store Terraform plan manifests between
# the plan pipeline (writes) and the deploy pipeline (reads).
#
# Also creates two IAM policies — one for each pipeline role:
#   plan-role   — needs to write manifests and deploy pointers to S3
#   deploy-role — needs to read manifests and deploy pointers from S3
#
# The roles themselves are managed separately. Attach the policy ARNs
# from the outputs of this module to your existing OIDC roles.
#
# Object layout inside the bucket:
#   pr-<number>/commit-<sha>/manifest.json   — plan manifest written on PR
#   deploy-pointer/<sha>.json                — pointer written on merge
# =============================================================================

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# KMS — encrypts all objects in the bucket
# -----------------------------------------------------------------------------

resource "aws_kms_key" "plan_manifests" {
  description             = "${var.project_name} plan manifest encryption key"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-plan-manifests-kms"
  })
}

resource "aws_kms_alias" "plan_manifests" {
  name          = "alias/${var.project_name}-plan-manifests"
  target_key_id = aws_kms_key.plan_manifests.key_id
}

# -----------------------------------------------------------------------------
# KMS key policy
# Root account retains full administrative access over this key.
# OIDC role is granted encrypt/decrypt only — no key administration.
# Both the IAM policy on the role AND this key policy must allow an action
# for it to succeed — KMS enforces both independently.
#
# Note: explicit admin actions are listed instead of kms:* to satisfy
# CKV_AWS_109 and CKV_AWS_356. Resources reference the key ARN directly
# instead of "*" for the same reason — AWS scopes key policies to the key
# implicitly but checkov requires an explicit ARN.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "plan_manifests_key_policy" {
  statement {
    sid    = "EnableRootAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]

    resources = [aws_kms_key.plan_manifests.arn]
  }

  statement {
    sid    = "AllowOIDCRoleAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.oidc_role_arn]
    }

    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]

    resources = [aws_kms_key.plan_manifests.arn]
  }
}

resource "aws_kms_key_policy" "plan_manifests" {
  key_id = aws_kms_key.plan_manifests.id
  policy = data.aws_iam_policy_document.plan_manifests_key_policy.json
}

# -----------------------------------------------------------------------------
# S3 bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "plan_manifests" {
  bucket = "${var.project_name}-terraform-plan-manifests"

  tags = merge(var.tags, {
    Name                       = "${var.project_name}-terraform-plan-manifests"
    "checkov:skip=CKV2_AWS_62" = "Event notifications not required for ephemeral CI/CD artifact bucket"
    "checkov:skip=CKV_AWS_144" = "Cross-region replication not required for ephemeral CI/CD plan manifests"
    "checkov:skip=CKV_AWS_18"  = "Access logging not required for ephemeral internal CI/CD manifests"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "plan_manifests" {
  bucket = aws_s3_bucket.plan_manifests.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.plan_manifests.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "plan_manifests" {
  bucket = aws_s3_bucket.plan_manifests.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "plan_manifests" {
  bucket = aws_s3_bucket.plan_manifests.id

  rule {
    id     = "expire-manifests"
    status = "Enabled"

    expiration {
      days = var.manifest_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "plan_manifests" {
  bucket = aws_s3_bucket.plan_manifests.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# IAM policy — plan pipeline role (write access)
# Scoped to the two key prefixes it needs to write:
#   pr-*            manifest files
#   deploy-pointer  SHA pointer files written on merge
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "plan_role" {
  statement {
    sid    = "WriteManifests"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.plan_manifests.arn}/pr-*",
      "${aws_s3_bucket.plan_manifests.arn}/deploy-pointer/*",
      "${aws_s3_bucket.plan_manifests.arn}/infracost-baseline/*",
    ]
  }

  statement {
    sid    = "KMSEncrypt"
    effect = "Allow"

    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]

    resources = [aws_kms_key.plan_manifests.arn]
  }
}

resource "aws_iam_policy" "plan_role" {
  name        = "${var.project_name}-cicd-plan-s3"
  description = "Allows the plan pipeline role to write plan manifests to S3"
  policy      = data.aws_iam_policy_document.plan_role.json

  tags = var.tags
}

# -----------------------------------------------------------------------------
# IAM policy — deploy pipeline role (read access)
# Read-only across the entire bucket — it needs to fetch both the pointer
# and the manifest it points to, without knowing the prefix in advance.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "deploy_role" {
  statement {
    sid    = "ReadManifests"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.plan_manifests.arn,
      "${aws_s3_bucket.plan_manifests.arn}/*",
    ]
  }

  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
    ]

    resources = [aws_kms_key.plan_manifests.arn]
  }
}

resource "aws_iam_policy" "deploy_role" {
  name        = "${var.project_name}-cicd-deploy-s3"
  description = "Allows the deploy pipeline role to read plan manifests from S3"
  policy      = data.aws_iam_policy_document.deploy_role.json

  tags = var.tags
}