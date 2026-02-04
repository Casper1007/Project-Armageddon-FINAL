# Lab 2: CloudFront + Origin Cloaking + WAF Architecture

## 🎯 Lab 2 Learning Objectives

- **Objective 1**: Understand how CloudFront acts as the single public entry point
- **Objective 2**: Implement origin cloaking to prevent ALB direct access
- **Objective 3**: Migrate WAF from regional (ALB) to global (CloudFront) scope
- **Objective 4**: Validate DNS points to CloudFront, not ALB
- **Objective 5**: Test edge-case security (direct ALB access fails with 403)

---

## 📐 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ 1. chrisbdevsecops.com
                        │    app.chrisbdevsecops.com
                        ↓
        ┌───────────────────────────────────┐
        │  Route53 (DNS)                    │
        │  Apex: CF distribution            │
        │  app:  CF distribution            │
        └───────────────────┬───────────────┘
                            │
                            │ 2. CloudFront Distribution
                            │    - WAF attached (CLOUDFRONT scope)
                            │    - Shield Standard (free DDoS)
                            │    - Cache + compression
                            ↓
        ┌───────────────────────────────────┐
        │  CloudFront (Global Edge)         │
        │  - Ingress: ✅ Internet (all)     │
        │  - Egress: ALB (via HTTPS)        │
        └───────────────────┬───────────────┘
                            │
                            │ 3. Custom header:
                            │    X-Chrisbarm-Growl
                            │    + CloudFront IP prefix list
                            ↓
        ┌───────────────────────────────────┐
        │  ALB (Application Load Balancer)  │
        │  - Ingress: ✅ CloudFront only    │
        │  - Ingress: ✅ Headers validated  │
        │  - Ingress: ❌ Direct access (403)│
        │  - Port: 443 HTTPS                │
        └───────────────────┬───────────────┘
                            │
                            │ 4. Application layer
                            │    (EC2 app servers)
                            ↓
        ┌───────────────────────────────────┐
        │  Private EC2 Instances (Lab 1a)   │
        │  - No public IP                   │
        │  - SSM Session Manager access     │
        │  - Talks to RDS                   │
        └───────────────────┬───────────────┘
                            │
                            │ 5. Database layer
                            ↓
        ┌───────────────────────────────────┐
        │  RDS MySQL (Lab 1a)               │
        │  - Private subnet                 │
        │  - Port 3306 (app only)           │
        └───────────────────────────────────┘
```

---

## 🔐 Origin Cloaking: Defense in Depth

### Problem: Why ALB Can't Be Public

If ALB had a public IP or was directly accessible:

```
❌ BAD: Internet → ALB (no CloudFront)
  - WAF not applied (if you have ALB WAF separate)
  - No caching (higher origin load)
  - No DDoS protection
  - Attackers bypass all controls
  - Direct database access possible
```

### Solution: Three-Layer Protection

#### Layer 1: AWS Managed Prefix List (IP Restriction)

```hcl
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group_rule" "alb_ingress_cf_only" {
  type              = "ingress"
  security_group_id = aws_security_group.chrisbarm_alb_sg01.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
}
```

**Why this works**:
- ✅ AWS maintains CloudFront IP ranges automatically
- ✅ Prevents direct ALB access from internet
- ✅ Stateless (firewall rule, not application logic)
- ✅ Free (no additional cost)

**What it blocks**:
```
❌ curl https://alb.elb.amazonaws.com  → Timeout or 403 (no matching SG rule)
❌ curl https://10.0.2.100:443         → Connection refused (not in CIDR)
```

#### Layer 2: Custom Origin Header (Secret Handshake)

```hcl
# CloudFront adds the header
custom_header {
  name  = "X-Chrisbarm-Growl"
  value = random_password.secret_origin_value.result
}

