Ready to Suffer? —here’s the next realism bump for Lab 1C-Bonus-D:
  1) Zone apex (chewbacca-growl.com) ALIAS → ALB
  2) ALB access logs → S3 bucket (with the required bucket policy)
  3) A couple of verification commands students can run to prove it’s working

Add this as bonus_b_logging_route53_apex.tf (or append to your existing Route53/logging file).

Add variables (append to variables.tf)
variable "enable_alb_access_logs" {
  description = "Enable ALB access logging to S3."
  type        = bool
  default     = true
}

variable "alb_access_logs_prefix" {
  description = "S3 prefix for ALB access logs."
  type        = string
  default     = "alb-access-logs"
}

Add file: bonus_b_logging_route53_apex.tf (go to Folder)

Patch reminder (students must modify the existing ALB resource)
Terraform can’t “append” nested blocks, so they must edit:
In bonus_b.tf, inside resource "aws_lb" "chewbacca_alb01" { ... } add:

  # Explanation: Chewbacca keeps flight logs—ALB access logs go to S3 for audits and incident response.
  access_logs {
    bucket  = aws_s3_bucket.chewbacca_alb_logs_bucket01[0].bucket
    prefix  = var.alb_access_logs_prefix
    enabled = var.enable_alb_access_logs
  }

Outputs (append to outputs.tf)

# Explanation: The apex URL is the front gate—humans type this when they forget subdomains.
output "chewbacca_apex_url_https" {
  value = "https://${var.domain_name}"
}

# Explanation: Log bucket name is where the footprints live—useful when hunting 5xx or WAF blocks.
output "chewbacca_alb_logs_bucket_name" {
  value = var.enable_alb_access_logs ? aws_s3_bucket.chewbacca_alb_logs_bucket01[0].bucket : null
}

Student verification (CLI) — DNS + Logs
1) Verify apex record exists
  aws route53 list-resource-record-sets \
    --hosted-zone-id <ZONE_ID> \
    --query "ResourceRecordSets[?Name=='chewbacca-growl.com.']"

2) Verify ALB logging is enabled
  aws elbv2 describe-load-balancers \
    --names chewbacca-alb01 \
    --query "LoadBalancers[0].LoadBalancerArn"

Then:
  aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn <ALB_ARN>

  Expected attributes include:
  access_logs.s3.enabled = true
  access_logs.s3.bucket = your bucket
  access_logs.s3.prefix = your prefix

3) Generate some traffic
  curl -I https://chewbacca-growl.com
  curl -I https://app.chewbacca-growl.com

4) Verify logs arrived in S3 (may take a few minutes)
  aws s3 ls s3://<BUCKET_NAME>/<PREFIX>/AWSLogs/<ACCOUNT_ID>/elasticloadbalancing/ --recursive | head


Why this matters to YOU (career-critical point)
This is incident response fuel:
  Access logs tell you:
    client IPs
    paths
    response codes
    target behavior
    latency

Combined with WAF logs/metrics and ALB 5xx alarms, you can do real triage:
  “Is it attackers, misroutes, or downstream failure?”










