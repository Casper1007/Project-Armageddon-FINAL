Beron Da Saluki criteria

Implements safe caching for a public GET endpoint using Cache-Control from origin
- Implemented a public GET endpoint that returns Cache-Control from the origin: public, max-age=30.
- This uses origin headers to control caching rather than hardcoding TTLs at the CDN.

Demonstrates correct behavior using headers and evidence
- Request 1 (cold): curl -I https://<cloudfront-domain>/health
	- Cache-Control: public, max-age=30
	- X-Cache: Miss from cloudfront
- Request 2 (within 30s): curl -I https://<cloudfront-domain>/health
	- Cache-Control: public, max-age=30
	- X-Cache: Hit from cloudfront
	- Age: <seconds>

Shows understanding of why Cache-Control is preferred
- Cache-Control is origin-authored and standards-based, allowing the app to set freshness per endpoint.
- It prevents over-caching of user-specific or dynamic data by making caching explicit where safe.
- It aligns browser and CDN behavior and avoids brittle, hardcoded CDN TTLs.
