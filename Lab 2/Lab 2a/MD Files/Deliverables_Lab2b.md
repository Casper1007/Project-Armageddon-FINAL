## Lab 2B: Expected Deliverables

### Deliverable A — Terraform
You must submit Terraform that creates/updates:
1. Two cache policies
	- static (aggressive caching)
	- api (caching disabled OR origin-driven)
2. Two origin request policies
	- static minimal forwarding
	- api forwards required headers/query/cookies (but doesn’t necessarily include them in cache key)
3. Two cache behaviors
	- path_pattern = "/static/*" → static policies
	- path_pattern = "/api/*" → api policies
4. Be A Man Challenge: Response headers policy for explicit Cache-Control on static responses (or security headers)

### Deliverable B — Correctness Proof (CLI evidence)
You must submit:
A) curl -I outputs for:
	- /static/example.txt (must show cache hit behavior)
	- /api/list (must NOT cache unsafe content)
B) A short written explanation:
	- “What is my cache key for /api/* and why?”
	- “What am I forwarding to origin and why?”

### Deliverable C — Haiku
You must submit:
A) Haiku describing Chewbacca's perfections.  
	漢字で。。。英語なし

### Deliverable D — Technical Verification (CLI) — “Correctness, not vibes”
1. Static caching proof
	- Run twice:
	  curl -I https://<your-domain-or-cloudfront-url>/static/example.txt
	  curl -I https://<your-domain-or-cloudfront-url>/static/example.txt
	- Look for:
	  - Cache-Control: public, max-age=... (from response headers policy)
	  - Age: increases on subsequent requests (cached object indicator)
	- If Age never appears/increases, caching isn’t working (or TTL is 0 / headers prevent caching).
2. API must NOT cache unsafe output
	- Run twice:
	  curl -I https://<your-domain-or-cloudfront-url>/api/list
	  curl -I https://<your-domain-or-cloudfront-url>/api/list
	- Expected for “safe default” API behavior:
	  - Age should be absent or 0
	  - Responses should reflect fresh origin behavior
	  - If you add auth later, you must never allow one user to see another’s response
3. Cache key sanity checks (query strings)
	- Static should ignore query strings by default:
	  curl -I "https://<your-domain-or-cloudfront-url>/static/example.txt?v=1"
	  curl -I "https://<your-domain-or-cloudfront-url>/static/example.txt?v=2"
	- Expected:
	  - both map to the same cached object (hit ratio stays high) because static cache policy ignores query strings (unless students intentionally change it)
4. “Stale read after write” safety test
	- If your API supports writes:
	  - POST a new row
	  - Immediately GET /api/list
	  - Ensure the new row appears
	  - If it doesn’t, they accidentally cached a dynamic response.
