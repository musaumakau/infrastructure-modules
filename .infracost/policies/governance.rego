package infracost.policies.governance

import rego.v1

# Cost limits per resource type (monthly USD)
cost_limits := {
    "aws_instance": 500,
    "aws_db_instance": 1000,
    "aws_rds_cluster": 2000,
    "aws_eks_cluster": 200,
    "aws_eks_node_group": 1000,
    "aws_elasticache_cluster": 500,
    "aws_elasticsearch_domain": 800,
    "aws_opensearch_domain": 800
}

# FAIL: Deny expensive resources that exceed cost limits
deny[msg] if {
    resource := input.resource_changes[_]
    resource.resource_type in cost_limits
    monthly_cost := resource.monthly_cost
    limit := cost_limits[resource.resource_type]
    monthly_cost > limit
    
    msg := {
        "msg": sprintf("Resource %s monthly cost $%.2f exceeds limit of $%.2f", [
            resource.address,
            monthly_cost,
            limit
        ]),
        "resource": resource.address,
        "monthly_cost": monthly_cost,
        "cost_limit": limit
    }
}

# WARN: Resources approaching cost limits (80% of limit)
warn[msg] if {
    resource := input.resource_changes[_]
    resource.resource_type in cost_limits
    monthly_cost := resource.monthly_cost
    limit := cost_limits[resource.resource_type]
    monthly_cost > (limit * 0.8)
    monthly_cost <= limit
    
    msg := {
        "msg": sprintf("Resource %s monthly cost $%.2f is approaching limit of $%.2f (%.0f%% of limit)", [
            resource.address,
            monthly_cost,
            limit,
            (monthly_cost / limit) * 100
        ]),
        "resource": resource.address,
        "monthly_cost": monthly_cost,
        "cost_limit": limit
    }
}

# FAIL: S3 bucket naming convention
deny[msg] if {
    resource := input.resource_changes[_]
    resource.resource_type == "aws_s3_bucket"
    not regex.match("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", resource.name)
    
    msg := {
        "msg": sprintf("S3 bucket %s name must follow naming convention (lowercase, alphanumeric, dots, hyphens)", [
            resource.address
        ]),
        "resource": resource.address,
        "bucket_name": resource.name
    }
}

# FAIL: Prevent unencrypted S3 buckets (if encryption settings are available)
deny[msg] if {
    resource := input.resource_changes[_]
    resource.resource_type == "aws_s3_bucket"
    # This is a simplified check - adjust based on your Terraform structure
    not resource.server_side_encryption_configuration
    
    msg := {
        "msg": sprintf("S3 bucket %s must have server-side encryption enabled", [
            resource.address
        ]),
        "resource": resource.address
    }
}

# WARN: Large instance types that might be oversized
warn[msg] if {
    resource := input.resource_changes[_]
    resource.resource_type == "aws_instance"
    large_instance_types := {
        "m5.4xlarge", "m5.8xlarge", "m5.12xlarge", "m5.16xlarge", "m5.24xlarge",
        "c5.4xlarge", "c5.9xlarge", "c5.12xlarge", "c5.18xlarge", "c5.24xlarge",
        "r5.4xlarge", "r5.8xlarge", "r5.12xlarge", "r5.16xlarge", "r5.24xlarge"
    }
    resource.instance_type in large_instance_types
    
    msg := {
        "msg": sprintf("Resource %s uses large instance type %s - verify this sizing is necessary", [
            resource.address,
            resource.instance_type
        ]),
        "resource": resource.address,
        "instance_type": resource.instance_type
    }
}