data "aws_iam_policy_document" "cluster_autoscaler" {
  count = local.irsa_ready && var.enable_cluster_autoscaler ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }

    principals {
      identifiers = [var.openid_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  count              = local.irsa_ready && var.enable_cluster_autoscaler ? 1 : 0
  name               = "${var.eks_name}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler[0].json

  tags = merge(module.tags.tags, {
    Name     = "${var.eks_name}-cluster-autoscaler"
    EksAddon = "cluster-autoscaler"
  })
}

resource "aws_iam_policy" "cluster_autoscaler" {
  count = local.irsa_ready && var.enable_cluster_autoscaler ? 1 : 0
  name  = "${var.eks_name}-cluster-autoscaler"

  tags = merge(module.tags.tags, {
    Name                       = "${var.eks_name}-cluster-autoscaler"
    EksAddon                   = "cluster-autoscaler"
    "checkov:skip=CKV_AWS_355" = "Cluster Autoscaler requires wildcard for dynamic scaling"
    "checkov:skip=CKV_AWS_290" = "Necessary wildcard for EC2 and ASG describe actions"
  })

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeImages",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  count      = local.irsa_ready && var.enable_cluster_autoscaler ? 1 : 0
  role       = aws_iam_role.cluster_autoscaler[0].name
  policy_arn = aws_iam_policy.cluster_autoscaler[0].arn
}

resource "helm_release" "cluster_autoscaler" {
  count = local.irsa_ready && var.enable_cluster_autoscaler ? 1 : 0

  name       = "autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = var.cluster_autoscaler_helm_version

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler[0].arn
  }

  set {
    name  = "autoDiscovery.clusterName"
    value = var.eks_name
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_autoscaler]
}
