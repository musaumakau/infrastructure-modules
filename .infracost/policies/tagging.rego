package infracost.policies.tagging

import rego.v1

# Required tags
required_tags := {
    "Environment",
    "Owner",
    "Project",
    "CostCenter",
}

# Resources that must be tagged
taggable_resources := {
    "aws_instance",
    "aws_db_instance",
    "aws_rds_cluster",
    "aws_rds_cluster_instance",
    "aws_s3_bucket",
    "aws_lambda_function",
    "aws_ecs_service",
    "aws_ecs_cluster",
    "aws_eks_cluster",
    "aws_eks_node_group",
    "aws_elasticache_cluster",
    "aws_elasticache_replication_group",
    "aws_elasticsearch_domain",
    "aws_opensearch_domain",
    "aws_elb",
    "aws_lb",
    "aws_nat_gateway",
    "aws_eip",
    "aws_security_group",
    "aws_vpc",
    "aws_subnet",
    "aws_internet_gateway",
    "aws_route_table",
    "aws_kms_key",
    "aws_iam_role",
    "helm_release",
}

placeholder_owner_values := {
    "admin", "root", "unknown", "tbd", "test", "user", "n/a", "none",
}

valid_environments := {
    "dev", "staging", "prod", "test", "ci-mock",
}

# Helper functions

get_resource_address(resource) := resource.address if { resource.address }
get_resource_address(resource) := sprintf("%s.%s", [resource.type, resource.name]) if {
    not resource.address
    resource.type
    resource.name
}

get_resource_type(resource) := resource.resource_type if { resource.resource_type }
get_resource_type(resource) := resource.type if {
    resource.type
    not resource.resource_type
}

# get_resource_tags resolves tags in priority order:
# 1. resource.tags                    — Infracost format
# 2. resource.change.after.tags_all   — Terraform plan format, includes provider default_tags
# 3. resource.change.after.tags       — Terraform plan format, explicit resource tags only
# 4. resource.values.tags             — Terraform state format
# 5. {}                               — fallback, no tags found
#
# tags_all is checked before tags because provider default_tags (from the aws provider block)
# are merged into tags_all by Terraform but are NOT present in tags alone.
# Without checking tags_all, resources that rely on provider default_tags appear untagged to OPA.

get_resource_tags(resource) := resource.tags if {
    resource.tags
}

get_resource_tags(resource) := resource.change.after.tags_all if {
    not resource.tags
    resource.change.after.tags_all
}

get_resource_tags(resource) := resource.change.after.tags if {
    not resource.tags
    not resource.change.after.tags_all
    resource.change.after.tags
}

get_resource_tags(resource) := resource.values.tags if {
    not resource.tags
    not resource.change.after.tags_all
    not resource.change.after.tags
    resource.values.tags
}

get_resource_tags(resource) := {} if {
    not resource.tags
    not resource.change.after.tags_all
    not resource.change.after.tags
    not resource.values.tags
}

resource_requires_tags(resource) if {
    t := get_resource_type(resource)
    t in taggable_resources
}

has_required_tags(resource) if {
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)
    every tag in required_tags {
        tag in resource_tags
        resource_tags[tag] != ""
        resource_tags[tag] != null
    }
}


# DENY: Missing required tags — Infracost format

deny[msg] if {
    project := input.projects[_]
    resource := project.breakdown.resources[_]
    resource_requires_tags(resource)
    not has_required_tags(resource)

    resource_tags := get_resource_tags(resource)
    missing_tags := required_tags - object.keys(resource_tags)
    address := get_resource_address(resource)

    msg := {
        "msg": sprintf("Resource %s is missing required tags: %s", [
            address, concat(", ", missing_tags)
        ]),
        "resource": address,
        "resource_type": get_resource_type(resource),
        "missing_tags": missing_tags,
    }
}

     
# DENY: Missing required tags — Terraform plan format
     

