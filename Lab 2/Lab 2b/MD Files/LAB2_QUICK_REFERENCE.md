# Lab 2: Quick Reference Guide

## 🚀 Quick Start (5 minutes)

### Prerequisites
- [ ] Lab 1a deployed (EC2, RDS, security groups exist)
- [ ] Route53 zone created with domain registered
- [ ] ACM certificate created in **us-east-1** (critical!)

### Deploy Lab 2 in 3 Commands

```bash
# 1. Navigate to terraform directory
cd /path/to/terraform_restart_fixed

# 2. Plan deployment
terraform plan -out=tfplan | grep -E "(cloudfront|waf|route53)"

# 3. Deploy
terraform apply tfplan
```

**Expected Output**:
```
Apply complete! Resources added: 
  - 1x aws_cloudfront_distribution
  - 1x aws_wafv2_web_acl
  - 4x aws_route53_record
  - 1x aws_security_group_rule (ALB ingress)
  - 2x random_password (origin header secret)
```

---

## 🔐 Origin Cloaking: The Secret Sauce

### Layer 1: IP Restriction (Managed Prefix List)

```bash
# What it does: Only CloudFront IPs can hit ALB
# Code: aws_security_group_rule (ingress) + prefix_list_ids
# Why: Prevents random internet IPs from reaching ALB

# Test it:
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?LoadBalancerName==`chrisbarm-alb01`].DNSName' \
  --output text)

curl https://$ALB_DNS
# Expected: Timeout or "Connection refused"
```

### Layer 2: Custom Header (Secret Handshake)

```bash
# What it does: ALB only forwards requests with correct header
# Code: random_password + aws_lb_listener_rule (condition: http_header)
# Why: Blocks attackers who spoof CloudFront IPs

# Test it:
curl -H "X-Chrisbarm-Growl: wrong-secret" https://$ALB_DNS
# Expected: 403 Forbidden

curl -H "X-Chrisbarm-Growl: correct-secret" https://$ALB_DNS
# Expected: 200 OK (or app response)
```

### Layer 3: HTTPS Only

```bash
# What it does: ALB only accepts HTTPS from CloudFront
# Code: origin_protocol_policy = "https-only"
# Why: Encrypts traffic, prevents MITM

# Test it:
curl http://$ALB_DNS  # HTTP
# Expected: Connection refused (ALB not listening on 80)
```

---

## 🛡️ WAF Rules Comparison

| Rule | What It Blocks | When to Use |
|------|----------------|-----------|
| **Common RuleSet** | SQLi, XSS, LFI, RFI | ✅ Always |
| **Known Bad Inputs** | Malformed requests | ✅ API endpoints |
| **Rate-Based** | >2000 req/5min per IP | ✅ Public APIs |
| **Bot Control** | Automated scraping | ⚠️ Advanced (costs extra) |

---

## 📊 Files You Need

| File | Purpose | Status |
|------|---------|--------|
| `lab2_cloudfront_alb.tf` | Distribution + cache | ✅ Provided |
| `lab2_cloudfront_origin_cloaking.tf` | SG rule + header + passwords | ✅ Provided |
| `lab2_cloudfront_shield_waf.tf` | WAF rules (CLOUDFRONT scope) | ✅ Provided |
| `lab2_cloudfront_r53.tf` | Route53 records | ✅ NEW FILE |
| `verify_lab2_complete.sh` | CLI verification script | ✅ NEW FILE |

---

## ✅ Verification Checklist

### Quick Verification (2 minutes)

```bash
# 1. CloudFront domain resolves
dig chrisbdevsecops.com A +short
# Expected: CloudFront anycast IP (changes frequently)

# 2. CloudFront accessible
curl -I https://chrisbdevsecops.com
# Expected: 200 OK

# 3. Direct ALB blocked
curl -I https://$ALB_DNS
# Expected: Timeout or 403

# 4. WAF is CLOUDFRONT scope
aws wafv2 list-web-acls --scope CLOUDFRONT --query 'WebACLs[*].Name'
# Expected: lab2-cloudfront-waf (or similar)

# 5. Distribution has custom header
aws cloudfront get-distribution-config --id $DIST_ID | grep -i growl
# Expected: "X-Chrisbarm-Growl" present
```