# ALB validates it
resource "aws_lb_listener_rule" "require_header" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 10
  action { type = "forward" ... }
  
  condition {
    http_header {
      http_header_name = "X-Chrisbarm-Growl"
      values           = [random_password.secret_origin_value.result]
    }
  }
}
```

**Why this works**:
- ✅ Second layer (defense-in-depth)
- ✅ Blocks attackers who spoof CloudFront IPs
- ✅ Secret is stored in Terraform state (only visible to infra team)
- ✅ Simple application-layer check

**What it blocks**:
```
❌ Attacker guesses CloudFront IP ranges and sends request → 403 (no header)
❌ Attacker adds fake header (X-Chrisbarm-Growl: random) → 403 (wrong value)
✅ CloudFront sends request with correct header → 200 (forwarded to target group)
```

#### Layer 3: HTTPS-Only Origin (TLS Mutual Trust)

```hcl
custom_origin_config {
  http_port              = 80    # Not used
  https_port             = 443   # Only this
  origin_protocol_policy = "https-only"  # ← Enforce HTTPS
  origin_ssl_protocols   = ["TLSv1.2"]   # ← No legacy SSL
}
```

**Why this works**:
- ✅ Encrypts traffic CloudFront → ALB
- ✅ Prevents man-in-the-middle (MITM)
- ✅ Validates ALB certificate (hostname matching)

---

## 🛡️ WAF Migration: Regional → Global

### Before (Lab 1C): WAF on ALB

```hcl
# Lab 1C (regional scope)
resource "aws_wafv2_web_acl" "alb_waf" {
  name  = "lab1c-alb-waf"
  scope = "REGIONAL"  # ← Attached to ALB in specific region
  # ... rules ...
}

resource "aws_wafv2_web_acl_association" "alb_waf_assoc" {
  resource_arn = aws_lb.chrisbarm_alb01.arn
  web_acl_arn  = aws_wafv2_web_acl.alb_waf.arn
}
```

**Problem**: WAF inspects traffic AFTER it reaches ALB
```
Internet → ALB (WAF here) → EC2
           ↑
           Traffic in VPC already (regional bandwidth)
```

### After (Lab 2): WAF on CloudFront

```hcl
# Lab 2 (global scope)
resource "aws_wafv2_web_acl" "cloudfront_waf" {
  name  = "lab2-cloudfront-waf"
  scope = "CLOUDFRONT"  # ← Global, at edge
  # ... rules ...
}

resource "aws_cloudfront_distribution" "chrisbarm_cf01" {
  web_acl_id = aws_wafv2_web_acl.cloudfront_waf.arn  # ← No separate association needed
  # ... other config ...
}
```

**Benefit**: WAF inspects traffic at CloudFront edge (reduces VPC bandwidth)
```
Internet → CloudFront (WAF here) → ALB → EC2
                ↑
                Malicious traffic filtered at edge
                No VPC bandwidth wasted
```

### WAF Rules Coverage

#### Common Rule Set (Always Include)

```hcl
# Protects against:
# - SQL injection (SQLi)
# - Cross-Site Scripting (XSS)
# - Local File Inclusion (LFI)
# - Remote File Inclusion (RFI)
rule {
  name     = "AWSManagedRulesCommonRuleSet"
  priority = 1
  override_action { none {} }
  
  statement {
    managed_rule_group_statement {
      name        = "AWSManagedRulesCommonRuleSet"
      vendor_name = "AWS"
    }
  }
  visibility_config { ... }
}
```

#### Known Bad Inputs Rule Set (Recommended)

```hcl
# Protects against patterns known to exploit services
rule {
  name     = "AWSManagedRulesKnownBadInputsRuleSet"
  priority = 2
  override_action { none {} }
  
  statement {
    managed_rule_group_statement {
      name        = "AWSManagedRulesKnownBadInputsRuleSet"
      vendor_name = "AWS"
    }
  }
  visibility_config { ... }
}
```

#### Rate-Based Rule (Recommended)

```hcl
# Blocks IPs exceeding request rate
rule {
  name     = "RateLimitRule"
  priority = 3
  action { block {} }
  
  statement {
    rate_based_statement {
      limit              = 2000  # 2000 requests per 5 min
      aggregate_key_type = "IP"
    }
  }
  visibility_config { ... }
}
```

#### Bot Control Rule Set (Optional, Advanced)

```hcl
# Detects and blocks malicious bots
rule {
  name     = "AWSManagedRulesBotControlRuleSet"
  priority = 4
  override_action { none {} }
  
  statement {
    managed_rule_group_statement {
      name        = "AWSManagedRulesBotControlRuleSet"
      vendor_name = "AWS"
    }
  }
  visibility_config { ... }
}
```

---

## 🌐 Route53 DNS Setup

### Requirement: Point Domains to CloudFront

```hcl
# lab2_cloudfront_r53.tf (NEW FILE)

# Apex domain: chrisbdevsecops.com → CloudFront
resource "aws_route53_record" "apex" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  
  alias {
    name                   = aws_cloudfront_distribution.chrisbarm_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.chrisbarm_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}

