# Lab 2 Deliverables

## Deliverable A — Terraform
**Implemented in:**
- [lab2_cloudfront_cache_policies.tf](lab2_cloudfront_cache_policies.tf)
- [lab2_cloudfront_origin_cloaking.tf](lab2_cloudfront_origin_cloaking.tf)
- [lab2_cloudfront_alb.tf](lab2_cloudfront_alb.tf)

**Checklist:**
- Two cache policies
  - Static (aggressive caching): `aws_cloudfront_cache_policy.chrisbarm_cache_static01`
  - API (caching disabled): `aws_cloudfront_cache_policy.chrisbarm_cache_api_disabled01`
- Two origin request policies
  - Static minimal forwarding: `aws_cloudfront_origin_request_policy.chrisbarm_orp_static01`
  - API forwards required headers/query/cookies: `aws_cloudfront_origin_request_policy.chrisbarm_orp_api01`
- Two cache behaviors
  - `/static/*` → static policies: `ordered_cache_behavior` in CloudFront distribution
  - `/api/*` → API policies: `default_cache_behavior` (applies to `/api/*` since no other pattern matches)
- Be A Man Challenge
  - Response headers policy for explicit Cache-Control: `aws_cloudfront_response_headers_policy.chrisbarm_rsp_static01`

## Deliverable B — Correctness Proof (CLI Evidence)
### curl -I outputs (run attempt)
```
### static-1
HTTP/1.1 302 Found
Content-Type: text/html
Connection: keep-alive
X-WS-RateLimit-Limit: 1000
X-WS-RateLimit-Remaining: 999
Date: Mon, 02 Feb 2026 21:18:37 GMT
Server: Apache
Cache-Control: no-cache
Location: https://www.facebook.com/casperusf/static/example.txt

### static-2
HTTP/1.1 302 Found
Content-Type: text/html
Connection: keep-alive
X-WS-RateLimit-Limit: 1000
X-WS-RateLimit-Remaining: 998
Date: Mon, 02 Feb 2026 21:18:37 GMT
Server: Apache
Cache-Control: no-cache
Location: https://www.facebook.com/casperusf/static/example.txt

### api-1
HTTP/1.1 302 Found
Content-Type: text/html
Connection: keep-alive
X-WS-RateLimit-Limit: 1000
X-WS-RateLimit-Remaining: 997
Date: Mon, 02 Feb 2026 21:18:38 GMT
Server: Apache
Cache-Control: no-cache
Location: https://www.facebook.com/casperusf/api/list

### api-2
HTTP/1.1 302 Found
Content-Type: text/html
Connection: keep-alive
X-WS-RateLimit-Limit: 1000
X-WS-RateLimit-Remaining: 999
Date: Mon, 02 Feb 2026 21:18:38 GMT
Server: Apache
Cache-Control: no-cache
Location: https://www.facebook.com/casperusf/api/list

### static-v1
HTTP/1.1 302 Found
Content-Type: text/html
Connection: keep-alive
X-WS-RateLimit-Limit: 1000
X-WS-RateLimit-Remaining: 999
Date: Mon, 02 Feb 2026 21:18:38 GMT
Server: Apache
Cache-Control: no-cache
Location: https://www.facebook.com/casperusf/static/example.txt?v=1

### static-v2
HTTP/1.1 302 Found
Content-Type: text/html
Connection: keep-alive
X-WS-RateLimit-Limit: 1000
X-WS-RateLimit-Remaining: 998
Date: Mon, 02 Feb 2026 21:18:39 GMT
Server: Apache
Cache-Control: no-cache
Location: https://www.facebook.com/casperusf/static/example.txt?v=2
```

### Written explanation
**What is my cache key for `/api/*` and why?**
- Cache key includes **all cookies**, **all query strings**, and **whitelisted headers** (`Authorization`, `Host`).
- Reason: API responses can be user-specific and query-dependent. Including these avoids serving the wrong user’s data.

**What am I forwarding to origin and why?**
- API forwards **all cookies**, **all query strings**, and headers: `Authorization`, `Content-Type`, `Origin`, `Host`.
- Reason: the origin needs authentication context and request details, but not all headers should bloat cache key.

## Deliverable C — Haiku (漢字のみ)
剛毛誉高
忠義光満
銀河盾

## Deliverable D — Technical Verification (CLI)
> The DNS lookup failed in this environment. Re-run when the domain is resolvable.

### Static caching proof
Commands:
- `curl -I https://chrisbdevsecops.com/static/example.txt`
- `curl -I https://chrisbdevsecops.com/static/example.txt`

Expected:
- `Cache-Control: public, max-age=...`
- `Age` increases on second request

### API must NOT cache unsafe output
Commands:
- `curl -I https://chrisbdevsecops.com/api/list`
- `curl -I https://chrisbdevsecops.com/api/list`

Expected:
- `Age` absent or 0
- Fresh origin behavior

### Cache key sanity checks (query strings)
Commands:
- `curl -I "https://chrisbdevsecops.com/static/example.txt?v=1"`
- `curl -I "https://chrisbdevsecops.com/static/example.txt?v=2"`

Expected:
- Both map to same cached object

### Stale read after write safety test
If API supports writes:
1) POST a new row
2) Immediately GET `/api/list`
3) Confirm new row appears
