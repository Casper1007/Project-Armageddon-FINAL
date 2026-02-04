############################################
# Bonus-D: Apex ALIAS + ALB Access Logs
############################################

data "aws_caller_identity" "current" {}

data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket" "chrisbarm_alb_logs_bucket01" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = "${local.name_prefix}-alb-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-alb-logs"
  }
}

resource "aws_s3_bucket_policy" "chrisbarm_alb_logs_policy01" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.chrisbarm_alb_logs_bucket01[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.chrisbarm_alb_logs_bucket01[0].arn}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.chrisbarm_alb_logs_bucket01[0].arn
      }
    ]
  })
}

############################################
# Route53 Apex Alias -> ALB
############################################

resource "aws_route53_record" "chrisbarm_apex_alias01" {
  count   = var.certificate_validation_method == "DNS" ? 1 : 0
  zone_id = local.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.chrisbarm_alb01.dns_name
    zone_id                = aws_lb.chrisbarm_alb01.zone_id
    evaluate_target_health = true
  }
}
