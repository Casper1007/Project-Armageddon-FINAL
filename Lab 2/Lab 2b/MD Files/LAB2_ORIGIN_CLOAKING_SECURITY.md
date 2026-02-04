# Lab 2: Origin Cloaking Security Deep Dive

## 🛡️ What is Origin Cloaking?

**Origin Cloaking** = Making your origin (ALB) invisible and unreachable directly from the internet

Goal: All internet traffic MUST flow through CloudFront. Direct ALB access = **403 Forbidden**

---

## 🔐 Three-Layer Defense

### Layer 1: IP Restriction (AWS Managed Prefix List)

```hcl
data "aws_ec2_managed_prefix_list" "chrisbarm_cf_origin_facing01" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group_rule" "chrisbarm_alb_ingress_cf44301" {
  type              = "ingress"
  security_group_id = aws_security_group.chrisbarm_alb_sg01.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [
    data.aws_ec2_managed_prefix_list.chrisbarm_cf_origin_facing01.id
  ]
}
```

**What It Does**:
- Restricts ALB inbound (443) to **CloudFront IP ranges only**
- AWS maintains this list automatically (updates as CloudFront expands)
- This is the **network-layer firewall rule**

**What It Blocks**:
```
❌ curl https://direct-alb-ip:443
   → TCP connection refused (not in allowed IP ranges)

❌ curl https://alb.region.elb.amazonaws.com:443
   → Connection refused (origin IP not in CloudFront prefix list)

❌ Attacker on office network tries ALB
   → Office IP not in CloudFront prefix list
   → Blocked at security group level
```

**What It Allows**:
```
✅ CloudFront edge in us-west-2 sends request
   → CloudFront IP in prefix list
   → Security group allows it
   → Request proceeds to application layer
```

**Real-World Example**:
```
CloudFront prefix list contains: 52.84.0.0/15, 205.251.200.0/21, etc.
Your ALB security group rule says: "Allow 443 from these IPs only"

Request from 52.84.50.100 (CloudFront edge in Ireland)
  → Security group checks: "52.84.50.100 in 52.84.0.0/15?" → YES
  → Let traffic through

Request from 203.0.113.50 (random attacker)
  → Security group checks: "203.0.113.50 in CloudFront ranges?" → NO
  → Drop connection (don't even respond)
```

---

### Layer 2: Custom Header Validation (Secret Handshake)

```hcl
resource "random_password" "chrisbarm_origin_header_value01" {
  length  = 32
  special = false
}

resource "aws_lb_listener_rule" "chrisbarm_require_origin_header01" {
  listener_arn = aws_lb_listener.chrisbarm_http_listener01.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.chrisbarm_tg01.arn
  }

  condition {
    http_header {
      http_header_name = "X-Chrisbarm-Growl"
      values           = [random_password.chrisbarm_origin_header_value01.result]
    }
  }
}
```

**What It Does**:
- Generates a **random 32-character secret** (stored in Terraform state)
- CloudFront automatically adds this header to all requests to ALB
- ALB only forwards requests that contain this **exact secret**
- This is the **application-layer authentication**

**Why This Layer Exists**:
Layer 1 (IP restriction) alone has a weakness: an attacker could theoretically:
1. Discover CloudFront IP ranges (public knowledge)
2. Spoof traffic from those IPs (harder, but possible with some network access)
3. Still reach your ALB

Layer 2 defends against this: even if IP is spoofed, the attacker won't have the secret header.

**Example Attack Scenario**:

```
Attacker discovers ALB DNS: alb-123.us-east-1.elb.amazonaws.com

Attack 1: Direct access
  curl https://alb-123.us-east-1.elb.amazonaws.com
  ├─ Security group allows? NO (attacker IP not in CloudFront range)
  └─ Result: Connection refused

Attack 2: Spoof CloudFront IP (more sophisticated)
  curl -H "X-Forwarded-For: 52.84.50.100" \
       https://alb-123.us-east-1.elb.amazonaws.com
  ├─ Security group allows? YES (IP appears to be CloudFront)
  ├─ Header validation: "X-Chrisbarm-Growl: ???"
  ├─ Attacker doesn't have secret (stored in Terraform state, not public)
  └─ Result: ALB returns 403 Forbidden

Attack 3: Brute-force secret (infeasible)
  for i in {1..1000000}; do
    curl -H "X-Chrisbarm-Growl: secret$i" https://alb-dns
  done
  ├─ Secret is 32 random characters (32! = 263,130,836,933,693,900,000,000,000,000,000 combinations)
  ├─ Even at 1M requests/second: takes 8 * 10^24 seconds
  └─ Result: Infeasible (brute force impossible)
```

