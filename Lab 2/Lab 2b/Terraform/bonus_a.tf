################################################################################
# BONUS-A: Private Compute with VPC Endpoints & SSM Session Manager
#
# Architecture: 
#   - Private EC2 (no public IP)
#   - VPC Interface Endpoints for SSM, EC2Messages, SSMMessages, CloudWatch Logs, 
#     Secrets Manager, KMS
#   - S3 Gateway Endpoint for yum/apt repos (if needed)
#   - Least-privilege IAM: scoped to specific secrets and parameter paths
#   - Session Manager for shell access (no SSH required)
#
# Real-world alignment:
#   - Matches regulated orgs (finance, healthcare, government)
#   - Reduces NAT complexity and dependency
#   - Eliminates internet exposure for compute
#   - Least-privilege follows security baseline (CIS, SOC2)
################################################################################

locals {
  bonus_a_prefix = "bonus-a"
  vpc_id         = aws_vpc.chrisbarm_vpc01.id
  private_subnet = aws_subnet.chrisbarm_private_subnets[0].id
  # For session manager endpoints, we'll use first private subnet
  endpoint_subnets = [aws_subnet.chrisbarm_private_subnets[0].id]
}

################################################################################
# BONUS-A: Security Group for Endpoints
################################################################################

resource "aws_security_group" "bonus_a_endpoints_sg" {
  name_prefix = "${local.bonus_a_prefix}-endpoints-"
  description = "SG for VPC endpoints (inbound HTTPS from private subnets)"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTPS from private subnets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  egress {
    description = "Allow all outbound - endpoints receive only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.bonus_a_prefix}-endpoints-sg"
  }
}

################################################################################
# BONUS-A: Security Group for Private EC2
################################################################################

resource "aws_security_group" "bonus_a_ec2_sg" {
  name_prefix = "${local.bonus_a_prefix}-ec2-"
  description = "SG for private EC2 outbound to endpoints and RDS"
  vpc_id      = local.vpc_id

  # No inbound rules allow Session Manager access

  egress {
    description     = "HTTPS to VPC endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.bonus_a_endpoints_sg.id]
  }

  # Allow RDS connectivity (to Lab 1a RDS in private subnet)
  egress {
    description = "MySQL to RDS (Lab 1a)"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = {
    Name = "${local.bonus_a_prefix}-ec2-sg"
  }
}

# Allow Bonus-A EC2 to connect to Lab 1a RDS
resource "aws_vpc_security_group_ingress_rule" "bonus_a_rds_ingress_from_bonus_a_ec2" {
  description              = "MySQL from Bonus-A EC2"
  from_port                = 3306
  to_port                  = 3306
  ip_protocol              = "tcp"
  security_group_id        = aws_security_group.chrisbarm_rds_sg01.id
  referenced_security_group_id = aws_security_group.bonus_a_ec2_sg.id
}

################################################################################
# BONUS-A: VPC Interface Endpoints
# 
# These replace the need for NAT Gateway to reach AWS APIs
# (S3 uses a Gateway Endpoint instead)
################################################################################

# SSM (Systems Manager) - for agent communication
resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type = "Interface"
  subnet_ids        = local.endpoint_subnets

  security_group_ids = [aws_security_group.bonus_a_endpoints_sg.id]

  private_dns_enabled = true

  tags = {
    Name = "${local.bonus_a_prefix}-ssm-endpoint"
  }
}

# EC2Messages - required for Session Manager
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type = "Interface"
  subnet_ids        = local.endpoint_subnets

  security_group_ids = [aws_security_group.bonus_a_endpoints_sg.id]

  private_dns_enabled = true

  tags = {
    Name = "${local.bonus_a_prefix}-ec2messages-endpoint"
  }
}

# SSMMessages - required for Session Manager shell
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type = "Interface"
  subnet_ids        = local.endpoint_subnets

  security_group_ids = [aws_security_group.bonus_a_endpoints_sg.id]

  private_dns_enabled = true

  tags = {
    Name = "${local.bonus_a_prefix}-ssmmessages-endpoint"
  }
}

# CloudWatch Logs - for log delivery
resource "aws_vpc_endpoint" "logs" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type = "Interface"
  subnet_ids        = local.endpoint_subnets

  security_group_ids = [aws_security_group.bonus_a_endpoints_sg.id]

  private_dns_enabled = true

  tags = {
    Name = "${local.bonus_a_prefix}-logs-endpoint"
  }
}

# Secrets Manager - for DB credentials
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type = "Interface"
  subnet_ids        = local.endpoint_subnets

  security_group_ids = [aws_security_group.bonus_a_endpoints_sg.id]

  private_dns_enabled = true

  tags = {
    Name = "${local.bonus_a_prefix}-secretsmanager-endpoint"
  }
}

