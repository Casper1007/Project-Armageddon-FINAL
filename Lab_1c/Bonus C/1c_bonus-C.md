Below is the Route53 add-on for Bonus-B (Hosted Zone + ACM DNS validation records + app.chrisbdevsecops.com ALIAS → ALB).
It’s written as a Terraform skeleton with Chewbacca comment style.

Add this as bonus_b_route53.tf.

Add to variables.tf (append)
variable "manage_route53_in_terraform" {
  description = "If true, create/manage Route53 hosted zone + records in Terraform."
  type        = bool
  default     = true
}

variable "route53_hosted_zone_id" {
  description = "If manage_route53_in_terraform=false, provide existing Hosted Zone ID for domain."
  type        = string
  default     = ""
}

Add file: bonus_b_route53.tf

Important note about the HTTPS listener
In your earlier bonus_b.tf, your HTTPS listener referenced:

certificate_arn = aws_acm_certificate_validation.chrisbarm_acm_validation01.certificate_arn

Now you have two possible validation resources (email/manual vs DNS). For the skeleton, do this pattern:
    Keep your original aws_acm_certificate_validation (email/manual) if you want
    OR switch the listener certificate ARN to the certificate itself and rely on validation dependency
Best skeleton approach (simple + works):
Update HTTPS listener to use:
  certificate_arn = aws_acm_certificate.chrisbarm_acm_cert01.arn

…and keep depends_on pointing at the DNS validation resource when DNS mode is used.
I’ll give you a clean patch below.

# Explanation: HTTPS listener is the real hangar bay — TLS terminates here, then traffic goes to private targets.
resource "aws_lb_listener" "chrisbarm_https_listener01" {
  load_balancer_arn = aws_lb.chrisbarm_alb01.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.chrisbarm_acm_cert01.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.chrisbarm_tg01.arn
  }

  # TODO: If DNS validation is enabled, ensure validation completes before listener creation.
  depends_on = [
    aws_acm_certificate_validation.chrisbarm_acm_validation01_dns_bonus
  ]
}


If you choose EMAIL validation instead, 
you can comment out the depends_on or set certificate_validation_method="EMAIL" 
and keep the listener creation after manual validation. (This is a skeleton; you’ll get some “learning friction” here.)

Continue bonus_b_route53.tf — ALIAS record app → ALB

############################################
# ALIAS record: app.chrisbdevsecops.com -> ALB
############################################

# Explanation: This is the holographic sign outside the cantina—app.chrisbdevsecops.com points to your ALB.
resource "aws_route53_record" "chrisbarm_app_alias01" {
  zone_id = local.chrisbarm_zone_id
  name    = local.chrisbarm_app_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.chrisbarm_alb01.dns_name
    zone_id                = aws_lb.chrisbarm_alb01.zone_id
    evaluate_target_health = true
  }
}

Add outputs (append to outputs.tf)
# Explanation: Outputs are the nav computer readout—Chewbacca needs coordinates that humans can paste into browsers.
output "chrisbarm_route53_zone_id" {
  value = local.chrisbarm_zone_id
}

output "chrisbarm_app_url_https" {
  value = "https://${var.app_subdomain}.${var.domain_name}"
}

Student verification (CLI)
1) Confirm hosted zone exists (if managed)
  aws route53 list-hosted-zones-by-name \
    --dns-name chrisbdevsecops.com \
    --query "HostedZones[].Id"

2) Confirm app record exists
  aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  --query "ResourceRecordSets[?Name=='app.chrisbdevsecops.com.']"

3) Confirm certificate issued
  aws acm describe-certificate \
  --certificate-arn <CERT_ARN> \
  --query "Certificate.Status"

Expected: ISSUED

4) Confirm HTTPS works
  curl -I https://app.chrisbdevsecops.com

Expected: HTTP/1.1 200 (or 301 then 200 depending on your app)

What YOU must understand (career point)
This is exactly how companies do it:
  DNS points to ingress
  TLS via ACM
  ALB handles secure public entry
  private compute does the work
  WAF + alarms defend and alert

When students can Terraform this, they’re doing real cloud engineering.