---

### Layer 3: Catch-All 403 Block (Default Deny)

```hcl
resource "aws_lb_listener_rule" "chrisbarm_default_block01" {
  listener_arn = aws_lb_listener.chrisbarm_http_listener01.arn
  priority     = 100  # ← LOWER precedence than priority 10

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  condition {
    path_pattern { values = ["*"] }
  }
}
```

**What It Does**:
- If request reaches ALB but doesn't have the secret header → 403 Forbidden
- Applies to **all paths** (catch-all: `*`)
- Has **lower priority (100)** than the forward rule (10), so it's evaluated second

**Priority Explanation**:
```
In ALB listener rules:
  Lower priority number = Higher precedence (evaluated first)
  Higher priority number = Lower precedence (evaluated later)

Priority 10: "If header matches, forward to target group"
Priority 100: "Otherwise, return 403"

Request flow:
  1. Evaluate priority 10: Does request have secret header? 
     → YES: Forward to target group (rule matches, stop here)
     → NO: Continue to next rule
  2. Evaluate priority 100: Match everything else
     → Return 403 Forbidden
```

**Why This Is Important**:
- Ensures **no request slips through** without validation
- If someone bypasses layer 1 (IP check) AND layer 2 (header check), layer 3 catches it
- Default-deny principle: "Block everything except what we explicitly allow"

---

## 🎯 Attack Scenarios & Defenses

### Scenario 1: Random Internet Scanner

**Attack**:
```bash
# Attacker's reconnaissance script
for i in {1..1000}; do
  nmap -p 443 10.0.0.0/8
done
```

**What Happens**:
```
Scanner discovers: 10.0.2.100:443 is open (ALB)
Scanner tries to connect: curl https://10.0.2.100:443

Layer 1 Defense (IP Restriction):
  ├─ Scanner IP: 203.0.113.50
  ├─ Security group check: "203.0.113.50 in CloudFront prefix list?"
  ├─ Result: NO
  └─ Action: Drop connection (don't respond, no 403 sent)

Result: Attack blocked at network level ✅
Cost: 0ms (connection refused before reaching application)
```

---

### Scenario 2: Someone Knows ALB DNS

**Attack**:
```bash
# Attacker obtained ALB DNS from DNS logs, Git history, or other source
curl https://alb-internal-123.us-east-1.elb.amazonaws.com
```

**What Happens**:
```
Attacker's laptop (203.0.113.50) tries to reach ALB

Layer 1 Defense (IP Restriction):
  ├─ Attacker IP: 203.0.113.50
  ├─ Check: In CloudFront ranges? NO
  └─ Result: Connection refused ✅

Result: Attack blocked at network layer ✅
```

---

### Scenario 3: AWS Insider (Has Network Access)

**Attack** (more sophisticated):
```bash
# Insider on office VPN (IP in allowed ranges) tries to reach ALB
# Or uses EC2 instance in same VPC to bypass network restrictions

curl -v https://alb-internal-123.us-east-1.elb.amazonaws.com
```

**What Happens**:
```
Request reaches ALB (either same VPC or via compromise)

Layer 1 Defense (IP Restriction):
  ├─ If from VPC: Security group allows VPC CIDR (10.0.0.0/16)? 
  │  Possibly (depends on SG rules)
  └─ If from office: IP blocked (not CloudFront range)

But Layer 2 Defense activates (Header Validation):
  ├─ Request arrives at ALB listener
  ├─ ALB checks priority 10 rule: "Does it have X-Chrisbarm-Growl header?"
  ├─ Request has: Host, User-Agent, etc. (from curl)
  ├─ Request does NOT have: X-Chrisbarm-Growl: <32-char-secret>
  ├─ Priority 10 rule doesn't match
  ├─ Check priority 100 rule: Match everything else? YES
  └─ Return 403 Forbidden ✅

Result: Attack blocked at application layer ✅
Attacker sees: HTTP 403 Forbidden (knows ALB exists but can't access it)
```