# KMS (optional but realistic for key operations)
resource "aws_vpc_endpoint" "kms" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type = "Interface"
  subnet_ids        = local.endpoint_subnets

  security_group_ids = [aws_security_group.bonus_a_endpoints_sg.id]

  private_dns_enabled = true

  tags = {
    Name = "${local.bonus_a_prefix}-kms-endpoint"
  }
}

################################################################################
# BONUS-A: S3 Gateway Endpoint
#
# Used for package repos, AMI baking, and data transfer (no NAT needed)
################################################################################

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = local.vpc_id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  # S3 Gateway routes through main private route table
  # (aws_route_table._private_rt01 in main.tf)

  tags = {
    Name = "${local.bonus_a_prefix}-s3-endpoint"
  }
}


################################################################################
# BONUS-A: IAM Role for Private EC2 (Least-Privilege)
################################################################################

resource "aws_iam_role" "bonus_a_ec2_role" {
  name_prefix = "${local.bonus_a_prefix}-ec2-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.bonus_a_prefix}-ec2-role"
  }
}

# Policy: SSM Session Manager access
resource "aws_iam_role_policy" "bonus_a_ssm_session" {
  name_prefix = "${local.bonus_a_prefix}-ssm-session-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMSessionManagerCore"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy: CloudWatch Logs write (app logs only)
resource "aws_iam_role_policy" "bonus_a_cloudwatch_logs" {
  name_prefix = "${local.bonus_a_prefix}-cloudwatch-logs-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/${local.bonus_a_prefix}-rds-app:*"
      }
    ]
  })
}

# Policy: Secrets Manager (scoped to Lab 1a RDS secret only)
resource "aws_iam_role_policy" "bonus_a_secrets_manager" {
  name_prefix = "${local.bonus_a_prefix}-secrets-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetLabSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:lab1a/rds/mysql*"
      }
    ]
  })
}

# Policy: Systems Manager Parameter Store (scoped to /lab/ path only)
resource "aws_iam_role_policy" "bonus_a_parameter_store" {
  name_prefix = "${local.bonus_a_prefix}-params-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetLabParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/lab/*"
      }
    ]
  })
}

# Instance profile for EC2
resource "aws_iam_instance_profile" "bonus_a_ec2_profile" {
  name_prefix = "${local.bonus_a_prefix}-ec2-profile-"
  role        = aws_iam_role.bonus_a_ec2_role.name
}

################################################################################
# BONUS-A: Private EC2 Instance
#
# - No public IP
# - Uses IAM role for permissions
# - Accessed via Session Manager (no SSH key needed)
################################################################################

resource "aws_instance" "bonus_a_ec2" {
  ami                         = "ami-0030e4319cbf4dbf2"  # Ubuntu 22.04 LTS in us-east-1
  instance_type               = var.ec2_instance_type
  subnet_id                   = local.private_subnet
  iam_instance_profile        = aws_iam_instance_profile.bonus_a_ec2_profile.name
  associate_public_ip_address = false # PRIVATE
  vpc_security_group_ids      = [aws_security_group.bonus_a_ec2_sg.id]

  # Use existing user_data script (Lab 1a setup)
  user_data = file("${path.module}/1a_user_data.sh")

  tags = {
    Name = "${local.bonus_a_prefix}-ec2-private"
  }
}

################################################################################
# BONUS-A: CloudWatch Log Group for Private EC2
################################################################################

resource "aws_cloudwatch_log_group" "bonus_a_logs" {
  name              = "/aws/ec2/${local.bonus_a_prefix}-rds-app"
  retention_in_days = 7

  tags = {
    Name = "${local.bonus_a_prefix}-log-group"
  }
}

################################################################################
# BONUS-A: Outputs
################################################################################

output "bonus_a_instance_id" {
  description = "Bonus-A private EC2 instance ID"
  value       = aws_instance.bonus_a_ec2.id
}

output "bonus_a_instance_private_ip" {
  description = "Bonus-A private EC2 IP"
  value       = aws_instance.bonus_a_ec2.private_ip
}

output "bonus_a_instance_public_ip" {
  description = "Bonus-A public IP (should be null for private instance)"
  value       = aws_instance.bonus_a_ec2.public_ip
}

output "bonus_a_vpc_endpoints" {
  description = "VPC Endpoint IDs for verification"
  value = {
    ssm               = aws_vpc_endpoint.ssm.id
    ec2messages       = aws_vpc_endpoint.ec2messages.id
    ssmmessages       = aws_vpc_endpoint.ssmmessages.id
    cloudwatch_logs   = aws_vpc_endpoint.logs.id
    secretsmanager    = aws_vpc_endpoint.secretsmanager.id
    kms               = aws_vpc_endpoint.kms.id
    s3_gateway        = aws_vpc_endpoint.s3.id
  }
}

output "bonus_a_session_manager_ready" {
  description = "Ready for Session Manager access"
  value       = "aws ssm start-session --target ${aws_instance.bonus_a_ec2.id} --region ${var.aws_region}"
}

################################################################################
# Data source for current AWS account ID
################################################################################

data "aws_caller_identity" "current" {}
