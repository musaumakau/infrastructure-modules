# -----------------------------------------------
# Loki Stack - No IRSA needed
# -----------------------------------------------
resource "helm_release" "loki" {
  count = var.skip_helm_deployments || !var.enable_loki ? 0 : 1

  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  namespace        = "monitoring"
  version          = var.loki_helm_version
  create_namespace = true

  set {
    name  = "loki.persistence.enabled"
    value = "true"
  }

  set {
    name  = "loki.persistence.size"
    value = "10Gi"
  }

  set {
    name  = "promtail.enabled"
    value = "true"
  }

  set {
    name  = "grafana.enabled"
    value = "false"
  }

  depends_on = [
    helm_release.kube_prometheus_stack,
    aws_eks_addon.ebs_csi,            # EBS CSI must be ready before Loki PVC can provision
  ]
}