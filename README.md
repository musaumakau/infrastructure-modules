# Infrastructure Modules

This repository contains reusable Terraform modules for AWS infrastructure provisioning. These modules are designed to be consumed by Terragrunt configurations in the `infrastructure-live` repository.

## 📁 Repository Structure

```
infrastructure-modules/
├── vpc/
│   ├── 0-provider.tf          # Provider configuration
│   ├── 1-vpc.tf               # Main VPC resource
│   ├── 2-igw.tf               # Internet Gateway
│   ├── 3-subnets.tf           # Public & Private subnets
│   ├── 4-nat.tf               # NAT Gateways
│   ├── 5-routes.tf            # Route tables & routes
│   ├── 6-outputs.tf           # Module outputs
│   ├── 7-variables.tf         # Input variables
│   └── 8-vpc-flowlogs.tf      # VPC Flow Logs
├── eks/
│   ├── 0-versions.tf          # Provider versions
│   ├── 1-eks.tf               # EKS cluster & control plane
│   ├── 2-nodes-iam.tf         # Node group IAM roles
│   ├── 3-nodes.tf             # Managed node groups
│   ├── 4-irsa.tf              # IAM Roles for Service Accounts
│   ├── 5-outputs.tf           # Module outputs
│   └── 6-variables.tf         # Input variables
└── kubernetes-addons/
    ├── 0-versions.tf          # Provider versions
    ├── 1-cluster-autoscaler.tf # Cluster Autoscaler addon
    └── 2-variables.tf         # Input variables
```

## 🎯 Module Design Philosophy

This repository follows a **numbered file structure** for better organization and readability:

- **0-**: Configuration files (providers, versions)
- **1-**: Core resources (main infrastructure components)
- **2-**: Supporting resources (IAM, security)
- **3-**: Additional resources (node groups, networking)
- **4-**: Advanced features (IRSA, monitoring)
- **5-**: Outputs (for module consumers)
- **6-**: Variables (inputs and validation)
- **7-**: Variables (additional inputs)
- **8-**: Monitoring and logging

This structure makes it easy to:
- **Navigate** large modules quickly
- **Understand dependencies** between resources
- **Maintain** and update specific components
- **Review** changes in logical order

### VPC Module (`./vpc`)
Creates a production-ready VPC with organized file structure:
- **0-provider.tf**: AWS provider configuration
- **1-vpc.tf**: Main VPC resource with CIDR configuration
- **2-igw.tf**: Internet Gateway for public internet access
- **3-subnets.tf**: Public and private subnets across multiple AZs
- **4-nat.tf**: NAT Gateways for private subnet internet access
- **5-routes.tf**: Route tables and routing configuration
- **6-outputs.tf**: VPC outputs for other modules
- **7-variables.tf**: Input variables and validation
- **8-vpc-flowlogs.tf**: VPC Flow Logs for network monitoring

### EKS Module (`./eks`)
Creates a secure EKS cluster with comprehensive configuration:
- **0-versions.tf**: Terraform and provider version constraints
- **1-eks.tf**: EKS control plane, security groups, and encryption
- **2-nodes-iam.tf**: IAM roles and policies for worker nodes
- **3-nodes.tf**: Managed node groups configuration
- **4-irsa.tf**: IAM Roles for Service Accounts (IRSA) setup
- **5-outputs.tf**: EKS cluster outputs (name, endpoint, etc.)
- **6-variables.tf**: Input variables for cluster configuration

### Kubernetes Addons Module (`./kubernetes-addons`)
Installs essential Kubernetes addons:
- **0-versions.tf**: Provider version constraints for Helm/K8s
- **1-cluster-autoscaler.tf**: Cluster Autoscaler Helm deployment
- **2-variables.tf**: Variables for addon configuration

**Currently includes:**
- Cluster Autoscaler for automatic node scaling
- Ready for additional addons (ALB Controller, etc.)

## 🔧 Usage

These modules are not meant to be used directly. Instead, they should be consumed via Terragrunt in the `infrastructure-live` repository.

Example Terragrunt configuration:
```hcl
terraform {
  source = "git::https://github.com/your-org/infrastructure-modules.git//vpc?ref=v1.0.0"
}

inputs = {
  env = "Dev"
  vpc_cidr = "10.0.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.16.0/20", "10.0.32.0/20"]
}
```

## 🏷️ Versioning

This repository follows semantic versioning. Use specific tags/releases in your Terragrunt configurations:

- `v1.0.0` - Initial stable release
- `v1.1.0` - Added EKS access entries
- `v1.2.0` - Updated to EKS 1.33

## 🔒 Security Features

- **Encryption**: EKS secrets encryption with KMS
- **Network Security**: Security groups with minimal required access
- **Access Control**: RBAC with least privilege principles
- **Logging**: Comprehensive CloudWatch logging
- **Compliance**: Follows AWS security best practices

## 🚀 CI/CD Integration

Changes to this repository automatically trigger deployments in the `infrastructure-live` repository via GitHub Actions and repository dispatch events.

## 📋 Requirements

- Terraform >= 1.7.0
- AWS Provider >= 5.0
- Kubernetes Provider >= 2.20
- Helm Provider >= 2.10

## 🤝 Contributing

1. Create a feature branch from `main`
2. Make your changes
3. Update module versions if needed
4. Test with a dev environment
5. Submit a pull request

## 📚 Documentation

For detailed usage examples and advanced configurations, see the individual module README files:
- [VPC Module](./vpc/README.md)
- [EKS Module](./eks/README.md)
- [Kubernetes Addons Module](./kubernetes-addons/README.md)

## 🐛 Issues

Report issues in this repository. Include:
- Module name and version
- Terraform/Terragrunt versions
- Error messages and logs
- Steps to reproduce