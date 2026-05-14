# Changelog

## v0.1.1
- Replaced repetitive count expressions with `local.irsa_ready` and `local.helm_ready`
- Tightened `required_version` constraint from `>= 1.0.0, < 2.0.0` to `~> 1.7.0`
- Added `aws_eks_addon.ebs_csi` to Loki `depends_on` — ensures CSI driver is ready before PVC provisioning
- Added `aws_eks_addon.ebs_csi` to kube-prometheus-stack `depends_on` — same reason
- Added `depends_on` to cluster-autoscaler Helm release — IAM role attachment must complete first
- Added `depends_on` to external-dns Helm release — LBC webhook must be ready first
- Added `metrics_server_insecure_tls` variable — replaces hardcoded `--kubelet-insecure-tls` arg
- Added missing checkov skips on cert-manager IAM policy
- Moved `vpc_id` variable to core cluster inputs section

## v0.1.0
- Added AWS Load Balancer Controller with IRSA
- Added External DNS with IRSA
- Added External Secrets with IRSA
- Added Cert Manager with IRSA
- Added EBS CSI Driver with gp3 StorageClass
- Added Metrics Server
- Added KEDA with IRSA for SQS and CloudWatch
- Added Loki stack with Promtail
- Added Kube Prometheus Stack with Grafana persistence
- Added `skip_helm_deployments` flag for bootstrapping IAM without Helm

## v0.0.2
- Updated provider version
- Added cluster autoscaler helm version variable
- Fixed typos
- Removed declared and unused `common_tags` variable
- Added OIDC mock value for tfvars

## v0.0.1
- Initial release
- Added Cluster Autoscaler with IRSA
- Added checkov suppress tags on cluster autoscaler IAM policy
- Widened Terraform core constraint to `>= 1.0.0, < 2.0.0`