variable "project" {
  description = "Project name"
  type        = string

  validation {
    condition     = length(var.project) > 0
    error_message = "project must not be empty."
  }
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "ci-mock"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, ci-mock."
  }
}

variable "owner" {
  description = "Team or individual responsible for the resources"
  type        = string

  validation {
    condition     = length(var.owner) > 0
    error_message = "owner must not be empty."
  }
}

variable "cost_center" {
  description = "Cost center for billing and chargeback"
  type        = string

  validation {
    condition     = length(var.cost_center) > 0
    error_message = "cost_center must not be empty."
  }
}

variable "module_name" {
  description = "Name of the calling stack — used for the TerraformModule tag"
  type        = string

  validation {
    condition     = length(var.module_name) > 0
    error_message = "module_name must not be empty."
  }
}

variable "extra_tags" {
  description = "Optional additional tags to merge into the tag map"
  type        = map(string)
  default     = {}
}
