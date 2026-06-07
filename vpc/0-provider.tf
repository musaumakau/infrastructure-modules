terraform {
  required_version = "~> 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.49.0"
    }
  }
}

# Provider-level default tags act as a safety net —
# any resource that doesn't explicitly set tags still gets the full tag map.
provider "aws" {
  region = var.region

  default_tags {
    tags = module.tags.tags
  }
}
