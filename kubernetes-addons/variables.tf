############################
# Core Cluster Inputs
############################

variable "eks_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  type        = string
}

variable "openid_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
  default     = null
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

############################
# Global Flags
############################

variable "skip_helm_deployments" {
  description = "Skip helm deployments"
  type        = bool
  default     = false
}

############################
# Cluster Autoscaler
############################

variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = true
}

variable "cluster_autoscaler_helm_version" {
  description = "Helm chart version for cluster autoscaler"
  type        = string
}

############################
# AWS Load Balancer Controller
############################

variable "enable_aws_lbc" {
  description = "Enable AWS Load Balancer Controller"
  type        = bool
  default     = false
}

variable "aws_lbc_helm_version" {
  description = "Helm chart version for AWS Load Balancer Controller"
  type        = string
}

############################
# EBS CSI Driver
############################

variable "enable_ebs_csi_driver" {
  description = "Enable EBS CSI Driver addon"
  type        = bool
  default     = false
}

variable "ebs_csi_addon_version" {
  description = "Version of the EBS CSI Driver EKS addon"
  type        = string
}

############################
# Metrics Server
############################

variable "enable_metrics_server" {
  description = "Enable Metrics Server"
  type        = bool
  default     = false
}

variable "metrics_server_helm_version" {
  description = "Helm chart version for Metrics Server"
  type        = string
}

############################
# External Secrets
############################

variable "enable_external_secrets" {
  description = "Enable External Secrets Operator"
  type        = bool
  default     = false
}

variable "external_secrets_helm_version" {
  description = "Helm chart version for External Secrets Operator"
  type        = string
}

############################
# Cert Manager
############################

variable "enable_cert_manager" {
  description = "Enable Cert Manager"
  type        = bool
  default     = false
}

variable "cert_manager_helm_version" {
  description = "Helm chart version for Cert Manager"
  type        = string
}

############################
# External DNS
############################

variable "enable_external_dns" {
  description = "Enable External DNS"
  type        = bool
  default     = false
}

variable "external_dns_helm_version" {
  description = "Helm chart version for External DNS"
  type        = string
}

variable "external_dns_domain_filter" {
  description = "Domain filter for External DNS e.g. example.com"
  type        = string
  default     = ""
}

############################
# Monitoring (Prometheus + Grafana)
############################

variable "enable_kube_prometheus_stack" {
  description = "Enable Kube Prometheus Stack"
  type        = bool
  default     = false
}

variable "kube_prometheus_stack_helm_version" {
  description = "Helm chart version for Kube Prometheus Stack"
  type        = string
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = null
}

############################
# Logging (Loki)
############################

variable "enable_loki" {
  description = "Enable Loki Stack"
  type        = bool
  default     = false
}

variable "loki_helm_version" {
  description = "Helm chart version for Loki Stack"
  type        = string
}

############################
# AWS Load Balancer Controller
############################
variable "vpc_id" {
  description = "VPC ID for the EKS cluster, used by AWS Load Balancer Controller"
  type        = string
}