deny[msg] if {
    resource := input.resource_changes[_]
    resource_requires_tags(resource)
    not has_required_tags(resource)

    resource_tags := get_resource_tags(resource)
    missing_tags := required_tags - object.keys(resource_tags)
    address := get_resource_address(resource)

    msg := {
        "msg": sprintf("Resource %s is missing required tags: %s", [
            address, concat(", ", missing_tags)
        ]),
        "resource": address,
        "resource_type": get_resource_type(resource),
        "missing_tags": missing_tags,
    }
}

     
# DENY: Empty tag values — Infracost format
     

deny[msg] if {
    project := input.projects[_]
    resource := project.breakdown.resources[_]
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)

    some tag in required_tags
    tag in resource_tags
    resource_tags[tag] in {"", null}

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Resource %s has empty value for required tag: %s", [address, tag]),
        "resource": address,
        "resource_type": get_resource_type(resource),
        "empty_tag": tag,
    }
}

     
# DENY: Empty tag values — Terraform plan format
     

deny[msg] if {
    resource := input.resource_changes[_]
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)

    some tag in required_tags
    tag in resource_tags
    resource_tags[tag] in {"", null}

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Resource %s has empty value for required tag: %s", [address, tag]),
        "resource": address,
        "resource_type": get_resource_type(resource),
        "empty_tag": tag,
    }
}

     
# WARN: Non-standard Environment value — Infracost format
     

warn[msg] if {
    project := input.projects[_]
    resource := project.breakdown.resources[_]
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)

    "Environment" in resource_tags
    environment := resource_tags.Environment
    not environment in valid_environments

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Resource %s has non-standard Environment tag value: '%s'. Expected: dev, staging, prod, test, or ci-mock", [
            address, environment
        ]),
        "resource": address,
        "environment_value": environment,
    }
}

     
# WARN: Non-standard Environment value — Terraform plan format
     

warn[msg] if {
    resource := input.resource_changes[_]
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)

    "Environment" in resource_tags
    environment := resource_tags.Environment
    not environment in valid_environments

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Resource %s has non-standard Environment tag value: '%s'. Expected: dev, staging, prod, test, or ci-mock", [
            address, environment
        ]),
        "resource": address,
        "environment_value": environment,
    }
}

     
# WARN: Placeholder Owner values

warn[msg] if {
    project := input.projects[_]
    resource := project.breakdown.resources[_]
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)

    "Owner" in resource_tags
    owner := lower(resource_tags.Owner)
    owner in placeholder_owner_values

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Resource %s has a placeholder Owner tag value: '%s' — use a real email or team name", [
            address, resource_tags.Owner
        ]),
        "resource": address,
        "owner_value": resource_tags.Owner,
    }
}

warn[msg] if {
    resource := input.resource_changes[_]
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)

    "Owner" in resource_tags
    owner := lower(resource_tags.Owner)
    owner in placeholder_owner_values

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Resource %s has a placeholder Owner tag value: '%s' — use a real email or team name", [
            address, resource_tags.Owner
        ]),
        "resource": address,
        "owner_value": resource_tags.Owner,
    }
}

     
# DENY: CostCenter format must match CC-XXXX
     
deny[msg] if {
    project := input.projects[_]
    resource := project.breakdown.resources[_]
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)

    "CostCenter" in resource_tags
    cost_center := resource_tags.CostCenter
    not regex.match(`^CC-[0-9]{4}$`, cost_center)

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Resource %s has CostCenter tag '%s' that doesn't match expected format CC-XXXX", [
            address, cost_center
        ]),
        "resource": address,
        "cost_center_value": cost_center,
    }
}

deny[msg] if {
    resource := input.resource_changes[_]
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)

    "CostCenter" in resource_tags
    cost_center := resource_tags.CostCenter
    not regex.match(`^CC-[0-9]{4}$`, cost_center)

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Resource %s has CostCenter tag '%s' that doesn't match expected format CC-XXXX", [
            address, cost_center
        ]),
        "resource": address,
        "cost_center_value": cost_center,
    }
}
