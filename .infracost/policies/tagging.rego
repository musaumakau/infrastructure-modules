package infracost.policies.tagging

import rego.v1

# Required tags for all resources
required_tags := {
    "Environment",
    "Owner", 
    "Project",
    "CostCenter"
}

# Resources that must have tags (customize based on your AWS resources)
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
    "aws_eip"
}

# Check if resource type requires tagging
resource_requires_tags(resource) if {
    resource.resource_type in taggable_resources
}

# Handle both Infracost breakdown format and Terraform plan format
get_resource_tags(resource) := tags if {
    # Infracost format
    tags := resource.tags
}

get_resource_tags(resource) := tags if {
    # Terraform plan format - try different possible locations
    tags := resource.change.after.tags
}

get_resource_tags(resource) := tags if {
    # Terraform plan format - alternative location
    tags := resource.values.tags
}

get_resource_tags(resource) := {} if {
    # Default empty if no tags found
    not resource.tags
    not resource.change.after.tags
    not resource.values.tags
}

# Check if resource has all required tags
has_required_tags(resource) if {
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)
    
    # Check that all required tags are present and not empty
    every tag in required_tags {
        tag in resource_tags
        resource_tags[tag] != ""
        resource_tags[tag] != null
    }
}

# Get resource address from different formats
get_resource_address(resource) := address if {
    address := resource.address
}

get_resource_address(resource) := address if {
    address := resource.name
}

get_resource_address(resource) := address if {
    address := sprintf("%s.%s", [resource.type, resource.name])
}

# Policy rule: FAIL if resource is missing required tags
deny[msg] if {
    # Handle Infracost format
    project := input.projects[_]
    resource := project.breakdown.resources[_]
    resource_requires_tags(resource)
    not has_required_tags(resource)
    
    resource_tags := get_resource_tags(resource)
    missing_tags := required_tags - object.keys(resource_tags)
    address := get_resource_address(resource)
    
    msg := {
        "msg": sprintf("Resource %s is missing required tags: %s", [
            address,
            concat(", ", missing_tags)
        ]),
        "resource": address,
        "resource_type": resource.resource_type,
        "missing_tags": missing_tags
    }
}

# Policy rule for Terraform plan format
deny[msg] if {
    # Handle Terraform plan format
    resource := input.resource_changes[_]
    resource_requires_tags(resource)
    not has_required_tags(resource)
    
    resource_tags := get_resource_tags(resource)
    missing_tags := required_tags - object.keys(resource_tags)
    address := get_resource_address(resource)
    
    msg := {
        "msg": sprintf("Resource %s is missing required tags: %s", [
            address,
            concat(", ", missing_tags)
        ]),
        "resource": address,
        "resource_type": resource.resource_type,
        "missing_tags": missing_tags
    }
}

# Policy rule: FAIL for resources with empty tag values
deny[msg] if {
    project := input.projects[_]
    resource := project.breakdown.resources[_]
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)
    
    some tag in required_tags
    tag in resource_tags
    tag_value := resource_tags[tag]
    any([tag_value == "", tag_value == null])
    
    address := get_resource_address(resource)
    
    msg := {
        "msg": sprintf("Resource %s has empty value for required tag: %s", [
            address,
            tag
        ]),
        "resource": address,
        "resource_type": resource.resource_type,
        "empty_tag": tag
    }
}

# Policy rule: WARN for non-standard Environment values
warn[msg] if {
    project := input.projects[_]
    resource := project.breakdown.resources[_]
    resource_requires_tags(resource)
    resource_tags := get_resource_tags(resource)
    
    "Environment" in resource_tags
    environment := resource_tags["Environment"]
    not environment in {"dev", "staging", "prod", "test"}
    
    address := get_resource_address(resource)
    
    msg := {
        "msg": sprintf("Resource %s has non-standard Environment tag value: %s. Expected: dev, staging, prod, or test", [
            address,
            environment
        ]),
        "resource": address,
        "environment_value": environment
    }
}