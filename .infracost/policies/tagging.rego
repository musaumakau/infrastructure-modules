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

# Check if resource has all required tags
has_required_tags(resource) if {
    resource_requires_tags(resource)
    resource_tags := object.get(resource, "tags", {})
    
    # Check that all required tags are present and not empty
    every tag in required_tags {
        tag in resource_tags
        resource_tags[tag] != ""
    }
}

# Policy rule: FAIL if resource is missing required tags
deny[msg] if {
    resource := input.resource_changes[_]
    resource_requires_tags(resource)
    not has_required_tags(resource)
    
    resource_tags := object.get(resource, "tags", {})
    missing_tags := required_tags - object.keys(resource_tags)
    
    msg := {
        "msg": sprintf("Resource %s is missing required tags: %s", [
            resource.address,
            concat(", ", missing_tags)
        ]),
        "resource": resource.address,
        "resource_type": resource.resource_type,
        "missing_tags": missing_tags
    }
}

# Policy rule: FAIL for resources with empty tag values
deny[msg] if {
    resource := input.resource_changes[_]
    resource_requires_tags(resource)
    resource_tags := object.get(resource, "tags", {})
    
    some tag in required_tags
    tag in resource_tags
    resource_tags[tag] == ""
    
    msg := {
        "msg": sprintf("Resource %s has empty value for required tag: %s", [
            resource.address,
            tag
        ]),
        "resource": resource.address,
        "resource_type": resource.resource_type,
        "empty_tag": tag
    }
}

# Policy rule: WARN for non-standard Environment values
warn[msg] if {
    resource := input.resource_changes[_]
    resource_requires_tags(resource)
    resource_tags := object.get(resource, "tags", {})
    
    "Environment" in resource_tags
    environment := resource_tags["Environment"]
    not environment in {"dev", "staging", "prod", "test"}
    
    msg := {
        "msg": sprintf("Resource %s has non-standard Environment tag value: %s. Expected: dev, staging, prod, or test", [
            resource.address,
            environment
        ]),
        "resource": resource.address,
        "environment_value": environment
    }
}