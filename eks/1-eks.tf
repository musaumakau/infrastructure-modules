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
        Resource = "*" # ✅ FIXED: Changed from aws_kms_key.eks.arn to "*"
      },
      {
        Sid    = "AllowAccountAdminsFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:*"
        ]
        Resource = "*" # ✅ FIXED: Changed from aws_kms_key.eks.arn to "*"
      }
    ]
  })
}

resource "aws_eks_cluster" "this" {
  name     = "${var.env}-${var.eks_name}"
  role_arn = aws_iam_role.eks.arn
  version  = var.eks_version

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
  }

  depends_on = [aws_iam_role_policy_attachment.eks]
}
resource "aws_eks_access_entry" "local_admin" {
  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = data.aws_caller_identity.current.arn
  type              = "STANDARD"
  kubernetes_groups = ["system:masters"]

  tags = {
    Name = "${var.env}-${var.eks_name}-local-admin-access"
  }
}