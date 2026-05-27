# =============================================================================
# MODULE: cicd-state — variables
# =============================================================================

variable "project_name" {
  description = "Project name used to prefix all resource names"
  type        = string
}


variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "kms_deletion_window_days" {
  description = "Number of days before a scheduled KMS key deletion takes effect"
  type        = number
  default     = 7
}

variable "manifest_retention_days" {
  description = "Number of days before plan manifest objects are automatically deleted"
  type        = number
  default     = 90
}

variable "noncurrent_version_retention_days" {
  description = "Number of days before non-current object versions are deleted"
  type        = number
  default     = 30
}


variable "oidc_role_arn" {
  description = "ARN of the OIDC role used by both pipelines — granted encrypt/decrypt access on the KMS key"
  type        = string
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "owner" {
  description = "Team responsible for these resources"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing and chargeback"
  type        = string
}
