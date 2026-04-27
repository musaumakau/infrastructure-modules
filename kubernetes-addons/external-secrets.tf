
data "aws_iam_policy_document" "external_secrets" {
  count = var.enable_external_secrets && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }

    principals {
      identifiers = [var.openid_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  count              = var.enable_external_secrets && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  name               = "${var.eks_name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.external_secrets[0].json

  tags = {
    "eks_addon" = "external-secrets"
  }
}

resource "aws_iam_policy" "external_secrets" {
  count = var.enable_external_secrets && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  name  = "${var.eks_name}-external-secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/*"
      }
    ]
  })

  tags = {
    "eks_addon" = "external-secrets"
  }
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  count      = var.enable_external_secrets && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  role       = aws_iam_role.external_secrets[0].name
  policy_arn = aws_iam_policy.external_secrets[0].arn
}

resource "helm_release" "external_secrets" {
  count = var.skip_helm_deployments || !var.enable_external_secrets || var.openid_provider_arn == null || var.openid_provider_arn == "" ? 0 : 1

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  version          = var.external_secrets_helm_version
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_secrets[0].arn
  }

  depends_on = [aws_iam_role_policy_attachment.external_secrets]
}