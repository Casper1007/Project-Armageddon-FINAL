output "bonus_b_alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.chrisbarm_alb01.dns_name
}

output "bonus_b_alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.chrisbarm_alb01.arn
}

output "bonus_b_target_group_arn" {
  description = "ALB target group ARN"
  value       = aws_lb_target_group.chrisbarm_alb_tg01.arn
}

output "bonus_b_acm_certificate_arn" {
  description = "ACM certificate ARN for the app domain"
  value       = aws_acm_certificate.bonus_b_cert.arn
}

output "bonus_b_waf_acl_arn" {
  description = "WAF ACL ARN (if enabled)"
  value       = var.enable_waf ? aws_wafv2_web_acl.chrisbarm_alb_waf01[0].arn : null
}

output "bonus_b_dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.chrisbarm_alb_dashboard01.dashboard_name
}

output "bonus_b_sns_topic_arn" {
  description = "SNS topic ARN for ALB alarms"
  value       = aws_sns_topic.chrisbarm_sns_topic01.arn
}
