variable "env" {
  description = "Environment name — used for resource naming"
  type        = string
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "vpc_id" {
  description = "VPC ID where EKS resources will be created"
  type        = string
  default     = ""
}

variable "eks_name" {
  description = "Name of the cluster"
  type        = string
}

variable "eks_version" {
  description = "Desired Kubernetes version for the master"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs, must be in at least two different availability zones"
  type        = list(string)
}

variable "node_iam_policies" {
  description = "List of IAM policies to attach to EKS-managed nodes"
  type        = map(string)
  default = {
    1 = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    2 = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    3 = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    4 = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

variable "node_groups" {
  description = "EKS node groups configuration"
  type = map(object({
    capacity_type  = string
    instance_types = list(string)
    disk_size      = number
    ami_type       = optional(string, "AL2_x86_64")
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    scaling_config = object({
      desired_size = number
      max_size     = number
      min_size     = number
    })
  }))
}

variable "enable_irsa" {
  description = "Determines whether to create an OpenID Connect provider for EKS"
  type        = bool
  default     = true
}

variable "eks_allowed_cidrs" {
  description = <<-EOT
    List of CIDRs allowed to access the EKS API server.
    Defaults to open for initial setup — restrict to known CIDRs
    (VPN, bastion, CI runner IPs) before moving to production.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_principal_arns" {
  description = "List of IAM user or role ARNs to grant EKS cluster admin access"
  type        = list(string)
  default     = []
}

variable "github_actions_role_arn" {
  description = "ARN of the IAM role used by GitHub Actions to access the EKS cluster"
  type        = string
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
