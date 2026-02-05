output "bonus_d_apex_url_https" {
	description = "HTTPS URL for the apex domain"
	value       = "https://${var.domain_name}"
}

output "bonus_d_alb_logs_bucket_name" {
	description = "S3 bucket name for ALB access logs"
	value       = var.enable_alb_access_logs ? aws_s3_bucket.chrisbarm_alb_logs_bucket01[0].bucket : null
}
