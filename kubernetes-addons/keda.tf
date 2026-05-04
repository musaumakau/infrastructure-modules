data "aws_iam_policy_document" "keda" {
  count = var.enable_keda && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:keda:keda-operator"]
    }

    principals {
      identifiers = [var.openid_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "keda" {
  count              = var.enable_keda && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  name               = "${var.eks_name}-keda"
  assume_role_policy = data.aws_iam_policy_document.keda[0].json

  tags = {
    "eks_addon" = "keda"
  }
}

resource "aws_iam_policy" "keda" {
  count = var.enable_keda && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  name  = "${var.eks_name}-keda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ListQueues",
          "sqs:ListDeadLetterSourceQueues",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    "eks_addon" = "keda"
  }
}

resource "aws_iam_role_policy_attachment" "keda" {
  count      = var.enable_keda && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  role       = aws_iam_role.keda[0].name
  policy_arn = aws_iam_policy.keda[0].arn
}

resource "helm_release" "keda" {
  count = var.skip_helm_deployments || !var.enable_keda || var.openid_provider_arn == null || var.openid_provider_arn == "" ? 0 : 1

  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  version          = var.keda_helm_version
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.keda[0].arn
  }

  set {
    name  = "podIdentity.aws.irsa.enabled"
    value = "true"
  }

  depends_on = [aws_iam_role_policy_attachment.keda, helm_release.aws_lbc]
}