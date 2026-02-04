# Lab 2: CloudFront + ALB + WAF Code Review

## 📋 Executive Summary

Your Chewbacca Lab 2 architecture implements a **well-designed CDN + origin cloaking pattern** with solid security practices. The code demonstrates strong understanding of CloudFront distribution, origin validation, and WAF integration.

**Overall Assessment**: ⭐⭐⭐⭐ (Production-ready with minor refinements)

---

## ✅ Strengths

### 1. **Origin Cloaking Pattern (Excellent)**
```hcl
# CloudFront-only prefix list
data "aws_ec2_managed_prefix_list" "chewbacca_cf_origin_facing01"
# ALB accepts only CloudFront IPs
resource "aws_security_group_rule" "chewbacca_alb_ingress_cf44301"
```

**Why this is good**:
- ✅ Prevents direct ALB access (bypassing CloudFront/WAF)
- ✅ Uses AWS managed prefix list (auto-updated when CloudFront IPs change)
- ✅ Eliminates need for manual IP maintenance
- ✅ Defense-in-depth: custom header + IP restriction

**Real-world value**: This is how regulated orgs prevent DDoS bypass and API abuse.

---

### 2. **Custom Header Validation (Strong)**
```hcl
# CloudFront adds custom header
custom_header {
  name  = "X-Chewbacca-Growl"
  value = random_password.chewbacca_origin_header_value01.result
}

# ALB validates header
condition {
  http_header {
    http_header_name = "X-Chewbacca-Growl"
    values           = [random_password.chewbacca_origin_header_value01.result]
  }
}
```

**Why this is good**:
- ✅ Second layer of validation (IP list + header)
- ✅ Randomized header value (secure)
- ✅ Blocks attackers who spoof CloudFront IPs
- ✅ Simple but effective

**Security concept**: "Trust but verify" — even if IP matches CloudFront, header must match.

---

### 3. **WAF at CloudFront Edge (Strategic)**
```hcl
web_acl_id = aws_wafv2_web_acl.chewbacca_cf_waf01.arn
```

**Why this is good**:
- ✅ WAF inspects traffic before it reaches your infrastructure
- ✅ Stops malicious requests at edge (reduced VPC load)
- ✅ Lower latency (AWS edge locations globally)
- ✅ Blocks common attacks (SQL injection, XSS, bot traffic)

**Cost implication**: WAF charges are for CloudFront scope, not regional ALB scope.

---

### 4. **HTTPS Enforcement**
```hcl
viewer_protocol_policy = "redirect-to-https"
origin_protocol_policy = "https-only"
ssl_support_method       = "sni-only"
minimum_protocol_version = "TLSv1.2_2021"
```

**Why this is good**:
- ✅ Redirects HTTP → HTTPS (no plaintext)
- ✅ ALB communication encrypted
- ✅ Modern TLS versions only (no legacy SSL)
- ✅ SNI-only (cost-effective alternative to dedicated IPs)

---

### 5. **Sensible Cache Behavior**
```hcl
cached_methods  = ["GET", "HEAD"]
allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]

forwarded_values {
  query_string = true
  headers      = ["*"]
  cookies { forward = "all" }
}
```

**Why this is good**:
- ✅ Only caches GET/HEAD (not mutations)
- ✅ Forwards all headers/cookies/query strings to origin
- ✅ Prevents cache poisoning for API endpoints
- ✅ Allows origin to control caching (via Cache-Control headers)

---

### 6. **Geo-Restriction (Open but Configurable)**
```hcl
restrictions {
  geo_restriction {
    restriction_type = "none"
  }
}
```

**Why this is reasonable**:
- ✅ Allows global access (most apps need this)
- ✅ Can be changed to whitelist/blacklist specific countries
- ✅ WAF provides additional DDoS/attack filtering

---

## ⚠️ Issues & Improvements

### Issue 1: **Listener Rule Priority Bug**

**Current Code**:
```hcl
resource "aws_lb_listener_rule" "chewbacca_require_origin_header01" {
  listener_arn = aws_lb_listener.chewbacca_https_listener01.arn
  priority     = 10  # ← Custom rule
  action { type = "forward" ... }
}

resource "aws_lb_listener_rule" "chewbacca_default_block01" {
  listener_arn = aws_lb_listener.chewbacca_https_listener01.arn
  priority     = 99  # ← Catch-all rule
  action { type = "fixed-response" ... }
}
```