# App subdomain: app.chrisbdevsecops.com → CloudFront
resource "aws_route53_record" "app" {
  zone_id = var.route53_zone_id
  name    = "app.${var.domain_name}"
  type    = "A"
  
  alias {
    name                   = aws_cloudfront_distribution.chrisbarm_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.chrisbarm_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}

# IPv6 support (optional but recommended)
resource "aws_route53_record" "apex_aaaa" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "AAAA"
  
  alias {
    name                   = aws_cloudfront_distribution.chrisbarm_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.chrisbarm_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}
```

**Key Point**: Use `alias` record (not CNAME) for apex domain
- ✅ Route53 alias records allow CNAME-like behavior for apex
- ❌ CNAME cannot be used for apex (DNS standard limitation)
- ✅ Free queries (count toward Route53 query quota)

---

## 🔑 CloudFront ACM Certificate (us-east-1)

### Critical Constraint: Certificate Must Be in us-east-1

CloudFront **only accepts viewer certificates from us-east-1**. This is a hard AWS limitation.

#### Option A: Create Certificate in Code (Recommended)

```hcl
# Create second provider for us-east-1
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Create ACM cert in us-east-1
resource "aws_acm_certificate" "cloudfront_cert" {
  provider            = aws.us_east_1
  domain_name         = var.domain_name
  validation_method   = "DNS"
  subject_alternative_names = [
    "*.${var.domain_name}",  # Wildcard for all subdomains
    var.domain_name          # Apex
  ]
  
  tags = {
    Name = "${var.project_name}-cloudfront-cert"
  }
}

# Route53 DNS validation (optional automation)
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# Validate certificate
resource "aws_acm_certificate_validation" "cloudfront_cert" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.cloudfront_cert.arn
  
  timeouts {
    create = "5m"
  }
  
  depends_on = [aws_route53_record.cert_validation]
}
```

#### Option B: Manual Certificate + Data Source (Quick)

```hcl
# Manually create cert in us-east-1 console, then reference:
data "aws_acm_certificate" "cloudfront_cert" {
  provider = aws.us_east_1
  domain   = var.domain_name
  statuses = ["ISSUED"]
  most_recent = true
}

# Use in CloudFront
resource "aws_cloudfront_distribution" "chrisbarm_cf01" {
  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.cloudfront_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
```

---

## 📋 File Structure

Lab 2 requires 4 Terraform files:

```
Lab 2 Files:
├── lab2_cloudfront_alb.tf            ← Distribution + custom origin + WAF
├── lab2_cloudfront_origin_cloaking.tf ← SG rule + header validation
├── lab2_cloudfront_shield_waf.tf      ← WAF rules (CLOUDFRONT scope)
└── lab2_cloudfront_r53.tf             ← Route53 records (NEW)

Existing Lab 1a/1c Files (Keep Unchanged):
├── main.tf                   ← EC2, RDS, security groups
├── bonus_a.tf               ← VPC endpoints (if using Bonus A)
├── outputs.tf               ← Existing outputs
└── variables.tf             ← Existing variables
```

---

## 🚀 Deployment Order

1. **Ensure Lab 1a is deployed** (EC2, RDS, security groups exist)
2. **Create ACM certificate in us-east-1** (if not already done)
3. **Deploy lab2_cloudfront_shield_waf.tf** (WAF rules)
4. **Deploy lab2_cloudfront_origin_cloaking.tf** (SG rule, header, passwords)
5. **Deploy lab2_cloudfront_alb.tf** (CloudFront distribution)
6. **Deploy lab2_cloudfront_r53.tf** (DNS records)
7. **Verify** (see CLI tests below)

```bash
# Full deployment
cd terraform_restart_fixed
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# If issues, debug with:
terraform show | grep -A 20 "cloudfront_distribution"
```

---

## ✅ Verification Tests (CLI)

### Test 1: Direct ALB Access Should Fail (403)

```bash
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?LoadBalancerName==`chrisbarm-alb01`].DNSName' \
  --output text)

# Try to access directly
curl -v https://$ALB_DNS 2>&1 | grep -E "(403|403 Forbidden)"

# Expected output:
# < HTTP/1.1 403 Forbidden
# Reason: Missing X-Chrisbarm-Growl header
```

### Test 2: CloudFront Access Should Succeed (200)

```bash
# Test apex domain
curl -I https://chrisbdevsecops.com

# Expected output:
# HTTP/1.1 200 OK
# (or 301 if app redirects, then 200 on follow)

# Test app subdomain
curl -I https://app.chrisbdevsecops.com

