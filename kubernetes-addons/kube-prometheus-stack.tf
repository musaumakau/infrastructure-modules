
resource "helm_release" "kube_prometheus_stack" {
  count = var.skip_helm_deployments || !var.enable_kube_prometheus_stack ? 0 : 1

  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  version          = var.kube_prometheus_stack_helm_version
  create_namespace = true
  timeout          = 600

  set {
    name  = "grafana.persistence.enabled"
    value = "true"
  }

  set {
    name  = "grafana.persistence.size"
    value = "10Gi"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "20Gi"
  }

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
}