**Problem**: 
- ⚠️ Both rules match ALL paths (path_pattern not specified in first rule)
- ⚠️ Priority 10 always wins, so 99 never executes
- ⚠️ Non-CloudFront traffic with correct header gets through
- ⚠️ Non-CloudFront traffic WITHOUT header gets through (hits priority 10 and returns 403, but then what?)

**Fix**:
```hcl
# Require header - must come FIRST
resource "aws_lb_listener_rule" "chewbacca_require_origin_header01" {
  listener_arn = aws_lb_listener.chewbacca_https_listener01.arn
  priority     = 10
  action { type = "forward" ... }
  
  condition {
    http_header {
      http_header_name = "X-Chewbacca-Growl"
      values           = [random_password.chewbacca_origin_header_value01.result]
    }
  }
  # ← ADD path pattern if you have specific paths
  # condition {
  #   path_pattern { values = ["/api/*"] }
  # }
}

# Default DENY - catch everything else (lower priority = lower precedence)
resource "aws_lb_listener_rule" "chewbacca_default_block01" {
  listener_arn = aws_lb_listener.chewbacca_https_listener01.arn
  priority     = 100  # ← HIGHER number for lower precedence
  action { type = "fixed-response" ... }
  
  condition {
    path_pattern { values = ["*"] }  # ← Explicitly match all paths
  }
}
```

**Priority Note**: In ALB, **LOWER numbers = HIGHER priority**. Priority 1 runs first, then 2, then 3, etc.

---

### Issue 2: **Cache Policy (Recommended Improvement)**

**Current Code** (Deprecated):
```hcl
forwarded_values {
  query_string = true
  headers      = ["*"]
  cookies { forward = "all" }
}
```

**Problem**:
- ⚠️ Using legacy `forwarded_values` (deprecated in CloudFront)
- ⚠️ AWS recommends moving to `cache_policy_id` + `origin_request_policy_id`
- ⚠️ Newer patterns provide finer control

**Recommended Fix**:
```hcl
# For APIs that bypass cache entirely:
resource "aws_cloudfront_cache_policy" "chewbacca_api_nocache" {
  name        = "${var.project_name}-api-nocache"
  description = "No caching for API endpoints"
  
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0
  
  parameters_in_cache_key_and_forwarded_to_origin {
    query_strings_config { query_string_behavior = "all" }
    headers_config { header_behavior = "all" }
    cookies_config { cookie_behavior = "all" }
  }
}

resource "aws_cloudfront_origin_request_policy" "chewbacca_all_forward" {
  name        = "${var.project_name}-forward-all"
  description = "Forward all headers, query strings, cookies"
  
  headers_config { header_behavior = "allViewerAndCloudFrontHeaders" }
  query_strings_config { query_string_behavior = "all" }
  cookies_config { cookie_behavior = "all" }
}

# Use in distribution:
default_cache_behavior {
  target_origin_id       = "${var.project_name}-alb-origin01"
  viewer_protocol_policy = "redirect-to-https"
  
  allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
  cached_methods  = ["GET", "HEAD"]
  
  cache_policy_id            = aws_cloudfront_cache_policy.chewbacca_api_nocache.id
  origin_request_policy_id   = aws_cloudfront_origin_request_policy.chewbacca_all_forward.id
}
```

**Why**:
- ✅ Modern CloudFront pattern
- ✅ Clearer separation of concerns
- ✅ Better control over caching behavior
- ✅ Aligns with AWS best practices

---

### Issue 3: **WAF Rule Set Could Be More Comprehensive**

**Current Code**:
```hcl
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
}
```

**What's Good**:
- ✅ AWSManagedRulesCommonRuleSet covers most cases

**What's Missing** (Recommended Additions):
```hcl
# 1. Known Bad Inputs (SQL injection, XSS, etc.)
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
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-cf-waf-badinputs"
    sampled_requests_enabled   = true
  }
}

# 2. Bot Control (optional but realistic for public APIs)
rule {
  name     = "AWSManagedRulesBotControlRuleSet"
  priority = 3
  override_action { none {} }
  
  statement {
    managed_rule_group_statement {
      name        = "AWSManagedRulesBotControlRuleSet"
      vendor_name = "AWS"
    }
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-cf-waf-bot"
    sampled_requests_enabled   = true
  }
}

# 3. Rate-Based Rule (prevent abuse)
rule {
  name     = "RateLimitRule"
  priority = 4
  action { block {} }
  
  statement {
    rate_based_statement {
      limit              = 2000  # 2000 requests per 5 minutes
      aggregate_key_type = "IP"
    }
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-cf-waf-ratelimit"
    sampled_requests_enabled   = true
  }
}
```

