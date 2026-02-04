# Explanation: Chrisbarm's caching strategy — aggressive for static, disabled for API

##############################################################
# 1) Cache Policy for Static Content (Aggressive)
##############################################################

# Explanation: Static files are the easy win—Chrisbarm caches them like hyperfuel for speed.
resource "aws_cloudfront_cache_policy" "chrisbarm_cache_static01" {
  name        = "${var.project_name}-cache-static01"
  comment     = "Aggressive caching for /static/*"
  default_ttl = 86400        # 1 day
  max_ttl     = 31536000     # 1 year
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    # Explanation: Static should not vary on cookies—Chrisbarm refuses to cache 10,000 versions of a PNG.
    cookies_config { cookie_behavior = "none" }

    # Explanation: Static should not vary on query strings (unless you do versioning); students can change later.
    query_strings_config { query_string_behavior = "none" }

    # Explanation: Keep headers out of cache key to maximize hit ratio.
    headers_config { header_behavior = "none" }

  }
}

##############################################################
# 2) Cache Policy for API (Safe Default: Caching Disabled)
##############################################################

# Explanation: APIs are dangerous to cache by accident—Chrisbarm disables caching until proven safe.
resource "aws_cloudfront_cache_policy" "chrisbarm_cache_api_disabled01" {
  name        = "${var.project_name}-cache-api-disabled01"
  comment     = "Disable caching for /api/* by default"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }

    # Explanation: Cache disabled — keep cache key minimal.
    headers_config { header_behavior = "none" }

  }
}

##############################################################
# 3) Origin Request Policy for API (Forward What Origin Needs)
##############################################################

# Explanation: Origins need context—Chrisbarm forwards what the app needs without polluting the cache key.
resource "aws_cloudfront_origin_request_policy" "chrisbarm_orp_api01" {
  name    = "${var.project_name}-orp-api01"
  comment = "Forward necessary values for API calls"

  cookies_config { cookie_behavior = "all" }
  query_strings_config { query_string_behavior = "all" }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Content-Type", "Origin", "Host"]
    }
  }
}

##############################################################
# 4) Origin Request Policy for Static (Minimal)
##############################################################

# Explanation: Static origins need almost nothing—Chrisbarm forwards minimal values for maximum cache sanity.
resource "aws_cloudfront_origin_request_policy" "chrisbarm_orp_static01" {
  name    = "${var.project_name}-orp-static01"
  comment = "Minimal forwarding for static assets"

  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "none" }
  headers_config { header_behavior = "none" }
}

##############################################################
# 5) Response Headers Policy (Optional But Nice)
##############################################################

# Explanation: Make caching intent explicit—Chrisbarm stamps Cache-Control so humans and CDNs agree.
resource "aws_cloudfront_response_headers_policy" "chrisbarm_rsp_static01" {
  name    = "${var.project_name}-rsp-static01"
  comment = "Add explicit Cache-Control for static content"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      override = true
      value    = "public, max-age=86400, immutable"
    }
  }
}

##############################################################
# Reference: Use these in distribution behaviors (see lab2_cloudfront_alb.tf)
##############################################################
# Default behavior (API): cache_policy_id = aws_cloudfront_cache_policy.chrisbarm_cache_api_disabled01.id
# Static behavior: cache_policy_id = aws_cloudfront_cache_policy.chrisbarm_cache_static01.id
