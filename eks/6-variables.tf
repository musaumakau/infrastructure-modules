variable "env" {
  description = "Environment name"
  type        = string

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
  description = "List of subnets IDS, must be in at least two different availability zones"
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
  description = "EKS node groups"
  type        = map(any)

}

variable "enable_irsa" {
  description = "Dertimines whether to create an OpenID Connect provider for EKS"
  type        = bool
  default     = true

}
variable "eks_allowed_cidrs" {
  description = "List of CIDRs that are allowed to access the EKS cluster"
  type        = list(string)

  default     = ["0.0.0.0/0"] # This allows access from anywhere, adjust as needed for security


}