**Why**:
- ✅ Blocks bots and automated attacks
- ✅ Rate limiting prevents API abuse
- ✅ Known bad inputs catch more attack patterns
- ✅ Production-grade security

---

### Issue 4: **Missing Logging Configuration**

**Current Code**: No WAF logging or CloudFront logging configured

**Recommendation**:
```hcl
# CloudWatch log group for WAF
resource "aws_cloudwatch_log_group" "chewbacca_cf_waf_logs" {
  name              = "/aws/wafv2/cloudfront/${var.project_name}"
  retention_in_days = 30
}

# WAF Logging
resource "aws_wafv2_web_acl_logging_configuration" "chewbacca_cf_waf_logging" {
  resource_arn            = aws_wafv2_web_acl.chewbacca_cf_waf01.arn
  log_destination_configs = [aws_cloudwatch_log_group.chewbacca_cf_waf_logs.arn]
}

# CloudFront Logging (to S3)
resource "aws_s3_bucket" "chewbacca_cf_logs" {
  bucket_prefix = "${var.project_name}-cf-logs-"
}

resource "aws_cloudfront_distribution" "chewbacca_cf01" {
  # ... existing config ...
  
  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.chewbacca_cf_logs.bucket_regional_domain_name
    prefix          = "logs/"
  }
}
```

**Why**:
- ✅ Compliance (audit trail for breaches)
- ✅ Forensics (understand attack patterns)
- ✅ Monitoring (set alarms on malicious requests)

---

### Issue 5: **Missing Custom Domain Configuration (TODOs Need Implementation)**

**Current Code**:
```hcl
aliases = [
  var.domain_name,
  "${var.app_subdomain}.${var.domain_name}"
]

viewer_certificate {
  acm_certificate_arn      = var.cloudfront_acm_cert_arn  # ← TODO by student
  ssl_support_method       = "sni-only"
  minimum_protocol_version = "TLSv1.2_2021"
}
```

**Current Assumptions**:
- ⚠️ Assumes ACM certificate exists in `us-east-1`
- ⚠️ Assumes certificate covers both domains
- ⚠️ No validation that certificate ARN is correct

**Recommended Enhancement**:
```hcl
# Option 1: Create ACM cert as part of this code (if domains are available)
resource "aws_acm_certificate" "chewbacca_cf_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  
  subject_alternative_names = [
    "${var.app_subdomain}.${var.domain_name}"
  ]
  
  tags = {
    Name = "${var.project_name}-cf-cert"
  }
}

# Option 2: Use data source if cert already exists
data "aws_acm_certificate" "chewbacca_cf_cert" {
  domain      = var.domain_name
  provider    = aws.us_east_1  # ← CRITICAL: CloudFront only works with us-east-1 certs
  statuses    = ["ISSUED"]
  most_recent = true
}

# In distribution:
viewer_certificate {
  acm_certificate_arn      = data.aws_acm_certificate.chewbacca_cf_cert.arn
  ssl_support_method       = "sni-only"
  minimum_protocol_version = "TLSv1.2_2021"
}
```

**Critical Note**: CloudFront certificates **MUST** be in `us-east-1`. This is a common deployment gotcha.

---

### Issue 6: **ALB Listener Missing HTTP Default**

**Observation**: Code shows HTTPS listener with header rules, but what about HTTP?

**Recommendation**:
```hcl
# HTTP listener (redirects to HTTPS)
resource "aws_lb_listener" "chewbacca_http_listener01" {
  load_balancer_arn = aws_lb.chewbacca_alb01.arn
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

# HTTPS listener (with validation rules)
resource "aws_lb_listener" "chewbacca_https_listener01" {
  load_balancer_arn = aws_lb.chewbacca_alb01.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.alb_acm_cert_arn
  
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}
```

**Why**:
- ✅ Enforces HTTPS everywhere
- ✅ Blocks direct HTTP access to ALB
- ✅ Only CloudFront can reach ALB (via HTTPS + header)

---

## 🔐 Security Assessment

