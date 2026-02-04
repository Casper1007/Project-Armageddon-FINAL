# Lab 2: CloudFront Cache Policies & Performance Guide

## 🚀 CloudFront Caching Strategy

Your Lab 2 infrastructure uses a **two-tier caching strategy**:
- **API endpoints** (default): No caching (TTL = 0)
- **Static content** (/static/*): Aggressive caching (TTL = 1 day → 1 year)

---

## 📊 Cache Policy vs. Origin Request Policy

### Cache Policy (What Gets Cached)

**Purpose**: Determines **what varies the cache** and **how long to cache**

```hcl
resource "aws_cloudfront_cache_policy" "api_disabled" {
  default_ttl = 0       # ← How long CloudFront caches after origin response
  max_ttl     = 0       # ← Maximum cache time (even if origin says cache for 1 year)
  min_ttl     = 0       # ← Minimum cache time (even if origin says no-cache)

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "all"  # ← Include ALL cookies in cache key
      # This means: request with cookie A=1 cached separately from A=2
    }
    query_strings_config {
      query_string_behavior = "all"  # ← Include ALL query strings in cache key
      # This means: /page?sort=asc cached separately from /page?sort=desc
    }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization", "Host"]  # ← Include only these headers in cache key
      }
    }
  }
}
```

**Impact on Cache Hit Ratio**:
```
High TTL + Few cache key variables = High hit ratio (faster)
  Example: Static image /logo.png (TTL=1 year, no cookies/query strings)
  Cache key = just the URL
  100 requests to /logo.png = 99 cache hits

Low TTL + Many cache key variables = Low hit ratio (more origin requests)
  Example: API /users?id=123&token=xyz (TTL=0, all cookies/query/headers)
  Cache key = URL + all cookies + all query strings + auth headers
  Each unique user = different cache key
  100 requests from 50 different users = ~50 origin requests
```

### Origin Request Policy (What Gets Forwarded)

**Purpose**: Determines **what CloudFront sends to the origin** (WITHOUT including in cache key)

```hcl
resource "aws_cloudfront_origin_request_policy" "api" {
  cookies_config {
    cookie_behavior = "all"  # ← Forward ALL cookies to origin
  }
  query_strings_config {
    query_string_behavior = "all"  # ← Forward ALL query strings to origin
  }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Authorization", "Content-Type", "Origin", "Host"]  # ← Forward only these
    }
  }
}
```

**Key Difference**:
```
Cache Policy: "What makes this response DIFFERENT?"
  → If auth header differs, treat as different response (different cache entries)

Origin Request Policy: "What does the origin NEED to process the request?"
  → Forward the header even if it's not in the cache key
  → The origin still needs Authorization to know who's asking
```

---

## 🎯 Cache Policy Comparison

### Your Static Content Policy

```hcl
resource "aws_cloudfront_cache_policy" "chewbacca_cache_static01" {
  default_ttl = 86400        # 1 day
  max_ttl     = 31536000     # 1 year
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "none" }           # Ignore all cookies
    query_strings_config { query_string_behavior = "none" }  # Ignore all query strings
    headers_config { header_behavior = "none" }           # Ignore all headers
  }
}
```

**Why This Works for Static**:
```
Request 1: GET /static/logo.png (cookie: session=abc)
  → Cache miss, fetch from origin
  → Store in cache

Request 2: GET /static/logo.png (cookie: session=xyz)  [Different user, different session]
  → Cache HIT! (because logo.png cache key doesn't include cookies)
  → Serve from cache immediately
  → Saves origin bandwidth + speeds up response
```

**Cache Hit Ratio**: 99%+

---

### Your API Policy (No Caching)

```hcl
resource "aws_cloudfront_cache_policy" "chewbacca_cache_api_disabled01" {
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "all" }
    query_strings_config { query_string_behavior = "all" }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization", "Host"]
      }
    }
  }
}
```

**Why This Works for APIs**:
```
Request 1: GET /api/users?id=123 (auth: Bearer token123)
  → Cache miss (TTL=0, so always fetch)
  → Ask origin for user 123
  → Return response immediately

Request 2: GET /api/users?id=123 (auth: Bearer token789)  [Different user]
  → Would be different cache entry anyway (auth header in key)
  → But TTL=0 means don't cache anyway
  → Always ask origin for fresh data
```

**Cache Hit Ratio**: 0% (intentional)

---

## 📋 Path-Based Routing Example

Your distribution uses **ordered cache behaviors** to route requests:

```hcl
# Priority 1: Check if URL starts with /static/*
ordered_cache_behavior {
  path_pattern = "/static/*"
  cache_policy_id = aws_cloudfront_cache_policy.chewbacca_cache_static01.id
  # → All static files use aggressive caching
}

# Default: If no path pattern matches, use API policy
default_cache_behavior {
  cache_policy_id = aws_cloudfront_cache_policy.chewbacca_cache_api_disabled01.id
  # → Everything else (including /api/*) has no caching
}
```

**Request Flow**:
```
Request 1: GET /static/app.js
  ├─ Matches ordered_cache_behavior (/static/*)? YES
  ├─ Use static cache policy (TTL=1 day)
  ├─ Cache key = just URL (no cookies/query/headers)
  └─ Result: High cache hit ratio

Request 2: GET /api/users?id=123
  ├─ Matches ordered_cache_behavior (/static/*)? NO
  ├─ Use default cache behavior (API policy, TTL=0)
  ├─ Don't cache, always ask origin
  └─ Result: Always fresh data

Request 3: GET /about
  ├─ Matches ordered_cache_behavior (/static/*)? NO
  ├─ Use default cache behavior (API policy, TTL=0)
  ├─ Don't cache (unless you add another ordered_cache_behavior for /about)
  └─ Result: No caching (conservative approach)
```

---

## 🎛️ Tuning Cache Policies

### Scenario 1: High-Volume Blog (Cacheable Content)

```hcl
resource "aws_cloudfront_cache_policy" "blog_pages" {
  name        = "blog-pages-cache"
  default_ttl = 3600         # 1 hour
  max_ttl     = 604800       # 1 week
  min_ttl     = 300          # 5 minutes

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "none" }  # Blog doesn't use cookies
    query_strings_config { query_string_behavior = "none" }  # No query tracking
    headers_config { header_behavior = "none" }
  }
}

# Usage
ordered_cache_behavior {
  path_pattern = "/blog/*"
  cache_policy_id = aws_cloudfront_cache_policy.blog_pages.id
}
```

**Why This Works**:
- Blog posts don't change every second
- 1-hour cache means: if post updated, takes up to 1 hour to show new version
- But saves 90%+ of origin requests during that hour

---

### Scenario 2: Real-Time Leaderboard (Minimal Cache)

```hcl
resource "aws_cloudfront_cache_policy" "leaderboard_live" {
  name        = "leaderboard-nocache"
  default_ttl = 0
  max_ttl     = 60           # Max 1 minute cache (if origin says cache)
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "all" }
    query_strings_config { query_string_behavior = "all" }
    headers_config { header_behavior = "whitelist"; headers { items = ["Authorization"] } }
  }
}
```

**Why This Works**:
- Leaderboard needs real-time data
- TTL=0 means don't cache by default
- max_ttl=60 means even if origin says "cache for 1 hour," CloudFront limits to 1 minute
- Every request goes to origin

---

### Scenario 3: CDN-Optimized API (Selective Caching)

```hcl
resource "aws_cloudfront_cache_policy" "api_cacheable" {
  name        = "api-cacheable"
  default_ttl = 60           # Cache for 1 minute
  max_ttl     = 3600         # Max 1 hour
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "none" }  # API doesn't use cookies
    query_strings_config { query_string_behavior = "all" }  # Cache per query (user=123 vs user=456)
    headers_config { 
      header_behavior = "whitelist"
      headers { items = ["Authorization"] }  # Cache per user token
    }
  }
}
```

**Why This Works**:
- GET /api/products uses cache (data changes slowly)
- GET /api/products?category=electronics cached separately from category=books
- Different auth tokens get different cache entries
- 1-minute cache = 60+ requests to /api/products from same user served from cache
- Origin only called once per user per minute

---

## 📊 Response Headers Policy

Your static content policy adds explicit Cache-Control headers:

```hcl
resource "aws_cloudfront_response_headers_policy" "chewbacca_rsp_static01" {
  name = "${var.project_name}-rsp-static01"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      override = true  # ← Override origin's header
      value    = "public, max-age=86400, immutable"
    }
  }
}
```

**What This Does**:
```
CloudFront receives response from ALB
Original header: Cache-Control: no-cache

CloudFront response headers policy applies:
→ Override with: Cache-Control: public, max-age=86400, immutable

Browser receives:
  Cache-Control: public, max-age=86400, immutable
  → Store for 1 day in browser cache
  → Never validate with server

User's browser cache (separate from CloudFront cache):
  Request 1: GET /static/app.js → Fetch from CloudFront or origin
  Requests 2-1000: GET /static/app.js → Serve from browser cache (instant, zero network)
```

**Benefits**:
- Browser also caches (double-caching: CDN + browser)
- "immutable" flag tells browser: this file never changes (true for /static/app.js)
- Massive speed improvement for returning users

---

## ✅ Optimization Checklist

### Static Content
- [ ] Cache policy has high TTL (1 day to 1 year)
- [ ] Cache key excludes cookies/query strings (unless needed)
- [ ] Response headers policy sets Cache-Control headers
- [ ] Path pattern (/static/*) is exact
- [ ] Expected cache hit ratio: >95%

### API Endpoints
- [ ] Cache policy has TTL=0 (no caching)
- [ ] Cache key includes auth headers (Authorization)
- [ ] Cache key includes all query strings (for filtering)
- [ ] Origin request policy forwards all needed headers
- [ ] Expected cache hit ratio: 0% (intentional)

### Mixed Content
- [ ] Different ordered_cache_behavior for each path pattern
- [ ] Lower priority numbers checked first (highest precedence)
- [ ] Default behavior is conservative (no caching)
- [ ] Cache key variables are minimal but sufficient

---

## 🔍 Debugging Cache Issues

### Check Cache Hit Ratio

```bash
# Get cache metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name CacheHitRate \
  --dimensions Name=DistributionId,Value=$DIST_ID \
  --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Average

# Expected:
# Static endpoints: 80-99%
# API endpoints: 0% (or very low)
```

### Check Cache Headers in Response

```bash
# See what headers CloudFront returns
curl -I https://app.chewbacca-growl.com/static/logo.png

# Expected output:
# HTTP/2 200
# x-cache: Hit from cloudfront  ← Cache HIT
# x-amz-cf-cache-status: Hit
# cache-control: public, max-age=86400, immutable
# age: 3600  ← Cached for 1 hour

# Check API (should say Miss)
curl -I https://app.chewbacca-growl.com/api/users

# Expected output:
# HTTP/2 200
# x-cache: Miss from cloudfront  ← Cache MISS
# x-amz-cf-cache-status: Miss
# cache-control: no-cache  ← Don't cache
```

### Verify Cache Key Variables

```bash
# These should have the SAME cache key (should hit cache)
curl -I "https://app.chewbacca-growl.com/static/app.js"
curl -I "https://app.chewbacca-growl.com/static/app.js?v=1.0"
# Both should hit cache (query strings ignored for /static/*)

# These should have DIFFERENT cache keys (won't hit cache)
curl -I "https://app.chewbacca-growl.com/api/users?id=123&auth=token1"
curl -I "https://app.chewbacca-growl.com/api/users?id=123&auth=token2"
# Different because /api/* uses cache policy with all query strings in key
```

---

## 🚀 Production Recommendations

### Add More Path Patterns

```hcl
# Images: Cache for 30 days
ordered_cache_behavior {
  path_pattern = "/images/*"
  cache_policy_id = aws_cloudfront_cache_policy.images_cache.id
}

# CSS/JS: Cache for 1 year (but use versioned filenames: app-v1.0.js)
ordered_cache_behavior {
  path_pattern = "/assets/*"
  cache_policy_id = aws_cloudfront_cache_policy.assets_cache.id
}

# API: Cache for 5 minutes (for GET endpoints that return consistent data)
ordered_cache_behavior {
  path_pattern = "/api/public/*"
  cache_policy_id = aws_cloudfront_cache_policy.api_public_cache.id  # TTL=300
}

# Admin: Never cache
ordered_cache_behavior {
  path_pattern = "/admin/*"
  cache_policy_id = aws_cloudfront_cache_policy.no_cache.id  # TTL=0
}
```

### Cache Invalidation

```bash
# After deploying new code, invalidate cache
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/*"

# Or be more targeted
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/static/*" "/api/config/*"

# Check invalidation status
aws cloudfront get-invalidation \
  --distribution-id $DIST_ID \
  --id $INVALIDATION_ID
```

---

## 📚 Real-World Scenarios

### E-Commerce Product Page

```
User visits: https://app.example.com/product/123

Requests made:
  1. GET /product/123              → cache_policy=no-cache (TTL=0, dynamic HTML)
  2. GET /static/product-list.css  → cache_policy=static (TTL=1 year, cache hit)
  3. GET /static/app.js            → cache_policy=static (cache hit)
  4. GET /images/product-123.jpg   → cache_policy=images (TTL=30 days, cache hit)
  5. GET /api/reviews?product=123  → cache_policy=api (TTL=5 min, might cache if viewed recently)

Result:
  - 1 origin request (product HTML)
  - 4 CDN cache hits (CSS, JS, image, reviews)
  - Response time: <500ms (mostly from cache)
```

### SaaS Dashboard

```
User visits: https://app.example.com/dashboard

Requests:
  1. GET /dashboard               → no cache (TTL=0, user-specific)
  2. GET /static/dashboard.css    → cache (TTL=1 year)
  3. GET /api/user/profile        → no cache (TTL=0, auth required)
  4. GET /api/dashboard/widgets   → cache (TTL=1 min, low sensitivity)

Result:
  - 2-3 origin requests (app content + user-specific API)
  - 1-2 CDN cache hits (static assets)
  - Response time: 500-1000ms
```

---

**Document Version**: 1.0  
**Lab 2 Component**: CloudFront Caching Strategy  
**Last Updated**: January 21, 2026
