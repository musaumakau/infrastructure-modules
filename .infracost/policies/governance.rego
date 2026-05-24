package infracost.policies.governance

import rego.v1

# Cost limits per resource type (monthly USD)
cost_limits := {
    "aws_instance":              500,
    "aws_db_instance":          1000,
    "aws_rds_cluster":          2000,
    "aws_eks_cluster":           200,
    "aws_eks_node_group":       1000,
    "aws_elasticache_cluster":   500,
    "aws_elasticsearch_domain":  800,
    "aws_opensearch_domain":     800,
}

large_instance_types := {
    "m5.4xlarge", "m5.8xlarge", "m5.12xlarge", "m5.16xlarge", "m5.24xlarge",
    "c5.4xlarge", "c5.9xlarge", "c5.12xlarge", "c5.18xlarge", "c5.24xlarge",
    "r5.4xlarge", "r5.8xlarge", "r5.12xlarge", "r5.16xlarge", "r5.24xlarge",
}

prod_only_instance_types := {
    "m5.4xlarge", "m5.8xlarge", "m5.16xlarge",
    "c5.9xlarge", "c5.18xlarge",
    "r5.4xlarge", "r5.8xlarge",
}

undersized_eks_types := {
    "t2.micro", "t2.small", "t3.micro", "t3.small",
}

# Helper functions

get_resource_address(resource) := resource.address if { resource.address }
get_resource_address(resource) := sprintf("%s.%s", [resource.type, resource.name]) if {
    not resource.address
    resource.type
    resource.name
}

get_monthly_cost(resource) := resource.monthly_cost if { resource.monthly_cost }
get_monthly_cost(resource) := resource.monthlyCost if {
    not resource.monthly_cost
    resource.monthlyCost
}
get_monthly_cost(resource) := 0 if {
    not resource.monthly_cost
    not resource.monthlyCost
}

get_resource_tags(resource) := resource.change.after.tags if {
    resource.change.after.tags
}
get_resource_tags(resource) := {} if {
    not resource.change.after.tags
}

# COST: Deny resources exceeding monthly cost limits

deny[msg] if {
    project := input.projects[_]
    resource := project.breakdown.resources[_]
    resource.resource_type in cost_limits
    monthly_cost := get_monthly_cost(resource)
    limit := cost_limits[resource.resource_type]
    monthly_cost > limit

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Resource %s monthly cost $%.2f exceeds limit of $%.2f", [
            address, monthly_cost, limit
        ]),
        "resource": address,
        "monthly_cost": monthly_cost,
        "cost_limit": limit,
    }
}

# COST: Warn resources approaching cost limits (80%)

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
            address, monthly_cost, limit, (monthly_cost / limit) * 100
        ]),
        "resource": address,
        "monthly_cost": monthly_cost,
        "cost_limit": limit,
    }
}

# COST: Warn total monthly cost across all projects exceeds budget

warn[msg] if {
    total := sum([cost |
        project := input.projects[_]
        resource := project.breakdown.resources[_]
        cost := get_monthly_cost(resource)
    ])
    total > 3000

    msg := {
        "msg": sprintf("Total estimated monthly cost $%.2f exceeds warning threshold of $3000", [total]),
        "total_cost": total,
    }
}

# S3: Naming convention

deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_s3_bucket"
    bucket_name := resource.change.after.bucket
    not regex.match(`^[a-z0-9][a-z0-9.-]*[a-z0-9]$`, bucket_name)

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("S3 bucket %s name '%s' must follow naming convention (lowercase, alphanumeric, dots, hyphens)", [
            address, bucket_name
        ]),
        "resource": address,
        "bucket_name": bucket_name,
    }
}

# S3: Public access block must exist

deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_s3_bucket"

    public_access_blocks := [r |
        r := input.resource_changes[_]
        r.type == "aws_s3_bucket_public_access_block"
    ]
    count(public_access_blocks) == 0

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("S3 bucket %s must have an accompanying aws_s3_bucket_public_access_block resource", [address]),
        "resource": address,
    }
}

# EC2: Encrypted root EBS volume

deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    root_block_device := resource.change.after.root_block_device[0]
    not root_block_device.encrypted

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("EC2 instance %s must have encrypted root EBS volume", [address]),
        "resource": address,
    }
}

# EC2: Enforce IMDSv2

deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    metadata_options := resource.change.after.metadata_options
    count(metadata_options) > 0
    metadata_options[0].http_tokens != "required"

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("EC2 instance %s must enforce IMDSv2 (http_tokens = required) to prevent SSRF attacks", [address]),
        "resource": address,
    }
}

# EC2: No plaintext secrets in userdata

deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    user_data := resource.change.after.user_data
    user_data != null

    secret_patterns := [
        "password=", "secret=", "api_key=",
        "access_key=", "aws_secret", "private_key",
    ]
    pattern := secret_patterns[_]
    contains(lower(user_data), pattern)

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("EC2 instance %s may contain plaintext secrets in user_data — use SSM Parameter Store or Secrets Manager instead", [address]),
        "resource": address,
    }
}

# EC2: Warn large instance types

warn[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    instance_type := resource.change.after.instance_type
    instance_type in large_instance_types

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Resource %s uses large instance type %s — verify this sizing is necessary", [
            address, instance_type
        ]),
        "resource": address,
        "instance_type": instance_type,
    }
}

