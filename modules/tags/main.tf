# Tag enforcement module
# This module is the single source of truth for all resource tags.
# It validates required inputs, computes governed tags (ManagedBy, TerraformModule),
# and outputs a guaranteed-compliant tag map for injection into every resource.
#
# Usage:
#   module "tags" {
#     source      = "../modules/tags"
#     project     = var.project
#     environment = var.environment
#     owner       = var.owner
#     cost_center = var.cost_center
#     module_name = "vpc"
#   }
#
#   tags = merge(module.tags.tags, { Name = "${var.env}-resource" })
