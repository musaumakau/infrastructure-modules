data "aws_iam_policy_document" "cert_manager" {
  count = local.irsa_ready && var.enable_cert_manager ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:cert-manager:cert-manager"]
    }

    principals {
      identifiers = [var.openid_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "cert_manager" {
  count              = local.irsa_ready && var.enable_cert_manager ? 1 : 0
  name               = "${var.eks_name}-cert-manager"
  assume_role_policy = data.aws_iam_policy_document.cert_manager[0].json

  tags = merge(module.tags.tags, {
    Name     = "${var.eks_name}-cert-manager"
    EksAddon = "cert-manager"
  })
}

resource "aws_iam_policy" "cert_manager" {
  count = local.irsa_ready && var.enable_cert_manager ? 1 : 0
  name  = "${var.eks_name}-cert-manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZonesByName"]
        Resource = "*"
      }
    ]
  })

  tags = merge(module.tags.tags, {
    Name                       = "${var.eks_name}-cert-manager"
    EksAddon                   = "cert-manager"
    "checkov:skip=CKV_AWS_355" = "cert-manager requires wildcard to list hosted zones"
    "checkov:skip=CKV_AWS_290" = "route53:ListHostedZonesByName requires wildcard resource"
  })
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  count      = local.irsa_ready && var.enable_cert_manager ? 1 : 0
  role       = aws_iam_role.cert_manager[0].name
  policy_arn = aws_iam_policy.cert_manager[0].arn
}

resource "helm_release" "cert_manager" {
  count = local.irsa_ready && var.enable_cert_manager ? 1 : 0

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  version          = var.cert_manager_helm_version
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cert_manager[0].arn
  }

  depends_on = [aws_iam_role_policy_attachment.cert_manager, helm_release.aws_lbc]
}