---

### Scenario 4: Sophisticated Attacker (Spoofs CloudFront IP)

**Attack**:
```bash
# Advanced: Attacker has network access (BGP hijack, compromised ISP, etc.)
# Sends packet with CloudFront IP as source

curl -H "X-Forwarded-For: 52.84.50.100" \
     https://alb-dns
```

**What Happens**:
```
Request arrives with source IP = 52.84.50.100 (CloudFront IP)

Layer 1 Defense (IP Restriction):
  ├─ Source IP: 52.84.50.100
  ├─ Check: In CloudFront prefix list? YES
  ├─ Result: Security group allows ✅
  └─ Continue to application layer

Layer 2 Defense (Header Validation):
  ├─ ALB checks: "Does request have X-Chrisbarm-Growl header?"
  ├─ Attacker added: X-Forwarded-For: 52.84.50.100
  ├─ But did NOT add: X-Chrisbarm-Growl: <32-char-secret>
  ├─ Priority 10 rule doesn't match
  ├─ Priority 100 rule matches: Return 403 ✅

Result: Attack blocked ✅
Why: Attacker doesn't have the secret (it's in Terraform state, not public)
```

---

### Scenario 5: Compromised Attacker (Has Terraform State)

**Attack** (worst case):
```bash
# Attacker has access to Terraform state (via Git commit, S3 exposure, etc.)
# Extracts the secret: 8f2a9b3c1d4e7f9a2b5c8d1e4f7a9b3c

HEADER_VALUE="8f2a9b3c1d4e7f9a2b5c8d1e4f7a9b3c"
curl -H "X-Chrisbarm-Growl: $HEADER_VALUE" \
     https://alb-dns
```

**What Happens**:
```
Request arrives with correct header

Layer 1 Defense (IP Restriction):
  ├─ Attacker IP: 203.0.113.50
  ├─ Check: In CloudFront range? NO
  └─ Result: Connection refused ✅

Result: STILL BLOCKED ✅
Why: Even with correct header, attacker IP fails Layer 1
```

**If attacker also spoof's IP**:
```
Request arrives with CloudFront IP AND correct header

Layer 1 Defense (IP Restriction):
  ├─ Source IP: 52.84.50.100 (spoofed CloudFront)
  ├─ Check: In CloudFront range? YES ✅

Layer 2 Defense (Header Validation):
  ├─ Header: X-Chrisbarm-Growl: 8f2a9b3c... (correct)
  ├─ Match? YES ✅
  └─ Forward to target group

Result: ATTACK SUCCEEDS ❌
Why: All layers passed
Mitigation: Rotate secret regularly (in Terraform)
```

---

## 📋 ALB Listener Rule Priority Reference

```
Request arrives at ALB listener on port 443

┌─────────────────────────────────────────┐
│ Check ALL listener rules in order       │
│ (lowest priority number first)          │
└─────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────┐
│ Priority 10:                            │
│ IF header matches X-Chrisbarm-Growl    │
│ THEN forward to target group            │
│ ELSE continue to next rule              │
└─────────────────────────────────────────┘
        ↓ (if no match)
┌─────────────────────────────────────────┐
│ Priority 100:                           │
│ IF path matches * (everything)          │
│ THEN return 403 Forbidden               │
│ (catches all remaining requests)        │
└─────────────────────────────────────────┘
```

**Critical Point**: Priority 100 is a **fallback catch-all**. If request reaches ALB without matching Priority 10, it gets 403.

---

## ✅ Verification Tests

### Test 1: Verify Layer 1 (IP Restriction)

```bash
# Get ALB security group
ALB_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=chrisbarm-alb-sg01" \
  --query 'SecurityGroups[0].GroupId' --output text)

# Check if CloudFront prefix list is in inbound rules
aws ec2 describe-security-groups \
  --group-ids $ALB_SG \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`443`]'

# Expected output should show:
# "PrefixListIds": [ { "PrefixListId": "pl-xxxxxxxx" } ]
```