| Area | Rating | Notes |
|------|--------|-------|
| **Origin Cloaking** | ⭐⭐⭐⭐⭐ | Excellent: IP list + custom header |
| **WAF Coverage** | ⭐⭐⭐⭐ | Good: Common RuleSet; missing Bot+Rate rules |
| **TLS/Encryption** | ⭐⭐⭐⭐⭐ | Excellent: HTTPS-only, modern TLS |
| **Logging** | ⭐⭐⭐ | Missing: No CloudFront logs, no WAF logs |
| **Cache Strategy** | ⭐⭐⭐⭐ | Good: Cache bypassed for mutations; could use new `cache_policy_id` pattern |
| **IP Reputation** | ⭐⭐⭐⭐ | Good: Uses managed prefix list (auto-updated) |

**Overall**: Production-ready with recommended hardening.

---

## 💰 Cost Implications

| Component | Pricing | Estimate |
|-----------|---------|----------|
| **CloudFront** | Data transfer OUT | $0.085/GB (US) |
| **CloudFront WAF** | $5.00/month + $0.60/million requests | ~$20-50/month |
| **ALB** | $0.0225/hour + $0.006/LCU | ~$30/month + LCU |
| **Data Transfer (VPC→ALB)** | Free (internal AWS) | $0 |
| **ACM Certificate** | Free | $0 |
| **S3 Logging** | $0.023/1000 requests | ~$1-5/month |

**Total Estimated Monthly**: $60-100 (varies with traffic)

---

## 🚀 Production Readiness Checklist

- ✅ Origin cloaking (IP + header validation)
- ✅ WAF at edge
- ✅ HTTPS enforcement
- ⚠️ WAF rules incomplete (missing Bot, Rate limiting)
- ⚠️ Logging not configured
- ⚠️ Cache policy uses deprecated pattern (should use `cache_policy_id`)
- ❌ Missing ACM certificate setup (TODO item)
- ❌ Missing ALB HTTP→HTTPS redirect
- ✅ Custom domain support (with TODOs)

**Recommendation**: Deploy with Issue 1 (priority bug) fixed, then address Issue 3 (WAF rules) and Issue 4 (logging) before going to production.

---

## 📋 Recommended Next Steps

### Phase 1 (Critical - Fix Before Deploy)
1. Fix ALB listener rule priority logic (Issue 1)
2. Add HTTP→HTTPS redirect listener
3. Verify ACM certificate exists in us-east-1
4. Test custom header validation

### Phase 2 (Recommended - Before Production)
1. Migrate to `cache_policy_id` + `origin_request_policy_id` (Issue 2)
2. Add comprehensive WAF rules (Bot, Known Bad, Rate) (Issue 3)
3. Configure CloudFront logging to S3 (Issue 4)
4. Configure WAF logging to CloudWatch (Issue 4)

### Phase 3 (Nice to Have)
1. Add CloudFront Origin Shield (extra caching layer)
2. Configure cache invalidation on deployment
3. Add monitoring/alarms for WAF blocks
4. Document origin cloaking in runbook

---

## 🎯 Interview-Ready Talking Points

**"Explain your origin cloaking strategy"**
> "We use two layers: First, we restrict ALB ingress to CloudFront IP ranges via a managed prefix list (auto-updated by AWS). Second, CloudFront adds a custom 32-character header that we validate at the ALB listener level. If either check fails, the ALB returns 403. This prevents attackers from bypassing CloudFront/WAF by hitting the ALB directly. Combined with WAF at the edge, it's a defense-in-depth approach."

**"Why not directly expose the ALB?"**
> "CloudFront gives us three things: (1) WAF at the edge—blocks attacks before reaching VPC. (2) Global caching—reduces origin load. (3) DDoS protection via AWS Shield Standard. If we exposed the ALB directly, we'd lose edge filtering and have no WAF without additional cost."

**"How do you handle cache invalidation?"**
> "Since we're setting TTL=0 for API endpoints, cache invalidation isn't needed—every request goes to origin. For static assets, we'd use CloudFront invalidation on deployment, or implement versioned URLs (e.g., /assets/v1.2.3/app.js)."

---

## ✨ Summary

**Strengths**:
- ✅ Solid origin cloaking (IP + header)
- ✅ WAF at edge (good decision)
- ✅ Modern TLS configuration
- ✅ Sensible cache strategy for APIs

**Areas for Improvement**:
- ⚠️ ALB rule priority logic needs fixing
- ⚠️ WAF rules need expansion (Bot, Rate limiting)
- ⚠️ Logging not configured
- ⚠️ Cache policy uses deprecated pattern
- ⚠️ Missing HTTP→HTTPS redirect

**Assessment**: **4.5/5 stars** - Production-ready with recommended refinements

---

**Document Version**: 1.0  
**Review Date**: January 21, 2026
