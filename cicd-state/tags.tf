module "tags" {
  source = "../modules/tags"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  cost_center = var.cost_center
  module_name = "cicd-state"
}