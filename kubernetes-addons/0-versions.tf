terraform {
  required_version = "~> 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.62"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
  }
}
