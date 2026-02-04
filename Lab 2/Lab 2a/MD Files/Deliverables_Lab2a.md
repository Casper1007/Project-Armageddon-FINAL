---
## Lab 2B-Honors++: CloudFront Validators, RefreshHit, and Conditional Requests

### Key Mental Model

| x-cache value                | Meaning                                                                  |
| ---------------------------- | ------------------------------------------------------------------------ |
| `Hit from cloudfront`        | Served entirely from cache                                               |
| `Miss from cloudfront`       | Fetched from origin                                                      |
| `RefreshHit from cloudfront` | Cached object existed, but CloudFront **revalidated** it with the origin |
| `Error from cloudfront`      | Origin or edge error                                                     |

**RefreshHit** means CloudFront had a cached copy, TTL expired, and it revalidated with the origin using conditional headers (If-None-Match, If-Modified-Since). If the origin returns 304 Not Modified, CloudFront reuses the cached body, saving bandwidth and origin load, with slightly higher latency than a Hit.

### Required App Change (EC2 Origin)
- Modify a static or semi-static endpoint (e.g., /static/index.html) to send at least one validator header (ETag or Last-Modified).
- Example:
	- Cache-Control: public, max-age=30
	- ETag: "chewie-v1"

### Investigation Steps
1. Observe headers with repeated curl requests after TTL expires:
	 - First: Miss
	 - Next within TTL: Hit
	 - After TTL: RefreshHit
2. Identify ETag or Last-Modified in response.
3. Explain RefreshHit:
	 > "CloudFront had a cached copy, but TTL expired. It sent a conditional request to the origin using validators. The origin returned 304 Not Modified, so CloudFront reused the cached body."

### Proving It’s NOT a Full Miss
- Wait for TTL, then curl again.
- Evidence: x-cache: RefreshHit from cloudfront, body unchanged, latency slightly higher than Hit.
- Bandwidth saved, origin load reduced, correct behavior.

### Failure Injection B: Stale Content with Unchanged Validator
- If content changes but ETag/Last-Modified is not updated, CloudFront keeps getting 304 and users see stale content (RefreshHit continues).
- Correct fix: Update ETag or Last-Modified. Invalidate only in emergencies.

### Controlled Invalidation
```sh
aws cloudfront create-invalidation \
	--distribution-id <DIST_ID> \
	--paths "/static/index.html"
```
Explain: Invalidation forces CloudFront to fetch a new copy, but updating validators is preferred for normal updates.

### Log Interpretation
- ALB logs: Look for If-None-Match and 304 responses.
- CloudFront logs: x-edge-result-type = RefreshHit, sc-status = 304.

### One-Paragraph Takeaway
> **What does RefreshHit mean, and why is it often better than a Miss?**
> RefreshHit means CloudFront had a cached object, but the TTL expired. Instead of fetching the full object, CloudFront sent a conditional request to the origin using ETag or Last-Modified. If the origin replied 304 Not Modified, CloudFront reused the cached body, saving bandwidth and reducing origin load. This is more efficient than a full Miss, as it delivers fresh content with less resource usage and lower latency than a full fetch.
---
---
## Lab 2B-Honors+: CloudFront Invalidation as a Controlled Operation

### Part A — “Break Glass” Invalidation Procedure (CLI)

**Invalidate a single file:**
```
aws cloudfront create-invalidation \
	--distribution-id <DISTRIBUTION_ID> \
	--paths "/static/index.html"
```

**Invalidate a wildcard path:**
```
aws cloudfront create-invalidation \
	--distribution-id <DISTRIBUTION_ID> \
	--paths "/static/*"
```

---
## lab2b_cache_correctness.tf (CloudFront + API Caching Correctness Overlay)
```hcl
**Track invalidation completion:**
```
aws cloudfront get-invalidation \
	--distribution-id <DISTRIBUTION_ID> \
	--id <INVALIDATION_ID>
