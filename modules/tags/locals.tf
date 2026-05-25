locals {
  # Tags the caller must supply — validated at input level via variables.tf
  required_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
  }

  # Tags the module computes automatically — caller never sets these
  # Placed last in merge so they always win and cannot be overridden
  computed_tags = {
    ManagedBy       = "terraform"
    TerraformModule = var.module_name
  }

  # Final tag map: extra_tags < required_tags < computed_tags
  # computed_tags always wins to guarantee governance compliance
  all_tags = merge(var.extra_tags, local.required_tags, local.computed_tags)
}
