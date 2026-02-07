REFRESHHIT OBSERVATION (TTL EXPIRED, VALIDATORS PRESENT)
curl -i https://chrisbdevsecops.com/static/index.html | sed -n '1,25p'
HTTP/2 200
cache-control: public, max-age=5
etag: "chewie-v1"
x-cache: Miss from cloudfront
age: 0

curl -i https://chrisbdevsecops.com/static/index.html | sed -n '1,25p'
HTTP/2 200
cache-control: public, max-age=5
etag: "chewie-v1"
x-cache: Hit from cloudfront
age: 3

sleep 6
curl -i https://chrisbdevsecops.com/static/index.html | sed -n '1,25p'
HTTP/2 200
cache-control: public, max-age=5
etag: "chewie-v1"
x-cache: RefreshHit from cloudfront
age: 0

VALIDATORS EVIDENCE
etag: "chewie-v1"
last-modified: <timestamp>

INJECTION B (STALE CONTENT DUE TO UNCHANGED VALIDATOR)
curl -i https://chrisbdevsecops.com/static/index.html | sed -n '1,25p'
HTTP/2 200
cache-control: public, max-age=5
etag: "chewie-v1"  # unchanged
x-cache: RefreshHit from cloudfront
age: 0
body: <stale>

FIX APPLIED
etag: "chewie-v2"  # updated
x-cache: Miss from cloudfront
body: <updated>

ONE-PARAGRAPH TAKEAWAY
RefreshHit means CloudFront had a cached object whose TTL expired, so it revalidated it with the origin using validators like ETag or Last-Modified; the origin returned 304 Not Modified and CloudFront reused the cached body. This is often better than a full Miss because it preserves correctness while saving bandwidth and reducing origin load, even though latency is slightly higher than a pure Hit.
