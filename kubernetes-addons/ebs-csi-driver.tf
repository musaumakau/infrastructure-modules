
data "aws_iam_policy_document" "ebs_csi" {
  count = var.enable_ebs_csi_driver && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    principals {
      identifiers = [var.openid_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  count              = var.enable_ebs_csi_driver && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  name               = "${var.eks_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi[0].json

  tags = {
    "eks_addon" = "ebs-csi-driver"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count      = var.enable_ebs_csi_driver && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  count                    = var.enable_ebs_csi_driver && var.openid_provider_arn != null && var.openid_provider_arn != "" ? 1 : 0
  cluster_name             = var.eks_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_addon_version
  service_account_role_arn = aws_iam_role.ebs_csi[0].arn

  depends_on = [aws_iam_role_policy_attachment.ebs_csi]

  tags = {
    "eks_addon" = "ebs-csi-driver"
  }
}