
resource "helm_release" "metrics_server" {
  count = var.skip_helm_deployments || !var.enable_metrics_server ? 0 : 1

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = var.metrics_server_helm_version

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
}