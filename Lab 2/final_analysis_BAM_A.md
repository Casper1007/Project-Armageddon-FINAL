PUBLIC FEED (MISS)
HTTP/2 200
cache-control: public, s-maxage=30, max-age=0
x-cache: Miss from cloudfront
age: 0

{"server_time_utc":"2026-02-06T00:00:00Z","message":"message of the minute"}

PUBLIC FEED (HIT)
HTTP/2 200
cache-control: public, s-maxage=30, max-age=0
x-cache: Hit from cloudfront
age: 12

{"server_time_utc":"2026-02-06T00:00:00Z","message":"message of the minute"}

PUBLIC FEED (MISS AFTER TTL)
HTTP/2 200
cache-control: public, s-maxage=30, max-age=0
x-cache: Miss from cloudfront
age: 0

{"server_time_utc":"2026-02-06T00:00:35Z","message":"message of the minute"}

PRIVATE LIST (NO-STORE)
HTTP/2 200
cache-control: private, no-store
x-cache: Miss from cloudfront

{"status":"success","notes":[...]}

PRIVATE LIST (NO-STORE REPEAT)
HTTP/2 200
cache-control: private, no-store
x-cache: Miss from cloudfront

{"status":"success","notes":[...]}

Origin-driven caching is safer for APIs because the origin explicitly defines freshness per endpoint, avoiding accidental caching of user-specific or dynamic data while keeping CDN behavior consistent with app intent. I would still disable caching entirely for endpoints that include authentication, personalization, or rapidly changing state where any stale or shared response could leak data or break correctness.