### Full Verification (5 minutes)

```bash
# Run automated verification script
bash verify_lab2_complete.sh

# Expected output:
# ✓ TEST 1: Direct ALB access should fail (403)
# Expected: chrisbdevsecops.com and *.chrisbdevsecops.com
# ✓ TEST 3: DNS should point to CloudFront (not ALB)
# ✓ TEST 4: WAF scope should be CLOUDFRONT
# ✓ TEST 5: Origin header validation works
# ✓ BONUS: CloudFront cache headers present
```

---

## 🔑 Key Variables

### Required Variables (add to `variables.tf`)

```hcl
variable "cloudfront_acm_cert_arn" {
  description = "ACM certificate ARN in us-east-1 for CloudFront"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "domain_name" {
  description = "Domain name (e.g., chrisbdevsecops.com)"
  type        = string
}

variable "app_subdomain" {
  description = "App subdomain prefix (e.g., app)"
  type        = string
  default     = "app"
}
```

### Set Values (in `terraform.tfvars` or `-var` flag)

```hcl
cloudfront_acm_cert_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
route53_zone_id         = "Z1234567890ABC"
domain_name             = "chrisbdevsecops.com"
app_subdomain           = "app"
```

---

## 🐛 Troubleshooting

### Problem: CloudFront returns 502 Bad Gateway

```bash
# Cause: ALB not accessible (missing header or SG rule)
# Fix:

# 1. Verify SG rule exists
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=chrisbarm-alb-sg01" \
  --query 'SecurityGroups[0].IpPermissions' | grep cloudfront

# Expected: CloudFront prefix list ID present

# 2. Verify custom header is set
aws cloudfront get-distribution-config --id $DIST_ID | grep -i "customheader" -A 2

# Expected: X-Chrisbarm-Growl header present

# 3. Check ALB listener rule
aws elbv2 describe-listener-rules \
  --listener-arn $LISTENER_ARN \
  --query 'Rules[].Conditions'

# Expected: http_header condition with correct header name
```

### Problem: DNS doesn't resolve to CloudFront

```bash
# Cause: Route53 record not created or wrong
# Fix:

# 1. Check Route53 record
aws route53 list-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Name=='chrisbdevsecops.com.']"

# Expected: Alias record pointing to CloudFront

# 2. Check if record is alias (not CNAME)
# Alias should have: AliasTarget { HostedZoneId: <CF Zone ID>, DNSName: <CF domain> }

# 3. Wait for DNS propagation (up to 5 minutes)
for i in {1..12}; do
  dig chrisbdevsecops.com A +short
  sleep 10
done
```

### Problem: Certificate validation fails for CloudFront

```bash
# Cause: Certificate not in us-east-1 or not validated
# Fix:

# 1. Check certificate region
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query 'Certificate.Status'

# Expected: ISSUED

# 2. Check certificate domain names
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[*].DomainName'

# Expected: chrisbdevsecops.com and *.chrisbdevsecops.com

# 3. If not validated, complete DNS validation
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[].ValidationMail'
```

### Problem: WAF rule blocking legitimate traffic

```bash
# Cause: WAF rule too strict
# Fix:

# 1. Check WAF metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/WAFV2 \
  --metric-name BlockedRequests \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# 2. Check blocked request samples
aws wafv2 get-sampled-requests \
  --web-acl-arn $WAF_ARN \
  --rule-metric-name Common \
  --scope CLOUDFRONT \
  --time-window StartTime=$START,EndTime=$END \
  --max-items 10

# 3. Disable rule temporarily for debugging
terraform apply -var="waf_default_action=count"  # Log instead of block
```

---

## 📋 CLI Commands (Copy-Paste Ready)

### Get CloudFront Distribution ID

```bash
DIST_ID=$(aws cloudfront list-distributions \
  --query 'DistributionList.Items[?Aliases.Items[0]==`chrisbdevsecops.com`].Id' \
  --output text)
echo $DIST_ID
```

### Get ALB DNS

```bash
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?LoadBalancerName==`chrisbarm-alb01`].DNSName' \
  --output text)
echo $ALB_DNS
```

