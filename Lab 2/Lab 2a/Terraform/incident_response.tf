################################################################################
# Lab 1b — Incident Response Infrastructure
# 
# Observability and Incident Response Configuration
# - CloudWatch Logs for application monitoring
# - CloudWatch Alarms for failure detection
# - SNS for incident notifications
# - Metrics for incident diagnosis
################################################################################

############################################
# CloudWatch Log Group for Application
############################################

resource "aws_cloudwatch_log_group" "lab_rds_app_logs" {
  name              = "/aws/ec2/chrisbarm-rds-app"
  retention_in_days = 7
  skip_destroy      = true

  tags = {
    Name = "${local.name_prefix}-app-logs"
  }
}

############################################
# SNS Topic for Incident Notifications
############################################

resource "aws_sns_topic" "db_incidents" {
  name = "lab-db-incidents"

  tags = {
    Name = "${local.name_prefix}-db-incidents"
  }
}

# SNS Topic Policy (allow CloudWatch to publish)
resource "aws_sns_topic_policy" "db_incidents_policy" {
  arn = aws_sns_topic.db_incidents.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.db_incidents.arn
      }
    ]
  })
}

############################################
# CloudWatch Metric for DB Errors
# (Application logs these via custom metrics)
############################################

resource "aws_cloudwatch_metric_alarm" "db_connection_failure" {
  alarm_name          = "lab-db-connection-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DBConnectionErrors"
  namespace           = "Lab/RDSApp"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 3 # Trigger if 3+ errors in 5 min
  alarm_description   = "Database connectivity failures detected"
  alarm_actions       = [aws_sns_topic.db_incidents.arn]
  treat_missing_data  = "notBreaching"

  tags = {
    Name = "${local.name_prefix}-db-connection-alarm"
  }
}

############################################
# CloudWatch Log Metric Filters
# (Parse application logs for error patterns)
############################################

resource "aws_cloudwatch_log_metric_filter" "db_error_filter" {
  name           = "DBErrorFilter"
  log_group_name = aws_cloudwatch_log_group.lab_rds_app_logs.name
  pattern        = "[ERROR]"

  metric_transformation {
    name      = "DBConnectionErrors"
    namespace = "Lab/RDSApp"
    value     = "1"
  }
}

############################################
# IAM Policy for EC2 to Write Logs
# (Already included in main.tf IAM section,
#  but documented here for reference)
############################################

# The EC2 role already has CloudWatch Logs permissions
# via AmazonSSMManagedInstanceCore and CloudWatchAgentServerPolicy
# Additional permissions can be added if needed:

resource "aws_iam_role_policy" "ec2_cloudwatch_logs" {
  name = "${local.name_prefix}-ec2-logs-policy"
  role = aws_iam_role.chrisbarm_ec2_role01.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.lab_rds_app_logs.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "Lab/RDSApp"
          }
        }
      }
    ]
  })
}

############################################
# Output: SNS Topic ARN for Subscriptions
############################################

output "db_incidents_topic_arn" {
  description = "SNS Topic ARN for database incident notifications"
  value       = aws_sns_topic.db_incidents.arn
}

output "db_incidents_topic_name" {
  description = "SNS Topic name for database incident notifications"
  value       = aws_sns_topic.db_incidents.name
}

output "log_group_name" {
  description = "CloudWatch Log Group for application logging"
  value       = aws_cloudwatch_log_group.lab_rds_app_logs.name
}

output "db_connection_alarm_name" {
  description = "CloudWatch Alarm name for database connection failures"
  value       = aws_cloudwatch_metric_alarm.db_connection_failure.alarm_name
}
