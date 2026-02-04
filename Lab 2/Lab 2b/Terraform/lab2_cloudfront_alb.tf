# Explanation: CloudFront is the only public doorway — Chrisbarm stands behind it with private infrastructure.
# This file integrates all cache policies for optimal performance.

resource "aws_cloudfront_distribution" "chrisbarm_cf01" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.project_name}-cf01"

  origin {
    origin_id   = "${var.project_name}-alb-origin01"
    domain_name = aws_lb.chrisbarm_alb01.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Explanation: CloudFront whispers the secret growl — the ALB only trusts this.
    custom_header {
      name  = "X-Chrisbarm-Growl"
      value = random_password.chrisbarm_origin_header_value01.result
    }
  }

  # ═══════════════════════════════════════════════════════════════════════════════
  # DEFAULT CACHE BEHAVIOR: API endpoints (conservative caching)
  # ═══════════════════════════════════════════════════════════════════════════════
  default_cache_behavior {
    target_origin_id       = "${var.project_name}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    # Explanation: Default behavior is conservative—Chrisbarm assumes dynamic until proven static.
    cache_policy_id          = aws_cloudfront_cache_policy.chrisbarm_cache_api_disabled01.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.chrisbarm_orp_api01.id
  }

  # ═══════════════════════════════════════════════════════════════════════════════
  # ORDERED CACHE BEHAVIOR 1: Static content (aggressive caching)
  # ═══════════════════════════════════════════════════════════════════════════════
  # Explanation: Static behavior is the speed lane—Chrisbarm caches it hard for performance.
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "${var.project_name}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id            = aws_cloudfront_cache_policy.chrisbarm_cache_static01.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.chrisbarm_orp_static01.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.chrisbarm_rsp_static01.id
  }

  # ═══════════════════════════════════════════════════════════════════════════════
  # Optional: Additional cache behaviors for other paths
  # ═══════════════════════════════════════════════════════════════════════════════
  # Students can add more behaviors here (e.g., /assets/*, /images/*, etc.)
  # Lower priority = evaluated first, so /static/* is checked before default

  # Explanation: Attach WAF at the edge — now WAF moved to CloudFront.
  # Optional: set `var.cloudfront_web_acl_arn` if a WAF Web ACL is provisioned.
  web_acl_id = var.cloudfront_web_acl_arn

  # NOTE: The ACM cert must cover every alias you list here.
  aliases = [var.domain_name]

  # TODO: students must use ACM cert in us-east-1 for CloudFront
  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_acm_cert_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Explanation: Standard logging configuration (optional but recommended for production)
  # logging_config {
  #   include_cookies = false
  #   bucket          = aws_s3_bucket.cloudfront_logs.bucket_regional_domain_name
  #   prefix          = "logs/"
  # }
}

# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUTS: CloudFront Distribution Details
# ═══════════════════════════════════════════════════════════════════════════════

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.chrisbarm_cf01.id
}

output "cloudfront_distribution_domain_name" {
  description = "CloudFront distribution domain name (e.g., d1234.cloudfront.net)"
  value       = aws_cloudfront_distribution.chrisbarm_cf01.domain_name
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.chrisbarm_cf01.arn
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted zone ID (for Route53 alias records)"
  value       = aws_cloudfront_distribution.chrisbarm_cf01.hosted_zone_id
}

# ═══════════════════════════════════════════════════════════════════════════════
# CACHE POLICY REFERENCES (for debugging)
# ═══════════════════════════════════════════════════════════════════════════════

output "cache_policy_api_disabled_id" {
  description = "Cache policy ID for API (caching disabled)"
  value       = aws_cloudfront_cache_policy.chrisbarm_cache_api_disabled01.id
}

output "cache_policy_static_id" {
  description = "Cache policy ID for static content (aggressive caching)"
  value       = aws_cloudfront_cache_policy.chrisbarm_cache_static01.id
}

output "origin_request_policy_api_id" {
  description = "Origin request policy ID for API"
  value       = aws_cloudfront_origin_request_policy.chrisbarm_orp_api01.id
}

output "origin_request_policy_static_id" {
  description = "Origin request policy ID for static"
  value       = aws_cloudfront_origin_request_policy.chrisbarm_orp_static01.id
}

output "waf_web_acl_id" {
  description = "WAF Web ACL ID (CLOUDFRONT scope)"
  value       = aws_cloudfront_distribution.chrisbarm_cf01.web_acl_id
}