### Test 2: Verify Layer 2 (Header Validation)

```bash
# Get ALB listener rules
LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn $(aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[?LoadBalancerName==`chrisbarm-alb01`].LoadBalancerArn' --output text) \
  --query 'Listeners[?Port==`443`].ListenerArn' --output text)

# Check listener rules
aws elbv2 describe-listener-rules \
  --listener-arn $LISTENER_ARN \
  --query 'Rules[*].[Priority,Conditions[0].HttpHeaderConfig.HttpHeaderName,Actions[0].Type]'

# Expected output:
# [ "10", "X-Chrisbarm-Growl", "forward" ]
# [ "100", null, "fixed-response" ]
```

### Test 3: Direct ALB Access Should Fail

```bash
# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?LoadBalancerName==`chrisbarm-alb01`].DNSName' \
  --output text)

# Try direct access
curl -I https://$ALB_DNS

# Expected output:
# HTTP/1.1 403 Forbidden
# (or connection refused if attacker IP blocked at SG level)
```

### Test 4: CloudFront Access Should Work

```bash
# Get domain name
DOMAIN=$(aws ssm get-parameter \
  --name /chrisbarm/domain_name \
  --query 'Parameter.Value' --output text)

# Try via CloudFront
curl -I https://$DOMAIN

# Expected output:
# HTTP/1.1 200 OK
# (or 301 if app redirects)
```

### Test 5: Verify Prefix List

```bash
# Get CloudFront prefix list ID
PL_ID=$(aws ec2 describe-managed-prefix-lists \
  --filters "Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing" \
  --query 'PrefixLists[0].PrefixListId' --output text)

# View IP ranges in prefix list (sample, not all)
aws ec2 get-managed-prefix-list-entries \
  --prefix-list-id $PL_ID \
  --query 'Entries[0:5].[Cidr,Description]'

# Sample output:
# [ "52.84.0.0/15", "CloudFront Edge" ]
# [ "205.251.200.0/21", "CloudFront Edge" ]
# ... (many more ranges)
```

---

## 🔄 Secret Rotation

Since the secret is stored in Terraform state (not in code), rotate it periodically:

```bash
# 1. Remove old secret from state
terraform state rm aws_random_password.chrisbarm_origin_header_value01

# 2. Generate new secret
terraform apply

# 3. Update ALB listener rule (happens automatically)

# 4. CloudFront automatically includes new header (no change needed)

# 5. Test access
curl -I https://chrisbdevsecops.com
# Should work immediately (CloudFront has new header)
```

---

## 📊 Security Comparison

| Defense Layer | Attack Vector | Protection Type | Strength |
|---|---|---|---|
| **Layer 1: IP Restriction** | Direct ALB from internet | Network (firewall) | Very strong (AWS maintained) |
| **Layer 2: Header Validation** | Spoof CloudFront IP | Application (header check) | Very strong (32 char secret, 10^48 combinations) |
| **Layer 3: Catch-All 403** | Bypass both layers | Fallback (deny-all) | Absolute (no requests slip through) |

---

## 🎯 Interview Talking Points

**Q: "Why do you need Layer 2 (header) if you already have Layer 1 (IP)?"**

A: "Layer 1 alone assumes that IP ranges can't be spoofed, which isn't always true in advanced attacks (BGP hijacking, compromised ISP). Layer 2 adds application-level authentication independent of IP, so even if an attacker spoofs a CloudFront IP, they won't have the secret header. It's defense-in-depth—two separate validation mechanisms."

**Q: "What happens if the secret is compromised?"**

A: "First, Layer 1 still protects us—even with the correct header, the attacker's IP needs to be in the CloudFront range, which is hard to spoof without serious network access. Second, we can rotate the secret by removing and re-generating the Terraform resource. CloudFront automatically gets the new header with the next deploy, and old header becomes invalid."

**Q: "Why not just use public CloudFront without origin cloaking?"**

A: "Public CloudFront means anyone can hit the ALB if they know the DNS or IP. We'd need to put WAF on the ALB too (not just CloudFront), which is expensive. Origin cloaking forces all traffic through CloudFront, so we only need one WAF (at CloudFront edge), saving cost and simplifying architecture."

