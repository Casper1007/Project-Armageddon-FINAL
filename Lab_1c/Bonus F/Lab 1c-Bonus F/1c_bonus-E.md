Key update since “the old days”: AWS WAF logging can go directly to CloudWatch Logs, S3, or Kinesis Data Firehose, 
and you can associate one destination per Web ACL. Also, the destination name must start with aws-waf-logs-. 


Terraform supports this with aws_wafv2_web_acl_logging_configuration. 
Terraform Registry

Below is Lab 1C-Bonus-E (continued): WAF logging in Terraform (with toggles), plus verification commands.

1) Add variables (append to variables.tf)
variable "waf_log_destination" {
  description = "Choose ONE destination per WebACL: cloudwatch | s3 | firehose"
  type        = string
  default     = "cloudwatch"
}

variable "waf_log_retention_days" {
  description = "Retention for WAF CloudWatch log group."
  type        = number
  default     = 14
}

variable "enable_waf_sampled_requests_only" {
  description = "If true, students can optionally filter/redact fields later. (Placeholder toggle.)"
  type        = bool
  default     = false
}


2) Add file: bonus_b_waf_logging.tf (Look in Folder)

This provides three skeleton options (CloudWatch / S3 / Firehose). Students choose one via var.waf_log_destination.


3) Outputs (append to outputs.tf)
# Explanation: Coordinates for the WAF log destination—Chewbacca wants to know where the footprints landed.
output "chewbacca_waf_log_destination" {
  value = var.waf_log_destination
}

output "chewbacca_waf_cw_log_group_name" {
  value = var.waf_log_destination == "cloudwatch" ? aws_cloudwatch_log_group.chewbacca_waf_log_group01[0].name : null
}

output "chewbacca_waf_logs_s3_bucket" {
  value = var.waf_log_destination == "s3" ? aws_s3_bucket.chewbacca_waf_logs_bucket01[0].bucket : null
}

output "chewbacca_waf_firehose_name" {
  value = var.waf_log_destination == "firehose" ? aws_kinesis_firehose_delivery_stream.chewbacca_waf_firehose01[0].name : null
}


4) Student verification (CLI)
A) Confirm WAF logging is enabled (authoritative)
  aws wafv2 get-logging-configuration \
    --resource-arn <WEB_ACL_ARN>

Expected: LogDestinationConfigs contains exactly one destination.

B) Generate traffic (hits + blocks)
  curl -I https://chewbacca-growl.com/
  curl -I https://app.chewbacca-growl.com/

C1) If CloudWatch Logs destination
  aws logs describe-log-streams \
  --log-group-name aws-waf-logs-<project>-webacl01 \
  --order-by LastEventTime --descending

Then pull recent events:
  aws logs filter-log-events \
  --log-group-name aws-waf-logs-<project>-webacl01 \
  --max-items 20

C2) If S3 destination
  aws s3 ls s3://aws-waf-logs-<project>-<account_id>/ --recursive | head

C3) If Firehose destination
  aws firehose describe-delivery-stream \
  --delivery-stream-name aws-waf-logs-<project>-firehose01 \
  --query "DeliveryStreamDescription.DeliveryStreamStatus"

And confirm objects land:
  aws s3 ls s3://<firehose_dest_bucket>/waf-logs/ --recursive | head

5) Why this makes incident response “real”
Now you can answer questions like:
  “Are 5xx caused by attackers or backend failure?”
  “Do we see WAF blocks spike before ALB 5xx?”
  “What paths / IPs are hammering the app?”
  “Is it one client, one ASN, one country, or broad?”
  “Did WAF mitigate, or are we failing downstream?”

This is precisely why WAF logging destinations include CloudWatch Logs (fast search) and S3/Firehose (archive/SIEM pipeline)












