#AWS Load Balancer Controller IAM Role and Helm Chart Deployment
data "aws_iam_policy_document" "aws_lbc" {
  count = var.enable_aws_lbc && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    principals {
      identifiers = [var.openid_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "aws_lbc" {
  count              = var.enable_aws_lbc && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  name               = "${var.eks_name}-aws-lbc"
  assume_role_policy = data.aws_iam_policy_document.aws_lbc[0].json

  tags = {
    "eks_addon" = "aws-load-balancer-controller"
  }
}

resource "aws_iam_policy" "aws_lbc" {
  count  = var.enable_aws_lbc && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  name   = "${var.eks_name}-aws-lbc"
  policy = file("${path.module}/policies/aws-lbc-policy.json")

  tags = {
    "eks_addon" = "aws-load-balancer-controller"
  }
}

resource "aws_iam_role_policy_attachment" "aws_lbc" {
  count      = var.enable_aws_lbc && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  role       = aws_iam_role.aws_lbc[0].name
  policy_arn = aws_iam_policy.aws_lbc[0].arn
}

resource "helm_release" "aws_lbc" {
  count = var.skip_helm_deployments || !var.enable_aws_lbc || var.openid_provider_arn == null || var.openid_provider_arn == "" ? 0 : 1

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.aws_lbc_helm_version

  set {
    name  = "clusterName"
    value = var.eks_name
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.aws_lbc[0].arn
  }

  # Recommended for production stability
  set {
    name  = "replicaCount"
    value = "2"
  }

  set {
    name  = "podDisruptionBudget.maxUnavailable"
    value = "1"
  }

  depends_on = [aws_iam_role_policy_attachment.aws_lbc]
}