**Q: "Isn't this overkill for a lab?"**

A: "This is actually standard practice for high-security environments (finance, healthcare, government). We're learning the industry pattern early. Most companies with serious infrastructure use origin cloaking to prevent accidental direct access and to ensure all traffic gets filtered through centralized WAF/logging."

---

## ⚠️ Common Mistakes

### Mistake 1: Wrong Listener Rule Priority

```hcl
# ❌ WRONG: Default block rule has LOWER priority number
resource "aws_lb_listener_rule" "default_block" {
  priority = 10  # ← Evaluated FIRST
  action { fixed_response { status_code = "403" } }
}

resource "aws_lb_listener_rule" "forward" {
  priority = 100  # ← Evaluated SECOND (never reached)
  action { forward { target_group_arn = ... } }
}
# Result: Everything returns 403, nothing reaches app ❌

# ✅ CORRECT: Forward rule has LOWER priority (evaluated first)
resource "aws_lb_listener_rule" "forward" {
  priority = 10   # ← Evaluated FIRST
  condition { http_header { ... } }
  action { forward { target_group_arn = ... } }
}

resource "aws_lb_listener_rule" "default_block" {
  priority = 100  # ← Evaluated SECOND (catchall)
  action { fixed_response { status_code = "403" } }
}
# Result: Valid requests forwarded, invalid requests get 403 ✅
```

### Mistake 2: Forgetting Security Group Rule

```hcl
# ❌ If you forget to add prefix list rule:
# ALB security group still has: Inbound 0.0.0.0/0:443 (allow all)
# Result: Anyone can access ALB directly, origin cloaking fails ❌

# ✅ Correct: Replace ALB inbound rule
resource "aws_security_group_rule" "alb_ingress_cf" {
  type              = "ingress"
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_ec2_managed_prefix_list.cf.id]
}

# Now ALB only accepts 443 from CloudFront IPs ✅
```

### Mistake 3: Hardcoding Secret

```hcl
# ❌ WRONG: Secret in code (visible in Git history)
resource "aws_lb_listener_rule" "forward" {
  condition {
    http_header {
      http_header_name = "X-Chrisbarm-Growl"
      values           = ["mySecretValue123"]  # ← In code!
    }
  }
}
# Result: Anyone with Git access sees the secret ❌

# ✅ CORRECT: Generate random secret
resource "random_password" "secret" {
  length  = 32
  special = false
}

resource "aws_lb_listener_rule" "forward" {
  condition {
    http_header {
      http_header_name = "X-Chrisbarm-Growl"
      values           = [random_password.secret.result]  # ← Generated
    }
  }
}
# Result: Secret never in code, stored only in state ✅
```

---

## 📚 Real-World Scenarios

### E-Commerce (PCI-DSS Compliance)

```
Internet → CloudFront (WAF blocks attacks) 
         → ALB (origin cloaking, header validation)
         → Private EC2 (payment processing)
         → RDS (encrypted credit card data)

Requirement: "Only approved devices can reach payment systems"
Solution: Origin cloaking + CloudFront origin header
Result: ✅ Meets PCI requirement 6.6 (firewall between internet and payment system)
```

### Healthcare (HIPAA Compliance)

```
Internet → CloudFront (audit logging)
         → ALB (origin cloaking)
         → Private EC2 (patient data)
         → RDS (encrypted PHI)

Requirement: "All traffic to PHI systems must be monitored"
Solution: All traffic goes through CloudFront (audit trails), ALB locked down
Result: ✅ Meets HIPAA requirement (audit logging of all access)
```

### Government (FedRAMP)

```
Internet → CloudFront + WAF (government-approved rules)
         → ALB (origin cloaking)
         → Private EC2 (government data)
         → RDS (encrypted secrets)

Requirement: "Publicly visible services must be protected by WAF"
Solution: CloudFront WAF + origin cloaking (two layers)
Result: ✅ Meets FedRAMP requirement (web application firewall in place)
```

---

**Document Version**: 1.0  
**Lab 2 Component**: Origin Cloaking Security  
**Last Updated**: January 21, 2026
