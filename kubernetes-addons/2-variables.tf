variable "openid_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
  default     = null
}

variable "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  type        = string
}

variable "eks_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = true
}

variable "skip_helm_deployments" {
  description = "Skip helm deployments"
  type        = bool
  default     = false
}

variable "cluster_autoscaler_helm_version" {
  description = "Helm chart version for cluster autoscaler"
  type        = string

}
