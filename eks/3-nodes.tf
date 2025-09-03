resource "aws_launch_template" "eks_nodes" {
  for_each = var.node_groups

  name_prefix   = "${var.env}-${var.eks_name}-${each.key}-"
  image_id      = data.aws_ssm_parameter.eks_ami_release_version.value
  instance_type = each.value.instance_types[0] # Use first instance type as default

  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = each.value.disk_size
      volume_type           = "gp3" # This satisfies the governance policy
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    cluster_name          = aws_eks_cluster.this.name
    endpoint              = aws_eks_cluster.this.endpoint
    certificate_authority = aws_eks_cluster.this.certificate_authority[0].data
  }))

  tags = merge(var.common_tags, {
    Name = "${var.env}-${var.eks_name}-${each.key}-launch-template"
    Type = "EKSLaunchTemplate"
  })
}

# Data source to get the latest EKS optimized AMI
data "aws_ssm_parameter" "eks_ami_release_version" {
  name = "/aws/service/eks/optimized-ami/${aws_eks_cluster.this.version}/amazon-linux-2/recommended/image_id"
}



resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.nodes.arn

  subnet_ids = var.subnet_ids

  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types

  launch_template {
    id      = aws_launch_template.eks_nodes[each.key].id
    version = aws_launch_template.eks_nodes[each.key].latest_version
  }

  scaling_config {
    desired_size = each.value.scaling_config.desired_size
    max_size     = each.value.scaling_config.max_size
    min_size     = each.value.scaling_config.min_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = each.key
  }

  depends_on = [aws_iam_role_policy_attachment.nodes]

}