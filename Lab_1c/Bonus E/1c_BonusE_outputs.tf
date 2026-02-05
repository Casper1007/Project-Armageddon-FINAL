output "bonus_e_waf_log_destination" {
  description = "Selected WAF log destination"
  value       = var.waf_log_destination
}

output "bonus_e_waf_cw_log_group_name" {
  description = "CloudWatch log group name for WAF logs (if enabled)"
  value       = var.waf_log_destination == "cloudwatch" ? aws_cloudwatch_log_group.chrisbarm_waf_log_group01[0].name : null
}

output "bonus_e_waf_logs_s3_bucket" {
  description = "S3 bucket for WAF logs (if enabled)"
  value       = var.waf_log_destination == "s3" ? aws_s3_bucket.chrisbarm_waf_logs_bucket01[0].bucket : null
}

output "bonus_e_waf_firehose_name" {
  description = "Firehose delivery stream name (if enabled)"
  value       = var.waf_log_destination == "firehose" ? aws_kinesis_firehose_delivery_stream.chrisbarm_waf_firehose01[0].name : null
}
