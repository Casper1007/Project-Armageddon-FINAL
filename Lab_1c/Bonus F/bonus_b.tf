############################################
# Bonus-B: ALB + ACM + WAF + Monitoring
############################################

locals {
  app_fqdn = "${var.app_subdomain}.${var.domain_name}"
  route53_zone_id = var.certificate_validation_method == "DNS" ? (
    var.create_route53_zone ? aws_route53_zone.bonus_b[0].zone_id : data.aws_route53_zone.bonus_b[0].zone_id
  ) : null
}

# Optional Route53 Hosted Zone (DNS validation path)
resource "aws_route53_zone" "bonus_b" {
  count = var.certificate_validation_method == "DNS" && var.create_route53_zone ? 1 : 0
  name  = var.domain_name
}

data "aws_route53_zone" "bonus_b" {
  count        = var.certificate_validation_method == "DNS" && !var.create_route53_zone ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

# ACM Certificate for app domain
resource "aws_acm_certificate" "bonus_b_cert" {
  domain_name       = local.app_fqdn
  validation_method = var.certificate_validation_method

  tags = {
    Name = "${local.name_prefix}-acm-${var.app_subdomain}"
  }
}

# DNS validation records (Route53)
resource "aws_route53_record" "bonus_b_cert_validation" {
  for_each = var.certificate_validation_method == "DNS" ? {
    for dvo in aws_acm_certificate.bonus_b_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = local.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "bonus_b_cert_validation" {
  count               = var.certificate_validation_method == "DNS" ? 1 : 0
  certificate_arn     = aws_acm_certificate.bonus_b_cert.arn
  validation_record_fqdns = [for r in aws_route53_record.bonus_b_cert_validation : r.fqdn]
}

# DNS record for app → ALB (Route53)
resource "aws_route53_record" "bonus_b_app_alias" {
  count   = var.certificate_validation_method == "DNS" ? 1 : 0
  zone_id = local.route53_zone_id
  name    = local.app_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.chrisbarm_alb01.dns_name
    zone_id                = aws_lb.chrisbarm_alb01.zone_id
    evaluate_target_health = true
  }
}

############################################
# ALB Security Group
############################################

resource "aws_security_group" "chrisbarm_alb_sg01" {
  name        = "${local.name_prefix}-alb-sg01"
  description = "ALB security group (HTTP/HTTPS)"
  vpc_id      = aws_vpc.chrisbarm_vpc01.id

  tags = {
    Name = "${local.name_prefix}-alb-sg01"
  }
}

resource "aws_vpc_security_group_ingress_rule" "chrisbarm_alb_sg_ingress_http" {
  ip_protocol       = local.tcp_protocol
  security_group_id = aws_security_group.chrisbarm_alb_sg01.id
  from_port         = local.ports_http
  to_port           = local.ports_http
  cidr_ipv4         = local.all_ip_address
}

resource "aws_vpc_security_group_ingress_rule" "chrisbarm_alb_sg_ingress_https" {
  ip_protocol       = local.tcp_protocol
  security_group_id = aws_security_group.chrisbarm_alb_sg01.id
  from_port         = local.ports_https
  to_port           = local.ports_https
  cidr_ipv4         = local.all_ip_address
}

resource "aws_vpc_security_group_egress_rule" "chrisbarm_alb_sg_egress_app" {
  ip_protocol                  = local.tcp_protocol
  security_group_id            = aws_security_group.chrisbarm_alb_sg01.id
  from_port                    = local.ports_http
  to_port                      = local.ports_http
  referenced_security_group_id = aws_security_group.chrisbarm_ec2_sg01.id
}

############################################
# Application Load Balancer
############################################

resource "aws_lb" "chrisbarm_alb01" {
  name               = "${local.name_prefix}-alb01"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.chrisbarm_alb_sg01.id]
  subnets            = aws_subnet.chrisbarm_public_subnets[*].id

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.chrisbarm_alb_logs_bucket01[0].bucket
      prefix  = var.alb_access_logs_prefix
      enabled = var.enable_alb_access_logs
    }
  }

  tags = {
    Name = "${local.name_prefix}-alb01"
  }
}

resource "aws_lb_target_group" "chrisbarm_alb_tg01" {
  name        = "${local.name_prefix}-tg01"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.chrisbarm_vpc01.id
  target_type = "instance"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
  }

  tags = {
    Name = "${local.name_prefix}-tg01"
  }
}

resource "aws_lb_target_group_attachment" "chrisbarm_alb_tg_attachment01" {
  target_group_arn = aws_lb_target_group.chrisbarm_alb_tg01.arn
  target_id        = aws_instance.chrisbarm_ec2_01.id
  port             = 80
}

resource "aws_lb_listener" "chrisbarm_alb_http" {
  load_balancer_arn = aws_lb.chrisbarm_alb01.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "chrisbarm_alb_https" {
  load_balancer_arn = aws_lb.chrisbarm_alb01.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.bonus_b_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.chrisbarm_alb_tg01.arn
  }

  depends_on = [aws_acm_certificate_validation.bonus_b_cert_validation]
}

############################################
# WAF (Optional)
############################################

resource "aws_wafv2_web_acl" "chrisbarm_alb_waf01" {
  count = var.enable_waf ? 1 : 0

  name  = "${local.name_prefix}-alb-waf01"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-alb-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "chrisbarm_alb_waf_assoc01" {
  count        = var.enable_waf ? 1 : 0
  resource_arn = aws_lb.chrisbarm_alb01.arn
  web_acl_arn  = aws_wafv2_web_acl.chrisbarm_alb_waf01[0].arn
}

############################################
# SNS + CloudWatch Alarm + Dashboard
############################################

resource "aws_sns_topic" "chrisbarm_sns_topic01" {
  name = "${local.name_prefix}-alb-alarms"
}

resource "aws_sns_topic_subscription" "chrisbarm_sns_email" {
  topic_arn = aws_sns_topic.chrisbarm_sns_topic01.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

resource "aws_cloudwatch_metric_alarm" "chrisbarm_alb_5xx_alarm" {
  alarm_name          = "${local.name_prefix}-alb-5xx"
  alarm_description   = "ALB 5xx spikes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alb_5xx_evaluation_periods
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = var.alb_5xx_period_seconds
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.chrisbarm_alb01.arn_suffix
  }

  alarm_actions = [aws_sns_topic.chrisbarm_sns_topic01.arn]
  ok_actions    = [aws_sns_topic.chrisbarm_sns_topic01.arn]
}

resource "aws_cloudwatch_dashboard" "chrisbarm_alb_dashboard01" {
  dashboard_name = "${local.name_prefix}-alb-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "ALB 5XX (ELB)"
          region  = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.chrisbarm_alb01.arn_suffix]
          ]
          stat   = "Sum"
          period = var.alb_5xx_period_seconds
        }
      }
    ]
  })
}