# Expected output:
# HTTP/1.1 200 OK
```

### Test 3: DNS Points to CloudFront (Not ALB)

```bash
# Check apex DNS
dig chrisbdevsecops.com A +short
# Expected: CloudFront anycast IP (not ALB elastic IP)

# Check app subdomain DNS
dig app.chrisbdevsecops.com A +short
# Expected: Same CloudFront anycast IP

# Verify CloudFront distribution ID
aws cloudfront list-distributions \
  --query 'DistributionList.Items[?Aliases.Items[0]==`chrisbdevsecops.com`].Id' \
  --output text
```

### Test 4: WAF Scope is CLOUDFRONT

```bash
# Get WAF ACL
WAF_ID=$(aws wafv2 list-web-acls \
  --scope CLOUDFRONT \
  --query 'WebACLs[?Name==`lab2-cloudfront-waf`].Id' \
  --output text)

# Verify it's attached to CloudFront
aws cloudfront get-distribution \
  --id <DISTRIBUTION_ID> \
  --query 'Distribution.DistributionConfig.WebACLId'

# Expected output: arn:aws:wafv2:us-east-1:...:global/webacl/lab2-cloudfront-waf/...
```

### Test 5: CloudFront Origin Header Validation

```bash
# Try to spoof origin header
curl -v \
  -H "X-Chrisbarm-Growl: fake-value" \
  https://$ALB_DNS 2>&1 | grep -E "(403|403 Forbidden)"

# Expected: 403 (because header value doesn't match)

# Verify header is actually sent by CloudFront
curl -v https://chrisbdevsecops.com 2>&1 | grep -i "x-chrisbarm"
# (This may not show in curl output, but ALB logs will verify)
```

---

## 📊 Architecture Comparison

| Aspect | Lab 1a | Lab 1c | Lab 2 |
|--------|--------|--------|-------|
| **Public Entry** | EC2 (public IP) | ALB | CloudFront |
| **WAF** | None | ALB (regional) | CloudFront (global) |
| **Origin Cloaking** | None | None | ✅ Prefix list + header |
| **EC2 Access** | SSH | SSM + SSH | SSM only |
| **Caching** | None | None | ✅ CloudFront edge caching |
| **DDoS Protection** | None | Shield Std | Shield Std at edge |
| **CDN** | None | None | ✅ Global distribution |
| **Cost** | Low | Medium | High (data transfer) |

---

## 🎯 Key Takeaways

### 1. **CloudFront is the Only Public Door**
   - DNS points to CloudFront, not ALB
   - ALB is functionally private (only CloudFront can reach it)
   - Internet users never see ALB IP/DNS

### 2. **Defense in Depth (Three Layers)**
   - Layer 1: AWS managed prefix list (IP restriction)
   - Layer 2: Custom header validation (secret handshake)
   - Layer 3: HTTPS-only origin (TLS encryption)

### 3. **WAF at the Edge**
   - Moved from ALB (regional) to CloudFront (global)
   - Blocks attacks before they reach VPC
   - Reduces bandwidth to origin

### 4. **Certificate Constraint**
   - CloudFront viewer certs MUST be in us-east-1
   - This is a hard AWS limitation
   - Plan this early in deployment

### 5. **Route53 Alias Records**
   - Use alias records (not CNAME) for apex domain
   - Alias records are free queries
   - Both apex and subdomains point to same CloudFront distribution

---

## 📚 Real-World Use Cases

### E-Commerce (High Traffic)
```
Internet → CloudFront (caching product pages) 
         → ALB (sticky sessions for checkout)
         → Private EC2 (order processing)
         → RDS (inventory database)
```

### API Gateway Pattern
```
Internet → CloudFront (rate limiting via WAF)
         → ALB (request routing)
         → Private EC2 (API servers)
         → RDS + DynamoDB (data persistence)
```

### Financial Services (Compliance)
```
Internet → CloudFront + WAF (PCI-DSS requirement)
         → ALB + WAF (defense-in-depth)
         → Private EC2 + Secrets (sensitive processing)
         → RDS (encrypted data)
```

---

## 🔗 References

- [AWS CloudFront Origin Cloaking](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/distribution-web-awsmanagedproto.html)
- [WAFv2 CloudFront Scope](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl.html)
- [CloudFront Viewer Certificates](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html)
- [AWS Prefix Lists](https://docs.aws.amazon.com/vpc/latest/userguide/managed-prefix-lists.html)

---

**Document Version**: 1.0  
**Lab 2 Focus**: CloudFront + Origin Cloaking + WAF Migration  
**Prerequisites**: Lab 1a/1c infrastructure already deployed
