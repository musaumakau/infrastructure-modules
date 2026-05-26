# Tag module call — single source of truth for all tags in this stack.
# Every resource references module.tags.tags — never define tags ad hoc.
module "tags" {
  source = "../modules/tags"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  cost_center = var.cost_center
  module_name = "eks"
}