# SECURITY GROUPS: No unrestricted SSH

deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_security_group"
    ingress := resource.change.after.ingress[_]
    ingress.from_port <= 22
    ingress.to_port >= 22
    cidr := ingress.cidr_blocks[_]
    cidr == "0.0.0.0/0"

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Security group %s allows unrestricted SSH (port 22) ingress from 0.0.0.0/0", [address]),
        "resource": address,
    }
}

# SECURITY GROUPS: No unrestricted RDP

deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_security_group"
    ingress := resource.change.after.ingress[_]
    ingress.from_port <= 3389
    ingress.to_port >= 3389
    cidr := ingress.cidr_blocks[_]
    cidr == "0.0.0.0/0"

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Security group %s allows unrestricted RDP (port 3389) ingress from 0.0.0.0/0", [address]),
        "resource": address,
    }
}

# KMS: Key rotation must be enabled

deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_kms_key"
    not resource.change.after.enable_key_rotation

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("KMS key %s must have key rotation enabled", [address]),
        "resource": address,
    }
}

# IAM: Warn wildcard principal in assume role policy

warn[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_iam_role"
    assume_role_policy := json.unmarshal(resource.change.after.assume_role_policy)
    statement := assume_role_policy.Statement[_]
    statement.Effect == "Allow"
    statement.Principal == "*"

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("IAM role %s has a wildcard principal in its assume role policy — review carefully", [address]),
        "resource": address,
    }
}

# RDS: Publicly accessible

warn[msg] if {
    resource := input.resource_changes[_]
    resource.type in {"aws_db_instance", "aws_rds_cluster"}
    resource.change.after.publicly_accessible == true

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Database %s should not be publicly accessible", [address]),
        "resource": address,
    }
}

# RDS: Deletion protection

warn[msg] if {
    resource := input.resource_changes[_]
    resource.type in {"aws_db_instance", "aws_rds_cluster"}
    not resource.change.after.deletion_protection

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("RDS resource %s does not have deletion_protection enabled", [address]),
        "resource": address,
    }
}

# EKS: Private endpoint must be enabled

deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_eks_cluster"
    not resource.change.after.vpc_config[0].endpoint_private_access

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("EKS cluster %s must have private endpoint access enabled", [address]),
        "resource": address,
    }
}

# EKS: Warn public endpoint enabled

warn[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_eks_cluster"
    resource.change.after.vpc_config[0].endpoint_public_access == true

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("EKS cluster %s has public endpoint enabled — restrict public_access_cidrs if intentional", [address]),
        "resource": address,
    }
}

# EKS: Required log types

deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_eks_cluster"
    enabled_log_types := {t | t := resource.change.after.enabled_cluster_log_types[_]}
    required_log_types := {"api", "audit", "authenticator"}
    missing := required_log_types - enabled_log_types
    count(missing) > 0

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("EKS cluster %s is missing required log types: %s", [
            address, concat(", ", missing)
        ]),
        "resource": address,
        "missing_log_types": missing,
    }
}

# EKS: Undersized node group instance types

deny[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_eks_node_group"
    instance_type := resource.change.after.instance_types[_]
    instance_type in undersized_eks_types

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("EKS node group %s uses undersized instance type %s — not suitable for production workloads", [
            address, instance_type
        ]),
        "resource": address,
        "instance_type": instance_type,
    }
}

# EKS: Prod-sized instances in dev environment

warn[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_eks_node_group"
    instance_type := resource.change.after.instance_types[_]
    instance_type in prod_only_instance_types
    tags := get_resource_tags(resource)
    tags.Environment == "dev"

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("EKS node group %s uses production-sized instance %s in dev environment — intentional?", [
            address, instance_type
        ]),
        "resource": address,
        "instance_type": instance_type,
    }
}

# EKS: Protected tag on prod/staging clusters

warn[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_eks_cluster"
    tags := get_resource_tags(resource)
    tags.Environment in {"prod", "staging"}
    not "protected" in object.keys(tags)

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("EKS cluster %s in %s environment is missing 'protected' tag — add lifecycle controls", [
            address, tags.Environment
        ]),
        "resource": address,
    }
}

# VPC: Flow logs must exist

warn[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_vpc"

    flow_logs := [r |
        r := input.resource_changes[_]
        r.type == "aws_flow_log"
    ]
    count(flow_logs) == 0

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("VPC %s has no aws_flow_log resource in this plan — ensure flow logs are enabled", [address]),
        "resource": address,
    }
}

# SUBNET: Public IP auto-assign

warn[msg] if {
    resource := input.resource_changes[_]
    resource.type == "aws_subnet"
    resource.change.after.map_public_ip_on_launch == true

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Subnet %s has map_public_ip_on_launch enabled — ensure this is a public subnet intentionally", [address]),
        "resource": address,
    }
}

# HELM: Timeout guard

warn[msg] if {
    resource := input.resource_changes[_]
    resource.type == "helm_release"
    timeout := resource.change.after.timeout
    timeout > 600

    address := get_resource_address(resource)
    msg := {
        "msg": sprintf("Helm release %s has a timeout of %d seconds — verify this is intentional", [
            address, timeout
        ]),
        "resource": address,
    }
}