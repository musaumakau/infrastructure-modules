

resource "aws_kms_key" "cloudwatch_logs" {
  description             = "KMS key for CloudWatch Logs encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc/flowlogs"
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.env}-cloudwatch-logs-key"
    Type = "KMSKey"
  })
}

resource "aws_kms_alias" "cloudwatch_logs" {
  name          = "alias/${var.env}-cloudwatch-logs"
  target_key_id = aws_kms_key.cloudwatch_logs.key_id
}

# CloudWatch Log Group with proper retention and encryption
resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/aws/vpc/flowlogs"
  retention_in_days = 365 # 1 year retention
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn

  tags = merge(var.common_tags, {
    Name = "${var.env}-vpc-flow-logs"
    Type = "LogGroup"
  })
}

# VPC Flow Log
resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn    = aws_iam_role.flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${var.env}-vpc-flow-log"
  })
}

# IAM Role for VPC Flow Logs
resource "aws_iam_role" "flow_log_role" {
  name = "${var.env}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.env}-flow-log-role"
    Type = "IAMRole"
  })
}

# IAM Policy with specific resource constraints
resource "aws_iam_role_policy" "flow_log_policy" {
  name = "${var.env}-flow-log-policy"
  role = aws_iam_role.flow_log_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.vpc_flow_log.arn,
          "${aws_cloudwatch_log_group.vpc_flow_log.arn}:*"
        ]
      }
    ]
  })
}

# Data sources for account and region info
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}