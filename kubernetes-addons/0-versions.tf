terraform {
  required_version = "~> 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

# Provider-level default tags act as a safety net —
# any resource that doesn't explicitly set tags still gets the full tag map.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = module.tags.tags
  }
}
