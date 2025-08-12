
resource "aws_iam_role" "eks" {
  name               = "${var.env}-${var.eks_name}-eks-cluster"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks.name
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS secrets encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "eks-key-policy"
    Statement = [
      {
        Sid    = "AllowEKSRoleUseOfTheKey"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.eks.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowAccountAdminsFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = ["kms:*"]
        Resource = "*"
      }
    ]
  })
}

# Security Groups
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.env}-${var.eks_name}-cluster-"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.env}-${var.eks_name}-cluster-sg"
  }
}

resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.env}-${var.eks_name}-nodes-"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.env}-${var.eks_name}-nodes-sg"
  }
}

# Security Group Rules
resource "aws_security_group_rule" "cluster_ingress_from_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_cluster.id
  description              = "HTTPS from worker nodes"
}

resource "aws_security_group_rule" "cluster_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_cluster.id
  description       = "All outbound traffic"

  #checkov:skip=CKV_AWS_277: "0.0.0.0/0 egress required for EKS cluster API access and AWS service communication"
  #checkov:skip=CKV_AWS_382: "All protocols egress required for EKS cluster to communicate with AWS services and download container images"

}

resource "aws_security_group_rule" "nodes_ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Node to node communication"

  #checkov:skip=CKV_AWS_24: "Wide port range required for inter-node communication in EKS"
}

resource "aws_security_group_rule" "nodes_ingress_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
  description              = "Cluster API to node kubelets"
}

resource "aws_security_group_rule" "nodes_ingress_cluster_api" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
  description              = "Cluster API to node communication"

  #checkov:skip=CKV_AWS_24: "Wide port range required for cluster to node communication in EKS"
}

resource "aws_security_group_rule" "nodes_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_nodes.id
  description       = "All outbound traffic"

  #checkov:skip=CKV_AWS_277: "0.0.0.0/0 egress required for container image pulls, AWS API access, and package downloads"
  #checkov:skip=CKV_AWS_382: "All protocols egress required for EKS nodes to communicate with AWS services and download container images"
}



resource "aws_eks_cluster" "this" {
  name     = "${var.env}-${var.eks_name}"
  role_arn = aws_iam_role.eks.arn
  version  = var.eks_version

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  tags = {
    "checkov:skip=CKV_AWS_39" = "Public endpoint needed for CI/CD and remote management"
    "checkov:skip=CKV_AWS_38" = "Public access from anywhere required for external access"
  }

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.eks_allowed_cidrs
    subnet_ids              = var.subnet_ids
    security_group_ids = [
      aws_security_group.eks_cluster.id,
      aws_security_group.eks_nodes.id
    ]
  }

  depends_on = [aws_iam_role_policy_attachment.eks]
}

resource "aws_eks_access_entry" "local_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = "arn:aws:iam::649203810550:user/Kay"
  type          = "STANDARD"

  tags = {
    Name = "${var.env}-${var.eks_name}-local-admin-access"
  }
}

resource "aws_eks_access_policy_association" "local_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = "arn:aws:iam::649203810550:user/Kay"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.local_admin]
}
