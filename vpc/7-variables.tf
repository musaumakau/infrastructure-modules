# VPC Variables
variable "env" {
  description = "Environment name — used for resource naming"
  type        = string
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability Zones for subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_tags" {
  description = "Additional tags for private subnets — used for EKS discovery labels"
  type        = map(string)
  default     = {}
}

variable "public_subnet_tags" {
  description = "Additional tags for public subnets — used for EKS discovery labels"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Tag variables — consumed by modules/tags
# ---------------------------------------------------------------------------

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