### Get CloudFront Custom Header (Secret)

```bash
# This is stored in Terraform state (secrets.tfstate)
terraform state show aws_random_password.chrisbarm_origin_header_value01 \
  | grep result
```

### Get Route53 Zone ID

```bash
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --query 'HostedZones[?Name==`chrisbdevsecops.com.`].Id' \
  --output text | cut -d'/' -f3)
echo $ZONE_ID
```

### Invalidate CloudFront Cache

```bash
# Use this after updating app to clear cached responses
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/*"

# Check invalidation progress
aws cloudfront get-invalidation --distribution-id $DIST_ID --id $INVALIDATION_ID
```

---

## 🎯 Interview Talking Points

### Q: "How do you prevent direct ALB access?"

A: "We use a managed prefix list from AWS that contains all CloudFront IP ranges. We add a security group rule that only allows HTTPS inbound from that prefix list. Additionally, CloudFront sends a custom 32-character header (X-Chrisbarm-Growl) that the ALB validates. If either check fails, the ALB returns 403. This is defense-in-depth—even if an attacker spoofs a CloudFront IP, they won't have the secret header."

### Q: "Why move WAF from ALB to CloudFront?"

A: "WAF at CloudFront edge filters attacks before they reach your VPC. This saves bandwidth and reduces origin load. It's also free for Shield Standard customers. You get the same WAF rules but at global distribution, not just the regional ALB."

### Q: "What happens if someone finds the ALB DNS name?"

A: "They can't access it. The security group rule only allows traffic from CloudFront IP ranges. If they somehow get a CloudFront IP range, they'd be blocked at the application layer because they don't have the custom header. If they somehow get both, they still need a valid SSL certificate that matches the ALB DNS name, which we've set to use CloudFront's certificate."

### Q: "How do you avoid DNS cache issues?"

A: "We use Route53 alias records (not CNAME). AWS manages the underlying IP resolution for us, so when CloudFront IPs change (which they do constantly due to their anycast architecture), Route53 automatically follows. We set TTL to 300 seconds to allow reasonably fast updates."

---

## 📊 Cost Estimate

| Component | Monthly Cost | Notes |
|-----------|--------------|-------|
| CloudFront | $0.085/GB | Data transfer OUT |
| CloudFront WAF | $20-50 | $5 base + $0.60/million requests |
| Route53 | $0.50/zone | Hosted zone + queries |
| ALB | ~$30 | $0.0225/hour |
| **Total** | **~$60-120** | Varies with traffic |

---

## 🔗 Real-World Examples

### E-Commerce Site

```
Customer → Route53 → CloudFront (cache product pages)
                   → ALB (shopping cart)
                   → Private EC2 (checkout)
                   → RDS (order database)
```

### SaaS Application

```
User → Route53 → CloudFront (static assets)
              → ALB (API gateway)
              → Private EC2 (business logic)
              → RDS + DynamoDB (data)
```

### Content Delivery Network

```
Viewer → Route53 → CloudFront (origin cloaking)
                 → ALB (video server)
                 → Private EC2 (transcoding)
                 → S3 (video storage)
```

---

## 📚 Useful AWS Documentation

- [CloudFront Distributions](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/distribution-web-awsmanagedproto.html)
- [WAFv2 WebACL](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl.html)
- [Route53 Alias Records](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html)
- [AWS Managed Prefix Lists](https://docs.aws.amazon.com/vpc/latest/userguide/managed-prefix-lists.html)

---

## ✨ Success Criteria

- ✅ Internet users access via `chrisbdevsecops.com` (Route53 → CloudFront)
- ✅ Direct ALB access blocked (returns 403 or times out)
- ✅ WAF applied at CloudFront edge (CLOUDFRONT scope, not regional)
- ✅ All traffic encrypted (HTTPS only)
- ✅ Origin cloaking enabled (prefix list + custom header)
- ✅ EC2 instances remain private (no public IP)

---

**Document Version**: 1.0  
**Lab 2 Focus**: CloudFront + Origin Cloaking + WAF Migration  
**Last Updated**: January 21, 2026
