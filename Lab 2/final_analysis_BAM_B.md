BREAK GLASS INVALIDATION (CLI)
aws cloudfront create-invalidation \
	--distribution-id <DISTRIBUTION_ID> \
	--paths "/static/index.html"
InvalidationId: <INVALIDATION_ID>

aws cloudfront create-invalidation \
	--distribution-id <DISTRIBUTION_ID> \
	--paths "/static/*"
InvalidationId: <INVALIDATION_ID>

aws cloudfront get-invalidation \
	--distribution-id <DISTRIBUTION_ID> \
	--id <INVALIDATION_ID>
Status: Completed

BEFORE INVALIDATION (CACHED)
curl -i https://chrisbdevsecops.com/static/index.html | sed -n '1,30p'
HTTP/2 200
x-cache: Miss from cloudfront
age: 0

curl -i https://chrisbdevsecops.com/static/index.html | sed -n '1,30p'
HTTP/2 200
x-cache: Hit from cloudfront
age: <increased>

AFTER INVALIDATION (REFRESH)
curl -i https://chrisbdevsecops.com/static/index.html | sed -n '1,30p'
HTTP/2 200
x-cache: Miss from cloudfront (or RefreshHit)
age: 0

POLICY PARAGRAPH
We invalidate only for break-glass events like security incidents, corrupted content, or legal takedowns, and we target the smallest path possible (for example, /static/index.html). For normal deployments we use versioned assets like /static/app.<hash>.js, which avoids invalidations entirely. We restrict /* because it blasts the entire cache, increases origin load, and burns the invalidation budget; wildcard invalidations require explicit approval and documented justification.
