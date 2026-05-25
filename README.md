# Infrastructure Modules

Enterprise-grade Terraform modules with automated governance, cost controls, and policy enforcement.

[![Terraform](https://img.shields.io/badge/Terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)](https://terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![GitHub Actions](https://img.shields.io/badge/github%20actions-%232671E5.svg?style=for-the-badge&logo=githubactions&logoColor=white)](https://github.com/features/actions)
[![Infracost](https://img.shields.io/badge/Infracost-Cost%20Analysis-%2300B5E2.svg?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAyQzYuNDggMiAyIDYuNDggMiAxMnM0LjQ4IDEwIDEwIDEwIDEwLTQuNDggMTAtMTBTMTcuNTIgMiAxMiAyem0xIDE1aC0ydi02aDJ2NnptMC04aC0yVjdoMnYyeiIvPjwvc3ZnPg==&logoColor=white)](https://www.infracost.io/)
[![OPA](https://img.shields.io/badge/OPA-Policy%20as%20Code-%237D3C98.svg?style=for-the-badge&logo=openpolicyagent&logoColor=white)](https://www.openpolicyagent.org/)

## Overview

This repository contains production-ready Terraform modules with built-in governance, cost control, and security enforcement. Every infrastructure change is automatically validated against organisational policies before deployment.

**Key features:**
- Modular, versioned infrastructure components
- Automated cost analysis and budget enforcement
- Multi-layered security scanning and compliance checks
- Policy as Code with Open Policy Agent (OPA)
- GitOps workflow with cross-repo orchestration
- Mandatory tagging and naming conventions
- Dependabot-managed dependency updates

## Repository Structure

```
infrastructure-modules/
├── vpc/                          # VPC, subnets, NAT gateways, routing
├── eks/                          # EKS cluster with managed node groups
├── kubernetes-addons/            # Cluster autoscaler and essential add-ons
├── cicd-state/                   # Bootstrap resources for CI/CD state (S3, DynamoDB)
├── .infracost/
│   ├── infracost.yml             # Infracost configuration
│   └── policies/
│       ├── tagging.rego          # Tag enforcement policies
│       └── governance.rego       # Cost and security policies
├── .github/
│   ├── actions/                  # Composite actions for reusable setup logic
│   │   ├── terraform-setup/      # Terraform + Terragrunt install + plugin cache
│   │   ├── aws-auth/             # OIDC credential configuration
│   │   ├── scanner-install/      # tfsec + checkov + trivy install with caching
│   │   └── pr-comment/           # PR comment upsert utility
│   ├── scripts/
│   │   └── detect-changed-modules.sh
│   ├── workflows/                # CI/CD workflows
│   └── dependabot.yml            # Automated dependency updates
└── README.md
```

## Governance & Policies

### Required Resource Tags

All billable resources must include these tags:

| Tag | Description | Example | Format |
|---|---|---|---|
| `Environment` | Deployment environment | `dev` | `dev`, `staging`, `prod`, `test` |
| `Owner` | Resource owner or team email | `platform-team@company.com` | Non-placeholder value |
| `Project` | Business project name | `customer-portal` | Any non-empty string |
| `CostCenter` | Cost allocation code | `CC-1234` | `CC-XXXX` (4 digits) |

Empty tag values and placeholder Owner values (`admin`, `root`, `unknown`, `tbd`) are treated as policy violations.

### Cost Limits

Automated cost controls prevent budget overruns:

| Resource Type | Monthly Limit |
|---|---|
| `aws_instance` | $500 |
| `aws_rds_cluster` | $2,000 |
| `aws_eks_cluster` | $200 |
| `aws_eks_node_group` | $1,000 |
| `aws_db_instance` | $1,000 |

Resources approaching 80% of their limit trigger a warning. Total monthly cost across all projects exceeding $3,000 also triggers a warning.

### Security Policies

**Hard failures (deny):**
- EKS clusters must have private endpoint enabled
- EKS clusters must have `api`, `audit`, and `authenticator` log types enabled
- EKS node groups must not use `t2/t3.micro/small` instance types
- All EBS volumes must be encrypted
- EC2 instances must enforce IMDSv2 (`http_tokens = required`)
- No plaintext secrets in EC2 userdata
- Security groups must not allow unrestricted SSH (port 22) from `0.0.0.0/0`
- Security groups must not allow unrestricted RDP (port 3389) from `0.0.0.0/0`
- KMS keys must have key rotation enabled
- S3 buckets must have an accompanying `aws_s3_bucket_public_access_block` resource
- S3 bucket names must follow naming conventions (lowercase, alphanumeric, dots, hyphens)

**Advisory warnings:**
- EKS clusters with public endpoint enabled
- EKS prod/staging clusters missing `protected` tag
- Production-sized instances deployed in dev environment
- RDS instances that are publicly accessible
- RDS instances without `deletion_protection` enabled
- IAM roles with wildcard principal in assume role policy
- VPC deployed without accompanying `aws_flow_log` resource
- Subnets with `map_public_ip_on_launch` enabled
- Helm releases with timeout exceeding 600 seconds
- Large instance types (`m5.4xlarge` and above)

## Available Modules

### VPC (`vpc/`)

Complete networking setup with public/private subnets, NAT gateways, and VPC flow logs.

**Resources created:** VPC, public and private subnets across AZs, Internet Gateway, NAT Gateways, route tables, security groups, VPC Flow Logs.

```hcl
module "vpc" {
  source = "git::https://github.com/musaumakau/infrastructure-modules.git//vpc?ref=vpc-v0.0.2"

  cidr_block         = "10.0.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b"]

  tags = {
    Environment = "prod"
    Owner       = "platform-team@company.com"
    Project     = "core-infrastructure"
    CostCenter  = "CC-1001"
  }
}
```

### EKS (`eks/`)

Production-ready EKS cluster with managed node groups and IRSA support.

**Resources created:** EKS cluster, managed node groups with auto-scaling, IAM roles and policies, IRSA configuration, cluster security groups.

```hcl
module "eks" {
  source = "git::https://github.com/musaumakau/infrastructure-modules.git//eks?ref=eks-v0.0.2"

  cluster_name    = "production-cluster"
  cluster_version = "1.33"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids

  node_groups = {
    main = {
      instance_types = ["m5.large"]
      min_size       = 1
      max_size       = 10
      desired_size   = 3
    }
  }
}
```

### Kubernetes Add-ons (`kubernetes-addons/`)

Essential cluster add-ons for production workloads.

**Add-ons included:**
- **AWS Load Balancer Controller** — provisions ALB/NLB resources from Kubernetes ingress/service objects
- **Cert Manager** — automates TLS certificate provisioning and renewal via Let's Encrypt or ACM
- **Cluster Autoscaler** — automatically adjusts node group size based on pending pods
- **AWS EBS CSI Driver** — enables dynamic provisioning of EBS volumes as persistent storage
- **External DNS** — synchronises Route53 records with Kubernetes ingress and service resources
- **External Secrets** — syncs secrets from AWS Secrets Manager and SSM Parameter Store into Kubernetes
- **KEDA** — event-driven autoscaling for workloads based on external metrics (SQS, Kafka, etc.)
- **Kube Prometheus Stack** — full observability stack including Prometheus, Alertmanager, and Grafana
- **Loki** — log aggregation and querying, integrated with the Grafana stack
- **Metrics Server** — provides resource utilisation data for HPA and `kubectl top`

### CI/CD State (`cicd-state/`)

Bootstrap module for CI/CD state resources. Manages the S3 bucket and DynamoDB table used for Terraform remote state and plan manifests. This module is excluded from automated plans — changes require manual review and apply.

## CI/CD Pipeline

### Architecture

The pipeline uses reusable workflows and composite actions to eliminate duplication and maximise parallelism. All jobs run on GitHub-hosted runners with OIDC-based AWS authentication — no long-lived credentials anywhere.

```
.github/
├── actions/
│   ├── terraform-setup/          # Terraform + Terragrunt install + plugin cache
│   ├── aws-auth/                 # OIDC credential configuration
│   ├── scanner-install/          # tfsec + checkov + trivy install with caching
│   └── pr-comment/               # PR comment upsert utility
└── workflows/
    ├── terraform-ci.yml               # Orchestrator
    ├── infracost-baseline.yml         # Cost baseline update on merge to main
    ├── reusable-validate.yml          # Terraform fmt + validate + TFLint
    ├── reusable-security-scan.yml     # tfsec × checkov × trivy matrix
    ├── reusable-plan-and-score.yml    # Terragrunt plan + blast radius scoring
    ├── reusable-infracost.yml         # Cost analysis + OPA policy evaluation
    └── reusable-dispatch.yml          # Auto-tag + infrastructure-live trigger
```

### Pull Request Workflow

Every PR triggers the following stages in order:

1. **Secret scan** — Gitleaks scans full commit history before anything else runs
2. **Changed module detection** — only affected modules proceed; docs-only changes are skipped
3. **Validate** — `terraform fmt`, `terraform validate`, TFLint (parallel per changed module)
4. **Security scan** — tfsec, checkov, trivy (parallel: 3 scanners × changed modules) with SARIF upload to the Security tab
5. **Plan & blast radius** — Terragrunt speculative plan, risk scoring, S3 manifest upload
6. **Cost & policy** — Infracost diff against base branch, OPA tagging + governance evaluation

### Push to Main Workflow

On merge to main:

1. Secret scan
2. Changed module detection
3. Validate
4. Plan & blast radius
5. Auto-tag changed modules from CHANGELOG.md versions
6. Trigger `infrastructure-live` deployment via `repository_dispatch`
7. Update Infracost cost baseline in S3

### Blast Radius Scoring

Every plan is scored before merge to catch high-risk changes:

| Score | Risk Level | Action |
|---|---|---|
| 0–30 | LOW | Auto-approved |
| 31–150 | ELEVATED | Review carefully |
| 150+ | BLOCKED | Requires `blast-radius-override: <reason>` in PR body |

### Cross-Repository Integration

This repository integrates with [`infrastructure-live`](https://github.com/musaumakau/infrastructure-live) for environment-specific Terragrunt deployments:

```
Developer PR → Policy Validation → Blast Radius Check → Merge to Main
                                                              │
                                                              ▼
                                               infrastructure-live (Dev → Staging → Prod)
```

## Dependency Management

Dependencies are automatically managed by [Dependabot](.github/dependabot.yml), which opens weekly PRs for outdated dependencies every Monday.

### What Dependabot tracks

| Ecosystem | Scope | Schedule |
|---|---|---|
| GitHub Actions | All workflow action versions | Weekly |
| Terraform | Provider version constraints per module | Weekly |

### How to handle Dependabot PRs

Every Dependabot PR runs the full pipeline automatically. Use the results to guide your decision:

- **Patch version bumps** — safe to merge after pipeline passes
- **Minor bumps** — read the changelog, merge if no breaking changes
- **Major version bumps** — read the migration guide; treat like any significant change
- **`aquasecurity/trivy`** — never auto-merge; manually verify releases due to supply chain attack history. Check the [release page](https://github.com/aquasecurity/trivy/releases) directly
- **`hashicorp/aws` major bumps** — likely contains breaking changes requiring module updates

To trigger a manual rebase on a Dependabot PR, comment `@dependabot rebase`.

## Quick Start

### Prerequisites

- Terraform >= 1.7.0
- AWS CLI configured with appropriate permissions
- Git access to both `infrastructure-modules` and `infrastructure-live`

### Steps

```bash
# Clone the repository
git clone https://github.com/musaumakau/infrastructure-modules.git
cd infrastructure-modules

# Create a feature branch
git checkout -b feat/your-change

# Make changes, then test locally
cd vpc/
terraform init
terraform plan -var-file=terraform.tfvars.example

# Push and open a PR — the pipeline runs automatically
git push origin feat/your-change
```

## Development

### Adding New Modules

1. Create the module directory following the naming convention:
   ```
   0-versions.tf              # Provider requirements
   1-main.tf                  # Primary resources
   2-variables.tf             # Input variables
   3-outputs.tf               # Output values
   terraform.tfvars.example   # Example configuration
   CHANGELOG.md               # Version history
   ```

2. Include required tags on all resources:
   ```hcl
   tags = merge(var.tags, {
     Name = "resource-specific-name"
   })
   ```

3. If new resource types are introduced, add them to `.infracost/policies/tagging.rego`'s
   `taggable_resources` set and update `governance.rego` if cost limits apply.

4. Add the module to `.github/scripts/detect-changed-modules.sh` so it is included
   in the pipeline matrix.

### Module Versioning

Releases are tagged per module using semantic versioning. The pipeline auto-tags on merge
when a CHANGELOG.md version is updated:

```bash
# Manual tag if needed
git tag -a vpc-v1.2.3 -m "VPC module: add VPC flow logs"
git push origin vpc-v1.2.3
```

### Testing Changes Locally

```bash
# Validate syntax
terraform validate

# Check formatting
terraform fmt -check -recursive

# Run security scan
checkov -d . --framework terraform

# Test OPA policies
opa eval \
  --data .infracost/policies/tagging.rego \
  --input tfplan.json \
  --format raw \
  'count(data.infracost.policies.tagging.deny)'
```

## Configuration

### GitHub Actions Secrets

| Secret | Description |
|---|---|
| `INFRACOST_API_KEY` | Infracost API access for cost estimation |
| `REPO_DISPATCH_PAT` | PAT for cross-repo checkout and `repository_dispatch` to `infrastructure-live` |
| `GRAFANA_ADMIN_PASSWORD` | Passed through to Terragrunt plan for kubernetes-addons |
| `GITLEAKS_LICENSE` | Gitleaks license key (free for public repos) |

### Repository Variables

| Variable | Description |
|---|---|
| `PLAN_MANIFEST_BUCKET` | S3 bucket name for plan manifests and Infracost baselines |

### AWS Authentication

All workflows use OIDC for keyless authentication — no long-lived AWS credentials are stored as secrets:

```yaml
- uses: aws-actions/configure-aws-credentials@<sha>
  with:
    role-to-assume: arn:aws:iam::649203810550:role/EksOIDCRole
    aws-region: eu-west-1
```

## Troubleshooting

**Policy validation fails**

```bash
# Check policy syntax
opa fmt .infracost/policies/tagging.rego
opa fmt .infracost/policies/governance.rego

# Test tagging policy locally
opa eval \
  --data .infracost/policies/tagging.rego \
  --input tfplan.json \
  --format raw \
  'count(data.infracost.policies.tagging.deny)'

# Test governance policy locally
opa eval \
  --data .infracost/policies/governance.rego \
  --input tfplan.json \
  --format raw \
  'count(data.infracost.policies.governance.deny)'
```

**Missing required variables**

```bash
cp terraform.tfvars.example terraform.tfvars
terraform validate
```

**Cost analysis errors**

```bash
infracost breakdown --config-file=.infracost/infracost.yml --dry-run
```

**Blast radius blocked**

Add an override to your PR description:
```
blast-radius-override: deploying new node group, reviewed and approved
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feat/amazing-feature`)
5. Open a Pull Request

**Guidelines:**
- Follow existing code structure and naming conventions
- Include comprehensive variable descriptions
- Add example tfvars for new modules
- Update documentation for any new features
- Ensure all resources include the required tags
- Test changes locally before submitting a PR

## Additional Resources

- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Open Policy Agent Documentation](https://www.openpolicyagent.org/docs/)
- [Infracost Documentation](https://www.infracost.io/docs/)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/musaumakau/infrastructure-modules/issues)
- **Discussions**: [GitHub Discussions](https://github.com/musaumakau/infrastructure-modules/discussions)