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

# Get monthly cost from resource
get_monthly_cost(resource) := cost if {
    cost := resource.monthly_cost
}

get_monthly_cost(resource) := cost if {
    cost := resource.monthlyCost
}

get_monthly_cost(resource) := 0 if {
    not resource.monthly_cost
    not resource.monthlyCost
}

# FAIL: Deny expensive resources that exceed cost limits
deny[msg] if {
    # Handle Infracost breakdown format
    project := input.projects[_]
    resource := project.breakdown.resources[_]
    resource.resource_type in cost_limits
    monthly_cost := get_monthly_cost(resource)
    limit := cost_limits[resource.resource_type]
    monthly_cost > limit
    
    address := get_resource_address(resource)
    
    msg := {
        "msg": sprintf("Resource %s monthly cost $%.2f exceeds limit of $%.2f", [
            address,
            monthly_cost,
            limit
        ]),
        "resource": address,
        "monthly_cost": monthly_cost,
        "cost_limit": limit
    }
}

# WARN: Resources approaching cost limits (80% of limit)
warn[msg] if {
    project := input.projects[_]
    resource := project.breakdown.resources[_]
    resource.resource_type in cost_limits
    monthly_cost := get_monthly_cost(resource)
    limit := cost_limits[resource.resource_type]
    monthly_cost > (limit * 0.8)
    monthly_cost <= limit
    
    address := get_resource_address(resource)
    
    msg := {
        "msg": sprintf("Resource %s monthly cost $%.2f is approaching limit of $%.2f (%.0f%% of limit)", [
            address,
            monthly_cost,
            limit,
            (monthly_cost / limit) * 100
        ]),
        "resource": address,
        "monthly_cost": monthly_cost,
        "cost_limit": limit
    }
}

# FAIL: S3 bucket naming convention (from Terraform plan)
deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_s3_bucket"
    bucket_name := resource.change.after.bucket
    not regex.match("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", bucket_name)
    
    address := get_resource_address(resource)
    
    msg := {
        "msg": sprintf("S3 bucket %s name '%s' must follow naming convention (lowercase, alphanumeric, dots, hyphens)", [
            address,
            bucket_name
        ]),
        "resource": address,
        "bucket_name": bucket_name
    }
}

# WARN: Large instance types that might be oversized (from Terraform plan)
warn[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    instance_type := resource.change.after.instance_type
    large_instance_types := {
        "m5.4xlarge", "m5.8xlarge", "m5.12xlarge", "m5.16xlarge", "m5.24xlarge",
        "c5.4xlarge", "c5.9xlarge", "c5.12xlarge", "c5.18xlarge", "c5.24xlarge",
        "r5.4xlarge", "r5.8xlarge", "r5.12xlarge", "r5.16xlarge", "r5.24xlarge"
    }
    instance_type in large_instance_types
    
    address := get_resource_address(resource)
    
    msg := {
        "msg": sprintf("Resource %s uses large instance type %s - verify this sizing is necessary", [
            address,
            instance_type
        ]),
        "resource": address,
        "instance_type": instance_type
    }
}

# FAIL: Prevent unencrypted EBS volumes (from Terraform plan)
deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    
    # Check root block device
    root_block_device := resource.change.after.root_block_device[0]
    not root_block_device.encrypted
    
    address := get_resource_address(resource)
    
    msg := {
        "msg": sprintf("EC2 instance %s must have encrypted root EBS volume", [
            address
        ]),
        "resource": address
    }
}

# WARN: Public subnets for databases (from Terraform plan)
warn[msg] if {
    resource := input.resource_changes[_]
    resource.type in {"aws_db_instance", "aws_rds_cluster"}
    
    # Check if publicly accessible
    publicly_accessible := resource.change.after.publicly_accessible
    publicly_accessible == true
    
    address := get_resource_address(resource)
    
    msg := {
        "msg": sprintf("Database %s should not be publicly accessible for security", [
            address
        ]),
        "resource": address
    }
}