```

### Part B — Correctness Proof Checklist

**1. Before invalidation: Prove object is cached**
```
curl -i https://<your-domain-or-cloudfront-url>/static/index.html | sed -n '1,30p'
curl -i https://<your-domain-or-cloudfront-url>/static/index.html | sed -n '1,30p'
```
Expected: Age increases, x-cache shows Hit from cloudfront

**2. Deploy change (simulate):**
- Update index.html at origin

**3. After invalidation: Prove cache refresh**
```
aws cloudfront create-invalidation --distribution-id <DISTRIBUTION_ID> --paths "/static/index.html"
curl -i https://<your-domain-or-cloudfront-url>/static/index.html | sed -n '1,30p'
```
Expected: x-cache is Miss or RefreshHit, new content served

### Part D — Incident Scenario: “Stale index.html after deployment”
**Incident Note:**
> After deploying a new version of index.html, users continued to receive the old cached version due to CloudFront’s cache. Versioned static assets did not require invalidation, but the HTML entrypoint did. We invalidated /static/index.html (not /*) to refresh the cache and verified new content was served. This minimized blast radius and followed operational policy.

### Part E — “Smart” Upgrade (Extra Credit)
**When not to invalidate:**
If only versioned assets (e.g., /static/app.<hash>.js) change, invalidation is unnecessary. Deploying new files with unique names ensures users get the latest assets without cache issues.

**Invalidation budget:**
- Monthly invalidation path budget: 200
- Wildcard usage: Only for urgent, broad fixes (e.g., /static/* if many files are corrupted)
- Approval workflow: /* invalidation requires documented justification and team lead approval

### Policy Paragraph
**When do we invalidate?**
Invalidate only for entrypoint files (e.g., /static/index.html) when content changes and users are receiving stale data, or in break-glass scenarios (security, legal, corruption).

**When do we version instead?**
Always version static assets (e.g., /static/app.<hash>.js) for normal deployments; this avoids the need for invalidation.

**Why is /* restricted?**
Invalidating /* is reserved for emergencies due to its high cost and risk. It should only be used for security incidents, legal takedowns, or catastrophic misconfigurations, and must be documented and approved.
---
---
## Lab 2B-Honors: Origin-Driven Caching

### Endpoints Implemented
- **GET /api/public-feed**: Cacheable, returns server time and message
	- `Cache-Control: public, s-maxage=30, max-age=0`
- **GET /api/list**: Private, never cached
	- `Cache-Control: private, no-store`

### CloudFront Honors Origin Cache-Control (Evidence)

#### 1. First request (should be MISS)
```
curl -i https://chewbacca-growl.com/api/public-feed | sed -n '1,20p'
```
Expected headers:
```
Cache-Control: public, s-maxage=30, max-age=0
x-cache: Miss from cloudfront
Age: (absent or 0)
```

#### 2. Second request within 30s (should be HIT)
```
curl -i https://<your-domain-or-cloudfront-url>/api/public-feed | sed -n '1,20p'
```
Expected headers:
```
x-cache: Hit from cloudfront
Age: (increases)
```

#### 3. After 35s (should MISS again)
```
sleep 35
curl -i https://<your-domain-or-cloudfront-url>/api/public-feed | sed -n '1,20p'
```
Expected: x-cache: Miss or RefreshHit, body updates

#### 4. /api/list (never cached)
```
curl -i https://<your-domain-or-cloudfront-url>/api/list | sed -n '1,30p'
```
Expected headers:
```
Cache-Control: private, no-store
x-cache: Miss from cloudfront (never Hit)
Age: (absent or 0)
```

### Why origin-driven caching is safer for APIs
Origin-driven caching lets the backend explicitly control what is cacheable and for how long, reducing the risk of serving stale or sensitive data. It allows dynamic endpoints to be safely cached when appropriate, while ensuring private or user-specific data is never cached. This is safer than static cache policies, which may not adapt to endpoint-specific needs.

**Disable caching entirely** for endpoints with sensitive, user-specific, or rapidly changing data, or when the risk of data leakage outweighs performance gains.

---
---
## Safe Caching Evidence: Beron Da Saluki Criteria

### 1. Implementation: Cache-Control Header
The `/list` endpoint sets the following header in the Flask response:

```
Cache-Control: public, max-age=30
```

### 2. Demonstration (Evidence)
Example curl command and output:

```
curl -I https://<your-domain-or-cloudfront-url>/list
```

Expected output (headers):

```
HTTP/2 200
content-type: application/json
cache-control: public, max-age=30
...other headers...
```

### 3. Why Cache-Control is Preferred
The `Cache-Control` header is the industry standard for controlling HTTP caching behavior. It allows the origin server to specify exactly how responses should be cached by browsers, CDNs, and proxies. Using `public, max-age=30` ensures that the response can be cached by any cache (not just the browser) for 30 seconds, improving performance and reducing backend load, while minimizing the risk of serving stale or sensitive data. This explicit control is safer and more predictable than relying on default or implicit caching behaviors.
---
## Lab 2 Terraform Outputs

```
bonus_a_instance_id = "i-065f3617be024702e"
bonus_a_instance_private_ip = "10.0.101.13"
bonus_a_instance_public_ip = ""
bonus_a_session_manager_ready = "aws ssm start-session --target i-065f3617be024702e --region us-east-1"
bonus_a_vpc_endpoints = {
	"cloudwatch_logs" = "vpce-0da49b0a3c7f3bc82"
	"ec2messages" = "vpce-0172ac9681b8e70e2"
	"kms" = "vpce-0bf0b8a8a29087662"
	"s3_gateway" = "vpce-0ac1084ac09e9958a"
	"secretsmanager" = "vpce-0ca3f1060a0b98378"
	"ssm" = "vpce-0729e5d3d8266f055"
	"ssmmessages" = "vpce-005631b38b14d7cc6"
}
chrisbarm_alb_arn01 = "arn:aws:elasticloadbalancing:us-east-1:198547498722:loadbalancer/app/chrisbarm-alb01/c9549f0cda36ba91"
chrisbarm_alb_dns_name01 = "chrisbarm-alb01-1147982951.us-east-1.elb.amazonaws.com"
chrisbarm_http_listener_arn01 = "arn:aws:elasticloadbalancing:us-east-1:198547498722:listener/app/chrisbarm-alb01/c9549f0cda36ba91/032d9d366867ac35"
chrisbarm_log_group_name = "/aws/ec2/chrisbarm-rds-app"
chrisbarm_private_subnet_ids = [
	"subnet-0a04c8671392e0074",
	"subnet-05a7989e075e5fc1d",
]
chrisbarm_public_subnet_ids = [
	"subnet-0c42249970450265d",
	"subnet-044062461f0fd3b40",
]
chrisbarm_rds_endpoint = "chrisbarm-rds01.c4x68420cyvy.us-east-1.rds.amazonaws.com"
chrisbarm_sns_topic_arn = "arn:aws:sns:us-east-1:198547498722:chrisbarm-db-incidents"
chrisbarm_target_group_arn01 = "arn:aws:elasticloadbalancing:us-east-1:198547498722:targetgroup/chrisbarm-tg01/5e78317173ac277c"
chrisbarm_vpc_id = "vpc-02d1bb2cf2a2dafdf"
db_connection_alarm_name = "lab-db-connection-failure"
db_incidents_topic_arn = "arn:aws:sns:us-east-1:198547498722:lab-db-incidents"
db_incidents_topic_name = "lab-db-incidents"
log_group_name = "/aws/ec2/chrisbarm-rds-app"
```
