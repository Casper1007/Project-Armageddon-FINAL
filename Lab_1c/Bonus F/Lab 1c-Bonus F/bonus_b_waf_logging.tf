############################################
# Bonus-E: WAF Logging (CloudWatch | S3 | Firehose)
############################################

locals {
  waf_log_group_name   = "aws-waf-logs-${local.name_prefix}-webacl01"
  waf_s3_bucket_name   = "aws-waf-logs-${local.name_prefix}-${data.aws_caller_identity.current.account_id}"
  waf_firehose_name    = "aws-waf-logs-${local.name_prefix}-firehose01"
  waf_firehose_bucket  = "aws-waf-logs-${local.name_prefix}-firehose-${data.aws_caller_identity.current.account_id}"

  waf_log_destination_arn = var.waf_log_destination == "cloudwatch" ? aws_cloudwatch_log_group.chrisbarm_waf_log_group01[0].arn : (
    var.waf_log_destination == "s3" ? aws_s3_bucket.chrisbarm_waf_logs_bucket01[0].arn : aws_kinesis_firehose_delivery_stream.chrisbarm_waf_firehose01[0].arn
  )
}

############################################
# CloudWatch Logs destination
############################################

resource "aws_cloudwatch_log_group" "chrisbarm_waf_log_group01" {
  count             = var.enable_waf && var.waf_log_destination == "cloudwatch" ? 1 : 0
  name              = local.waf_log_group_name
  retention_in_days = var.waf_log_retention_days
}

resource "aws_cloudwatch_log_resource_policy" "chrisbarm_waf_logs_policy01" {
  count       = var.enable_waf && var.waf_log_destination == "cloudwatch" ? 1 : 0
  policy_name = "${local.name_prefix}-waf-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSWAFLoggingPermissions"
        Effect = "Allow"
        Principal = {
          Service = "waf.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.chrisbarm_waf_log_group01[0].arn}:*"
      }
    ]
  })
}

############################################
# S3 destination
############################################

resource "aws_s3_bucket" "chrisbarm_waf_logs_bucket01" {
  count  = var.enable_waf && var.waf_log_destination == "s3" ? 1 : 0
  bucket = local.waf_s3_bucket_name
}

resource "aws_s3_bucket_policy" "chrisbarm_waf_logs_bucket_policy01" {
  count  = var.enable_waf && var.waf_log_destination == "s3" ? 1 : 0
  bucket = aws_s3_bucket.chrisbarm_waf_logs_bucket01[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSWAFLogsWrite"
        Effect = "Allow"
        Principal = {
          Service = "waf.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.chrisbarm_waf_logs_bucket01[0].arn}/*"
      }
    ]
  })
}

############################################
# Firehose destination (to S3)
############################################

resource "aws_s3_bucket" "chrisbarm_waf_firehose_bucket01" {
  count  = var.enable_waf && var.waf_log_destination == "firehose" ? 1 : 0
  bucket = local.waf_firehose_bucket
}

resource "aws_iam_role" "chrisbarm_waf_firehose_role01" {
  count = var.enable_waf && var.waf_log_destination == "firehose" ? 1 : 0
  name  = "${local.name_prefix}-waf-firehose-role01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "firehose.amazonaws.com" }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "chrisbarm_waf_firehose_policy01" {
  count = var.enable_waf && var.waf_log_destination == "firehose" ? 1 : 0
  name  = "${local.name_prefix}-waf-firehose-policy01"
  role  = aws_iam_role.chrisbarm_waf_firehose_role01[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.chrisbarm_waf_firehose_bucket01[0].arn,
          "${aws_s3_bucket.chrisbarm_waf_firehose_bucket01[0].arn}/*"
        ]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "chrisbarm_waf_firehose01" {
  count       = var.enable_waf && var.waf_log_destination == "firehose" ? 1 : 0
  name        = local.waf_firehose_name
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.chrisbarm_waf_firehose_role01[0].arn
    bucket_arn         = aws_s3_bucket.chrisbarm_waf_firehose_bucket01[0].arn
    prefix             = "waf-logs/"
    buffering_size     = 5
    buffering_interval = 300
  }
}

############################################
# WAF Logging Configuration (one destination)
############################################

resource "aws_wafv2_web_acl_logging_configuration" "chrisbarm_waf_logging01" {
  count                 = var.enable_waf ? 1 : 0
  resource_arn          = aws_wafv2_web_acl.chrisbarm_alb_waf01[0].arn
  log_destination_configs = [local.waf_log_destination_arn]
}
