# This file defines the resources for deploying External DNS as an EKS addon using Helm.

data "aws_iam_policy_document" "external_dns" {
  count = local.irsa_ready && var.enable_external_dns ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-dns:external-dns"]
    }

    principals {
      identifiers = [var.openid_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "external_dns" {
  count              = local.irsa_ready && var.enable_external_dns ? 1 : 0
  name               = "${var.eks_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns[0].json

  tags = merge(module.tags.tags, {
    Name     = "${var.eks_name}-external-dns"
    EksAddon = "external-dns"
  })
}

resource "aws_iam_policy" "external_dns" {
  count = local.irsa_ready && var.enable_external_dns ? 1 : 0
  name  = "${var.eks_name}-external-dns"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(module.tags.tags, {
    Name                       = "${var.eks_name}-external-dns"
    EksAddon                   = "external-dns"
    "checkov:skip=CKV_AWS_355" = "External DNS requires wildcard to list all hosted zones"
    "checkov:skip=CKV_AWS_290" = "External DNS requires wildcard for Route53 list actions"
  })
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  count      = local.irsa_ready && var.enable_external_dns ? 1 : 0
  role       = aws_iam_role.external_dns[0].name
  policy_arn = aws_iam_policy.external_dns[0].arn
}

resource "helm_release" "external_dns" {
  count = local.irsa_ready && var.enable_external_dns ? 1 : 0

  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  namespace        = "external-dns"
  version          = var.external_dns_helm_version
  create_namespace = true

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns[0].arn
  }

  set {
    name  = "domainFilters[0]"
    value = var.external_dns_domain_filter
  }

  depends_on = [aws_iam_role_policy_attachment.external_dns, helm_release.aws_lbc]
}
