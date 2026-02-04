# Defending Armageddon Part 2: What, How, Why Evaluation

**Date:** January 22, 2026  
**Project Type:** Multi-tier AWS Infrastructure with Production Security Patterns  
**Technology Stack:** Terraform, AWS (EC2, RDS, CloudFront, WAF, VPC Endpoints, IAM), Python, Bash  

---

## Project Overview: The Big Picture

This project demonstrates a **progressive security hardening journey** from basic cloud architecture to enterprise-grade infrastructure. It's structured as 4 interconnected labs where each builds on previous layers:

```
Lab 1a: Foundation (EC2 ↔ RDS)
    ↓ (What happens when things break?)
Lab 1b: Resilience (Observability + Incident Response)
    ↓ (How do we protect from external attacks?)
Lab 2: Edge Security (CloudFront + WAF + Origin Cloaking)
    ↓ (How do we achieve maximum security?)
Bonus-A: Hardening (Zero Internet Exposure + VPC Endpoints)
```

---

# PART 1: LAB 1A — EC2-to-RDS Integration (Foundation)

## WHAT Was Built

A **secure, production-ready database integration** between an application server and managed database using AWS native security services.

**Infrastructure Components:**
- VPC with public/private subnets across 2 availability zones
- EC2 instance running Flask application (in public subnet)
- RDS MySQL database (in private subnets, isolated)
- Security groups enforcing least-privilege network access
- IAM role attached to EC2 (enables credential-free access)
- AWS Secrets Manager storing database credentials
- NAT Gateway and Internet Gateway for routing
- CloudWatch monitoring for logs and metrics

**Application Layer:**
- Python Flask web server with REST endpoints
- MySQL connector for database communication
- Dynamic credential retrieval from Secrets Manager
- Error handling, logging, and retry logic

**Resource Counts:**
- 1 VPC, 4 subnets, 2 availability zones
- 1 EC2 instance, 1 RDS instance
- 3 security groups (public, private, database)
- 1 IAM role with 3 policies attached
- 1 Secrets Manager secret storing 5 credential fields

---

## HOW It Was Implemented

### Infrastructure as Code (Terraform)

**Files:**
- `main.tf` (570 lines) - VPC, subnets, security groups, EC2, RDS
- `variables.tf` - Parameterized inputs (region, CIDR blocks, instance types)
- `outputs.tf` - Exports resource IDs for downstream integration
- `providers.tf` - AWS provider configuration

**Key Terraform Patterns:**

```terraform
# 1. Locals for consistent naming
locals {
  name_prefix = var.project_name
  db_port     = 3306
}

# 2. VPC with DNS enabled
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# 3. Public subnets (internet-accessible)
resource "aws_subnet" "public" {
  count             = 2
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  map_public_ip_on_launch = true
}

# 4. Private subnets (database layer)
resource "aws_subnet" "private" {
  count             = 2
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
}

# 5. Security group with least-privilege rule
resource "aws_security_group_rule" "rds_from_ec2_only" {
  # RDS accepts MySQL ONLY from EC2's security group
  # Not from 0.0.0.0/0 (the entire internet)
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  source_security_group_id = aws_security_group.ec2.id
}

# 6. IAM role for EC2 (no hardcoded credentials)
resource "aws_iam_role" "ec2_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

# 7. IAM policy scoped to specific secret
resource "aws_iam_role_policy" "secrets_access" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "secretsmanager:GetSecretValue"
      Resource = "arn:aws:secretsmanager:us-east-1:*:secret:lab1a/rds/mysql*"
    }]
  })
}

# 8. Secrets Manager storing credentials
resource "aws_secretsmanager_secret" "db_creds" {
  name = "lab1a/rds/mysql"
  
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.rds.endpoint
    port     = 3306
    dbname   = var.db_name
  })
}

# 9. RDS in private subnet
resource "aws_db_instance" "rds" {
  db_subnet_group_name   = aws_db_subnet_group.private.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false  # CRITICAL: not exposed to internet
  skip_final_snapshot    = false  # Enable backups
}
```

### Application Code (Python + Flask)

**File:** `app.py` (274 lines)

**Pattern 1: Credential-Free Access**
```python
def get_db_credentials():
    """
    Retrieve credentials from Secrets Manager using IAM role.
    Credentials never hardcoded or in environment variables.
    """
    secrets_client = boto3.client('secretsmanager', region_name='us-east-1')
    response = secrets_client.get_secret_value(SecretId='lab1a/rds/mysql')
    
    if 'SecretString' in response:
        return json.loads(response['SecretString'])
    else:
        raise Exception("Invalid secret format")
```

**Pattern 2: Dynamic Database Connection**
```python
def get_db_connection():
    """Connect to RDS using dynamically retrieved credentials."""
    creds = get_db_credentials()
    connection = mysql.connector.connect(
        host=creds['host'],
        user=creds['username'],
        password=creds['password'],
        database=creds['dbname'],
        port=creds['port'],
        autocommit=True
    )
    return connection
```

**Pattern 3: Error Handling**
```python
@app.route('/init', methods=['POST'])
def init_database():
    try:
        connection = get_db_connection()
        cursor = connection.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS notes (
                id INT AUTO_INCREMENT PRIMARY KEY,
                note TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """)
        connection.close()
        return jsonify({"status": "success", "message": "Database initialized"})
    except Exception as e:
        logger.error(f"Database initialization failed: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500
```

**Endpoints Provided:**
- `GET /health` - Application health check
- `POST /init` - Initialize database schema
- `POST /add?note=<text>` - Insert note into database
- `GET /list` - Retrieve all notes

### Automation (User Data & EC2 Initialization)

**File:** `1a_user_data.sh`

```bash
#!/bin/bash
# 1. Update system packages
apt-get update && apt-get install -y python3-pip git mysql-client

# 2. Install Python dependencies
pip install flask mysql-connector-python boto3

# 3. Download and deploy application
git clone https://...code-repo.../app.git /opt/rds-app
cd /opt/rds-app

# 4. Create systemd service for automatic startup
cat > /etc/systemd/system/rds-app.service <<EOF
[Unit]
Description=RDS Database App
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/rds-app
ExecStart=/usr/bin/python3 app.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 5. Enable and start service
systemctl daemon-reload
systemctl enable rds-app
systemctl start rds-app
```

---

## WHY These Decisions

### Why IAM Roles Instead of Hardcoded Credentials?

**Problem:** If credentials are in code/environment variables:
- They appear in `aws ec2 describe-instances` output (visible to anyone with EC2:Describe permission)
- They show up in application logs if errors occur
- They appear in version control history (nearly impossible to fully remove)
- Rotation requires redeploying application

**Solution - IAM Role:**
- ✅ Credentials never stored on EC2; AWS manages temporary credentials
- ✅ Automatic credential rotation (refreshed every 6 hours by default)
- ✅ Audit trail via CloudTrail (exactly who accessed what)
- ✅ Time-limited credentials (session tokens with expiration)

**Real-world impact:** Netflix, Stripe, AWS itself all use IAM roles—this is THE pattern for production.

### Why Secrets Manager Instead of Environment Variables?

**Problem:** Environment variables appear in multiple places:
- `aws ssm describe-instances` API calls
- Application startup logs
- Container definitions (if using ECS)
- SSH session environment dumps

**Solution - Secrets Manager:**
- ✅ Separate service; not stored on instance
- ✅ Encrypted at rest (KMS)
- ✅ Access logged to CloudTrail
- ✅ Supports automatic rotation
- ✅ Credentials retrieved at runtime (not build time)

**Real-world impact:** Compliance standards (PCI-DSS, HIPAA, SOC2) often require this pattern.

### Why RDS in Private Subnet?

**Problem:** If RDS had public IP or was internet-routable:
- Attackers could scan for MySQL ports
- DDoS attacks directly hit database
- Brute-force attacks on database password
- One vulnerability = complete database compromise

**Solution - Private Subnet:**
- ✅ RDS has no internet route; only accessible from VPC
- ✅ Security group restricts to EC2 SG (not any IP)
- ✅ NAT Gateway handles outbound traffic (patches, backups)
- ✅ Multi-AZ means automatic failover to another AZ

**Real-world impact:** "Defense in depth"—even if EC2 is compromised, attacker needs to bypass security group rule.

### Why Security Group Rule Sources Other by SG ID (Not CIDR)?

**Problem:** If rule uses CIDR (e.g., `10.0.1.0/24`):
- If EC2 is terminated and replaced with different IP, rule breaks
- If EC2 IP changes, rule breaks
- Manual rule updates needed

**Solution - Source by Security Group ID:**
- ✅ Rule works regardless of EC2 IP changes
- ✅ AWS automatically resolves SG ID to current IPs
- ✅ Cleaner infrastructure (rule says "allow from EC2 SG", not "allow from 10.0.1.37")
- ✅ Portable across AZs and regions

**Real-world impact:** When you need to scale (auto-scaling groups), SG-based rules are mandatory.

### Why Multi-AZ Architecture?

**Problem:** Single AZ means:
- Database down = application down
- If AWS AZ-a fails (power outage, hardware failure), everything stops
- No automatic failover

**Solution - Multi-AZ RDS:**
- ✅ Primary RDS in AZ-a, standby in AZ-b (synchronously replicated)
- ✅ If AZ-a fails, automatic failover to AZ-b (usually <2 min)
- ✅ EC2 also placed to span AZs (future: auto-scaling group would have instances in both)
- ✅ Meets most SLA requirements (99.95% uptime)

**Real-world impact:** Enterprise SLAs typically require multi-AZ; this demonstrates awareness.

### Why Least-Privilege IAM?

**Problem:** If IAM role has broad permissions:
- If EC2 is compromised, attacker can access everything in AWS account
- Example: role with `"Action": "iam:*"` means attacker can create new admins
- Blast radius unbounded

**Solution - Scoped Permissions:**
```json
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": "arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:lab1a/rds/mysql*"
}
```
- ✅ EC2 can ONLY read ONE secret (not all secrets)
- ✅ EC2 can only call GetSecretValue (not delete, create, etc.)
- ✅ Blast radius limited: even if compromised, attacker confined

**Real-world impact:** AWS Well-Architected Framework pillar #1 is "least privilege".

---

# PART 2: LAB 1B — Incident Response & Observability (Resilience)

## WHAT Was Built

An **observability and incident response system** that detects failures automatically, classifies them, and executes recovery scripts without redeployment.

**Observability Components:**
- CloudWatch Logs collecting application output
- CloudWatch Metrics capturing errors from log patterns
- CloudWatch Alarms triggering when thresholds exceeded
- SNS Topics notifying on-call team
- Log Metric Filters parsing errors from application logs

**Incident Response Components:**
- 3 failure scenario simulations (credential drift, network isolation, DB unavailable)
- 3 recovery scripts (one per scenario)
- Runbook documenting investigation steps
- Incident report generation tool

**Key Metrics:**
- `DBConnectionErrors` - Count of database connection failures
- Alert threshold: 3+ errors in 5-minute window
- Action: SNS notification to on-call team

---

## HOW It Was Implemented

### Observability Infrastructure (Terraform)

**File:** `incident_response.tf` (169 lines)

**Pattern 1: CloudWatch Log Group**
```terraform
data "aws_cloudwatch_log_group" "app_logs" {
  name = "/aws/ec2/chrisbarm-rds-app"
}
```

**Pattern 2: Log Metric Filter (Parse Logs)**
```terraform
resource "aws_cloudwatch_log_metric_filter" "db_error_filter" {
  log_group_name = data.aws_cloudwatch_log_group.app_logs.name
  pattern        = "[ERROR]"  # Matches any line with ERROR
  
  metric_transformation {
    name      = "DBConnectionErrors"
    namespace = "Lab/RDSApp"
    value     = "1"  # Each matching line = +1 to metric
  }
}
```

**Pattern 3: CloudWatch Alarm**
```terraform
resource "aws_cloudwatch_metric_alarm" "db_connection_failure" {
  alarm_name          = "lab-db-connection-failure"
  metric_name         = "DBConnectionErrors"
  threshold           = 3  # Trigger if 3+ errors detected
  evaluation_periods  = 1
  period              = 300  # In 5-minute window
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = [aws_sns_topic.db_incidents.arn]  # Send SNS notification
}
```

**Pattern 4: SNS for Notifications**
```terraform
resource "aws_sns_topic" "db_incidents" {
  name = "lab-db-incidents"
}

resource "aws_sns_topic_policy" "allow_cloudwatch" {
  arn = aws_sns_topic.db_incidents.arn
  
  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action = "SNS:Publish"
      Resource = aws_sns_topic.db_incidents.arn
    }]
  })
}
```

### Incident Injection & Recovery Scripts

**File:** `incident_inject_option_a.sh` - Simulate Credential Drift

```bash
#!/bin/bash
# Scenario: Secret password changed, RDS password not updated
# Result: Application cannot authenticate to database

# Change password in Secrets Manager
aws secretsmanager update-secret \
  --secret-id lab1a/rds/mysql \
  --secret-string '{"username":"admin","password":"WRONG_PASSWORD",...}'

# RDS still has old password → connection fails
# Application logs: "Access denied for user 'admin'"
# Metric filter detects ERROR pattern → alarm triggers → SNS notification
```

**File:** `incident_inject_option_b.sh` - Simulate Network Isolation

```bash
#!/bin/bash
# Scenario: EC2→RDS security group rule deleted
# Result: Network packets from EC2 rejected by RDS SG

# Delete the ingress rule
aws ec2 revoke-security-group-ingress \
  --group-id sg-XXXX \
  --source-security-group-id sg-YYYY \
  --protocol tcp \
  --port 3306

# Application logs: "Connection timeout" or "Connection refused"
# Metric filter detects ERROR pattern → alarm triggers
```

**File:** `incident_inject_option_c.sh` - Simulate DB Unavailable

```bash
#!/bin/bash
# Scenario: RDS instance stopped or crashed
# Result: All connection attempts fail

# Stop the RDS instance
aws rds stop-db-instance --db-instance-identifier chrisbarm-rds01

# Application cannot connect → errors logged → alarm triggers
```

**File:** `recover_option_a.sh` - Fix Credential Drift

```bash
#!/bin/bash
# 1. Check current secret
CURRENT=$(aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql | jq .SecretString)

# 2. Compare with RDS password
# 3. If mismatch, update RDS password to match secret
aws rds modify-db-instance \
  --db-instance-identifier chrisbarm-rds01 \
  --master-user-password $(echo $CURRENT | jq -r .password) \
  --apply-immediately

# 4. Application automatically retrieves new creds on next request
# 5. Metric alarm clears when error rate drops below threshold
```

**Similar for:** `recover_option_b.sh` (re-add SG rule) and `recover_option_c.sh` (restart RDS)

### Incident Runbook & Reporting

**File:** `incident_runbook.sh` - Mandatory Response Steps

```bash
#!/bin/bash
# Incident Response Workflow

# Step 1: Get alarm details
aws cloudwatch describe-alarms --alarm-names lab-db-connection-failure

# Step 2: Check application logs
aws logs tail /aws/ec2/chrisbarm-rds-app --follow

# Step 3: Classify failure type (A, B, or C based on error message)

# Step 4: Run appropriate recovery script
case $FAILURE_TYPE in
  "Access denied")     bash recover_option_a.sh ;;
  "Connection timeout") bash recover_option_b.sh ;;
  "Not available")     bash recover_option_c.sh ;;
esac

# Step 5: Verify resolution
bash verify_lab.sh

# Step 6: Generate incident report
bash generate_incident_report.sh
```

---

## WHY This Approach

### Why CloudWatch Logs Over SSH?

**Problem:** Manual SSH inspection requires:
- Human to SSH into EC2
- Manually grep logs
- Slow detection (humans don't watch logs 24/7)
- No audit trail of who viewed what

**Solution - CloudWatch Logs:**
- ✅ Automatic collection (sent by application)
- ✅ Searchable/queryable via AWS console
- ✅ Metric filters parse automatically
- ✅ Central visibility (not scattered across instances)
- ✅ Retention policies (old logs auto-deleted)
- ✅ Audit trail (CloudTrail logs who queried logs)

**Real-world impact:** CloudWatch is AWS native; compatible with all AWS services. Can set up alerts without human intervention.

### Why Metric Filters Over Manual Monitoring?

**Problem:** Manual monitoring requires:
- Someone watching dashboard 24/7
- Alerting is human-dependent
- Delayed response (lag between error and human noticing)

**Solution - Metric Filters:**
- ✅ Automatic pattern matching (runs instantly on log ingestion)
- ✅ Metrics aggregated (can sum, average, max)
- ✅ Alarms triggered at scale (if 10 instances all start erroring, single alarm)
- ✅ No human intervention needed

**Real-world impact:** Netflix processes millions of logs/day; impossible without automation.

### Why Alarms Instead of Manual Response?

**Problem:** Manual response means:
- Team gets paged
- Someone SSHes into instance
- Manually runs recovery commands
- MTTR (mean time to recovery) = 5-30 minutes

**Solution - Automated Recovery Scripts:**
- ✅ Recovery executes in seconds (not minutes)
- ✅ Consistent (same steps every time; no "I forgot this step")
- ✅ Auditable (script logs what it did)
- ✅ Can be triggered by alarm automatically (via SNS → Lambda)

**Real-world impact:** Industry standard for incident response; reduces downtime significantly.

### Why Three Separate Scenarios?

**Problem:** Real incidents are diverse:
- Sometimes it's auth failures (credentials)
- Sometimes it's network issues (connectivity)
- Sometimes it's resource unavailability (RDS down)

**Solution - Multiple Scenarios:**
- ✅ Trains team to classify failures (not all errors are the same)
- ✅ Teaches diagnostic thinking (how to distinguish causes)
- ✅ Validates recovery procedures (each has its own fix)
- ✅ Tests resilience (system should recover from any scenario)

**Real-world impact:** On-call teams need to handle different failure types; this builds that muscle.

---

# PART 3: LAB 2 — CloudFront + Origin Cloaking + WAF (Edge Security)

## WHAT Was Built

A **global CDN with Web Application Firewall and origin protection** that:
- Caches content at edge (200+ locations worldwide)
- Blocks DDoS attacks and malicious requests
- Prevents direct database access via origin cloaking
- Routes all traffic through CloudFront (not directly to ALB)

**Architecture Change:**

**Before Lab 2:**
```
Internet → ALB (public IP) → EC2 → RDS
❌ No caching (high latency)
❌ No DDoS protection
❌ Origin IP discoverable
❌ All attacks hit origin
```

**After Lab 2:**
```
Internet → CloudFront (200+ edge locations) → ALB → EC2 → RDS
✅ Cached responses served from edge
✅ DDoS absorbed at edge (Shield Standard)
✅ WAF blocks malicious requests
✅ Origin cloaked (3-layer protection)
```

**New Components:**
- CloudFront Distribution (CDN)
- Web Application Firewall (WAF) - CloudFront scope
- Route53 DNS pointing to CloudFront
- CloudFront Prefix List (IP allowlist)
- Custom origin headers (secret validation)
- ALB listener rules (header verification)

---

## HOW It Was Implemented

### CloudFront CDN Distribution

**File:** `lab2_cloudfront_alb.tf.disabled` (excerpt)

**Pattern 1: CloudFront Distribution**
```terraform
resource "aws_cloudfront_distribution" "main" {
  origin {
    domain_name = aws_lb.alb.dns_name
    origin_id   = "ALB"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"  # Force HTTPS to origin
      origin_ssl_protocols   = ["TLSv1.2"]
    }
    
    # Add secret header to all origin requests
    custom_header {
      name  = "X-Chrisbarm-Growl"
      value = random_password.secret_value.result  # 32-char random
    }
  }
  
  enabled = true
  
  # Cache behavior
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB"
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300  # 5 minutes
    max_ttl                = 3600 # 1 hour
  }
  
  # Attach WAF
  web_acl_id = aws_wafv2_web_acl.cloudfront_waf.arn
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
  }
}
```

### Origin Cloaking: Three-Layer Defense

**Layer 1: IP Allowlist (AWS Managed Prefix List)**

```terraform
# Use AWS-maintained list of CloudFront IPs
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# ALB security group: only CloudFront IPs can reach port 443
resource "aws_security_group_rule" "alb_from_cloudfront" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  security_group_id = aws_security_group.alb.id
}

# What this blocks:
# ❌ Direct ALB access: curl https://alb.internal.elb.amazonaws.com → timeout
# ❌ Random IP access: curl https://10.0.2.100 → 403 Forbidden
# ❌ Attacker with different IP: automatically blocked
```

**Why This Works:**
- ✅ AWS maintains the prefix list automatically
- ✅ If CloudFront IP ranges change, security group updates automatically
- ✅ Stateless (firewall rule, not application logic)
- ✅ Free (no additional cost)

**Layer 2: Custom Header Validation (Secret Handshake)**

```terraform
# CloudFront adds secret header to all origin requests
resource "random_password" "secret_origin_value" {
  length  = 32
  special = true
}

# ALB listener rule: verify header before forwarding
resource "aws_lb_listener_rule" "require_secret_header" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
  
  condition {
    http_header {
      http_header_name = "X-Chrisbarm-Growl"
      values           = [random_password.secret_origin_value.result]
    }
  }
}

# What this blocks:
# ❌ Attacker spoofs CloudFront IP but lacks header → 403 Forbidden
# ❌ Even if attacker guesses wrong header → 403 Forbidden
# ✅ Only CloudFront knows the secret → can forward
```

**Why This Works:**
- ✅ Defense in depth (if Layer 1 fails, Layer 2 still blocks)
- ✅ Secret stored in Terraform state (only infra team sees it)
- ✅ Simple application-level check
- ✅ Transparent to backend app (app doesn't know about it)

**Layer 3: WAF Rules (Application-Level Protection)**

```terraform
resource "aws_wafv2_web_acl" "cloudfront_waf" {
  scope       = "CLOUDFRONT"  # Global scope
  default_action {
    allow {}  # Default: allow all
  }
  
  # AWS Managed Rules for common attacks
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 0
    
    action {
      block {}  # Block if rule triggers
    }
    
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
        
        # These rules detect:
        # - SQL injection: SELECT * FROM users WHERE id=1' OR '1'='1
        # - XSS: <script>alert('xss')</script>
        # - RFI: /index.php?page=../../../etc/passwd
        # - LFI: include($_GET['file'])
        # - PHP injection
        # - etc.
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }
  
  # Bot Control (optional premium rule)
  rule {
    name     = "AWSManagedRulesBotControlRuleSet"
    priority = 1
    
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"
      }
    }
    
    action {
      block {}
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BotControlMetric"
      sampled_requests_enabled   = true
    }
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CloudFrontWAFMetric"
    sampled_requests_enabled   = true
  }
}
```

### DNS Configuration (Route53)

```terraform
resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "chrisbdevsecops.com"
  type    = "A"
  
  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# Points domain to CloudFront, not ALB
# Users see: chrisbdevsecops.com → CloudFront
# Attackers trying to find origin: ❌ only see CloudFront IP
```

---

## WHY This Architecture

### Why CloudFront CDN?

**Problem:** Direct ALB access means:
- Every user request hits the same ALB (potential bottleneck)
- High latency for users far from AWS region
- All traffic consumes ALB capacity

**Solution - CloudFront:**
- ✅ Content cached at 200+ edge locations
- ✅ User requests served from nearest edge (ms latency)
- ✅ Cache hits don't touch origin (massive bandwidth savings)
- ✅ DDoS attack traffic absorbed at edge (not origin)

**Real-world impact:** Netflix uses CloudFront; latency improvement = huge user experience gain.

### Why WAF at CloudFront (Not ALB)?

**Problem:** If WAF only at ALB:
- Malicious requests still travel across internet to ALB
- Bandwidth wasted on DDoS traffic
- Origin consumes resources processing attacks

**Solution - CloudFront WAF:**
- ✅ Malicious requests blocked at edge (before reaching ALB)
- ✅ DDoS attacks absorbed early
- ✅ Clean traffic reaches ALB (less load)
- ✅ WAF in CloudFront scope = globally deployed (not just one region)

**Real-world impact:** DDoS mitigation at scale; protects origin from being overwhelmed.

### Why Origin Cloaking (3 Layers)?

**Problem:** If ALB IP is discoverable:
- Attacker scans internet for ALB IP
- Attacker crafts direct requests to ALB (bypassing CloudFront WAF)
- Attacker directly exploits application

**Solution - Origin Cloaking:**

**Layer 1 (IP Allowlist):** 
- Blocks direct ALB access
- Even if attacker finds ALB IP, SG rule rejects

**Layer 2 (Custom Header):**
- Defense in depth
- Even if attacker spoofs CloudFront IP, missing header blocks

**Layer 3 (WAF):**
- Catches malicious requests that bypass both layers
- Final defense

**Real-world impact:** This is what companies do to protect origins. Demonstrates "defense in depth" principle.

### Why Cache TTL = 5 minutes?

**Trade-off:**
- Short TTL (5 min) = fresh content, more origin hits
- Long TTL (1 hr) = stale content, fewer origin hits

**Decision:** 5 minutes balances:
- ✅ Fresh data (users don't see 1-hour-old content)
- ✅ Cache efficiency (if 100 users access in 5 min, 99 get cache hit)
- ✅ Origin load (not hammered by repeated requests)

**Real-world:** Netflix uses longer TTLs for static content, shorter for user-specific content.

---

# PART 4: BONUS-A — Private Compute with VPC Endpoints (Hardening)

## WHAT Was Built

A **zero-internet-exposure architecture** where EC2:
- Has NO public IP (not discoverable from internet)
- Makes NO internet-bound calls (uses VPC Endpoints instead)
- Accesses AWS APIs privately (never crosses internet)
- Uses Session Manager for shell access (no SSH keys)

**Architecture Comparison:**

**Lab 1a (Public EC2):**
```
EC2 (public subnet)
  ├─ Has public IP (internet-routable)
  ├─ SSH key pair for access
  ├─ Internet route via IGW
  └─ Calls AWS APIs via internet
```

**Bonus-A (Private EC2):**
```
EC2 (private subnet)
  ├─ NO public IP (not internet-routable)
  ├─ NO SSH keys (Session Manager access)
  ├─ NO internet route (no IGW, no NAT)
  └─ Calls AWS APIs via VPC Endpoints (private)
```

**New Components:**
- 7 VPC Endpoints (SSM, EC2Messages, SSMMessages, CloudWatch Logs, Secrets Manager, KMS, S3)
- Private subnets (no internet route)
- Session Manager for shell access
- Least-privilege IAM (4 scoped policies)
- Endpoint security groups (HTTPS 443 from private subnet only)

---

## HOW It Was Implemented

### Network Architecture (Zero Internet Exposure)

**File:** `bonus_a.tf` (450+ lines)

**Pattern 1: Private Subnets (No Internet Route)**
```terraform
# Private subnet: no internet route
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = "us-east-1a"
}

# Private route table: no route to Internet Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  # NO default route to IGW (0.0.0.0/0 → igw-xxx)
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Result: Packets destined for internet (e.g., 8.8.8.8) have no route → dropped
```

**Pattern 2: EC2 Without Public IP**
```terraform
resource "aws_instance" "app" {
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false  # CRITICAL: no public IP
  
  # Even if subnet had "map_public_ip_on_launch = true", we override
}

# Result: EC2 has only private IP (10.0.101.x); not internet-routable
```

**Pattern 3: VPC Endpoints (Private AWS API Access)**

```terraform
# VPC Endpoint for Systems Manager (SSM)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true  # Resolves ssm.us-east-1.amazonaws.com → endpoint IP
  
  subnet_ids         = [aws_subnet.private.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}

# VPC Endpoint for EC2Messages (Session Manager protocol)
resource "aws_vpc_endpoint" "ec2_messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  
  subnet_ids         = [aws_subnet.private.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}

# VPC Endpoint for SSM Messages (Session Manager protocol)
resource "aws_vpc_endpoint" "ssm_messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  
  subnet_ids         = [aws_subnet.private.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}

# VPC Endpoint for CloudWatch Logs
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  
  subnet_ids         = [aws_subnet.private.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}

# VPC Endpoint for Secrets Manager
resource "aws_vpc_endpoint" "secrets" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  
  subnet_ids         = [aws_subnet.private.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}

# VPC Endpoint for KMS
resource "aws_vpc_endpoint" "kms" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.kms"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  
  subnet_ids         = [aws_subnet.private.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}

# Gateway Endpoint for S3 (different from Interface endpoints)
resource "aws_vpc_endpoint" "s3" {
  vpc_id           = aws_vpc.main.id
  service_name     = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  
  route_table_ids = [aws_route_table.private.id]
}

# Result: EC2 can call these AWS services via private IPs (not internet)
```

**Pattern 4: VPC Endpoint Security Group**
```terraform
resource "aws_security_group" "vpc_endpoints" {
  vpc_id = aws_vpc.main.id
  
  ingress {
    from_port   = 443  # HTTPS only
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]  # From VPC (private subnet)
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # All protocols
    cidr_blocks = ["0.0.0.0/0"]  # Anywhere (endpoints respond to VPC)
  }
}

# Result: Only private subnet can access endpoints (port 443)
# Internet cannot reach endpoints (no internet gateway)
```

### Session Manager Access (No SSH Keys)

**Traditional EC2 Access:**
```bash
# Requires SSH key
ssh -i key.pem ec2-user@54.91.122.42
```

**Bonus-A Access (Session Manager):**
```bash
# No SSH key needed; authenticated via IAM role
aws ssm start-session --target i-0123456789abcdef --region us-east-1

# Opens interactive shell
```

**How Session Manager Works:**
1. SSM Agent running on EC2 (started by EC2 launch)
2. Agent contacts SSM endpoint (private, via VPC endpoint)
3. User authenticates to AWS (IAM credentials, not SSH key)
4. Session established through AWS infrastructure
5. All commands logged to CloudTrail

**Benefits:**
- ✅ No SSH keys to manage/rotate
- ✅ Access controlled via IAM (same identity system)
- ✅ All sessions logged (audit trail)
- ✅ Can revoke access instantly (disable IAM role)
- ✅ Works through NAT/proxies (uses HTTPS internally)

### Least-Privilege IAM (4 Scoped Policies)

```terraform
# Policy 1: Read specific secret
resource "aws_iam_role_policy" "secrets_access" {
  role = aws_iam_role.ec2.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:lab1a/rds/mysql*"
      # ✅ Only THIS secret; not all secrets
    }]
  })
}

# Policy 2: Write to specific log group
resource "aws_iam_role_policy" "cloudwatch_logs" {
  role = aws_iam_role.ec2.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:us-east-1:ACCOUNT:log-group:/lab/bonus-a*"
      # ✅ Only /lab/bonus-a* log group; not all logs
    }]
  })
}

# Policy 3: Decrypt with specific KMS key
resource "aws_iam_role_policy" "kms_decrypt" {
  role = aws_iam_role.ec2.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["kms:Decrypt"]
      Resource = "arn:aws:kms:us-east-1:ACCOUNT:key/12345678-1234-1234-1234-123456789012"
      # ✅ Only THIS key; not all KMS keys
    }]
  })
}

# Policy 4: Session Manager basics
resource "aws_iam_role_policy" "session_manager" {
  role = aws_iam_role.ec2.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
        "ec2messages:GetMessages"
      ]
      Resource = "*"  # Session Manager requires this
    }]
  })
}

# Result: If EC2 compromised, attacker limited to:
# - Reading ONE specific secret
# - Writing to ONE log group
# - Decrypting with ONE key
# ❌ Cannot access other secrets, logs, KMS keys, or AWS resources
```

---

## WHY This Architecture

### Why Zero Internet Exposure?

**Problem:** Internet-exposed instances are vulnerable to:
- Port scans (attackers find exposed services)
- SSH brute-force attacks
- SSH key compromise (keys in git, stolen, etc.)
- DDoS attacks (direct targets)
- Zero-day exploits (unpatched vulnerabilities)

**Solution - No Public IP:**
- ✅ EC2 not discoverable from internet
- ✅ No SSH port exposed (no brute-force possible)
- ✅ No SSH keys needed (no keys to compromise)
- ✅ DDoS attackers don't know where to attack
- ✅ Vastly reduces attack surface

**Real-world impact:** This is Netflix's pattern. Google Cloud calls this "Beyondcorp"—zero internet exposure.

### Why VPC Endpoints Over NAT Gateway?

**NAT Gateway Approach:**
- EC2 in private subnet
- NAT Gateway in public subnet
- Private subnet routes all traffic through NAT
- NAT translates EC2 IP to NAT IP (appears to come from NAT)
- Costs: NAT Gateway = $32/month + data charges

**VPC Endpoint Approach:**
- EC2 in private subnet
- VPC Endpoints in private subnet
- Private subnet routes specific AWS service traffic to endpoints
- Traffic stays within AWS network (doesn't cross internet)
- Costs: VPC Endpoints = $7/month each + data charges

**When to use each:**
- NAT: If you need general internet access (download packages from pypi.org, etc.)
- VPC Endpoints: If you ONLY need AWS service access (no internet)

**Bonus-A choice:** VPC Endpoints only → more secure, cleaner architecture

**Real-world impact:** Cost savings + better security + demonstrates architectural maturity.

### Why Session Manager Over SSH?

**SSH Approach:**
- Generate SSH key pair
- Store private key on developer machine (risky)
- SSH key rotates infrequently (manual process)
- Access control: "who has the key file?"
- Audit trail: no logging of commands

**Session Manager Approach:**
- No keys needed (uses IAM credentials)
- Access control: "who has IAM permissions?"
- Sessions logged to CloudTrail
- Audit trail: every command recorded
- Access revoked instantly (disable IAM role)
- Works over HTTPS (works through corporate proxies)

**Real-world impact:** AWS best practice; eliminates SSH key management burden.

### Why Least-Privilege IAM at Compute Layer?

**Problem:** If EC2 role has broad permissions:
- If EC2 compromised, attacker has broad AWS access
- Attacker could create IAM users, delete backups, etc.

**Solution - Scoped Policies:**
- ✅ EC2 role limited to specific resources
- ✅ Blast radius bounded (can't access everything)
- ✅ Even if EC2 compromised, attacker confined

**Real-world example:**
- Broad role: `"Action": "s3:*", "Resource": "*"` → attacker deletes all S3 buckets
- Scoped role: `"Action": "s3:GetObject", "Resource": "arn:aws:s3:::my-bucket/app-config/*"` → attacker can only read app config

**Real-world impact:** This is #1 AWS Well-Architected principle: "least privilege".

---

# CROSS-CUTTING CONCERNS & WHAT'S MISSING

## Verification & Automation (What's Included)

**Lab 1a Verification:**
- `verify_lab.sh` - Infrastructure checks (9 steps)
- `verify_ec2_secrets_access.sh` - EC2 can read secret?
- `verify_secrets_and_iam.sh` - IAM role configured?
- `test_app.sh` - Application endpoints working?

**Bonus-A Verification (5 comprehensive tests):**
- `verify_bonus_a_1_private_ip.sh` - EC2 has NO public IP?
- `verify_bonus_a_2_vpc_endpoints.sh` - All 7 endpoints exist?
- `verify_bonus_a_3_session_manager.sh` - SSM agent registered?
- `verify_bonus_a_4_config_stores.sh` - Secrets Manager accessible?
- `verify_bonus_a_5_cloudwatch_logs.sh` - CloudWatch Logs working?
- `run_bonus_a_verification.sh` - Run all tests automatically

**Lab 2 Verification:**
- `verify_lab2_complete.sh` - CloudFront, WAF, origin cloaking

**Security Testing Tools:**
- `malgus_cli.py` - Infrastructure management CLI
- `malgus_cloudfront_cache_probe.py` - Cache behavior testing
- `malgus_origin_cloak_tester.py` - Origin protection validation
- `malgus_waf_block_spike_detector.py` - WAF effectiveness testing

---

## Potential Gaps/Future Improvements

### 1. **Database Layer**
- Current: Single RDS instance
- Could add: Aurora MySQL (better performance, automatic backups)
- Could add: Read replicas (for read-heavy workloads)

### 2. **Application Scaling**
- Current: Single EC2 instance
- Could add: Auto Scaling Group (multiple instances)
- Could add: Application Load Balancer health checks

### 3. **Caching**
- Current: None at application layer
- Could add: ElastiCache (Redis/Memcached)
- Could add: CloudFront cache headers optimization

### 4. **Secrets Rotation**
- Current: Manual (runbook-based)
- Could add: AWS Secrets Manager automatic rotation (Lambda-based)

### 5. **Compliance & Audit**
- Current: CloudTrail (default)
- Could add: CloudTrail analysis (Athena queries)
- Could add: Config Rules (compliance checking)

### 6. **Disaster Recovery**
- Current: RDS automated backups
- Could add: Cross-region RDS read replica
- Could add: Backup testing (restore validation)

### 7. **Cost Optimization**
- Current: On-demand instances
- Could add: Savings Plans, Reserved Instances
- Could add: Cost anomaly detection

### 8. **Advanced Observability**
- Current: CloudWatch Logs + Alarms
- Could add: X-Ray (distributed tracing)
- Could add: Application Performance Monitoring (APM)

### 9. **CI/CD Integration**
- Current: Manual Terraform apply
- Could add: GitHub Actions pipeline
- Could add: Terraform plan validation, cost estimation

### 10. **Infrastructure Testing**
- Current: Manual verification scripts
- Could add: Automated compliance tests (Terraform Cloud)
- Could add: Security scanning (tfsec, checkov)

---

# SUMMARY TABLE: What, How, Why by Lab

| Lab | WHAT | HOW | WHY |
|-----|------|-----|-----|
| **1a** | EC2 ↔ RDS integration | Terraform VPC, IAM roles, Secrets Manager, Flask app | Credential-free access, least-privilege, multi-AZ |
| **1b** | Incident response | CloudWatch Logs, Metrics, Alarms, SNS, Recovery scripts | Detect failures early, automate recovery, reduce MTTR |
| **2** | Edge security | CloudFront CDN, WAF, Route53, Origin cloaking (3 layers) | Global performance, DDoS mitigation, origin protection |
| **Bonus-A** | Zero internet exposure | Private EC2, 7 VPC Endpoints, Session Manager, scoped IAM | Minimal attack surface, AWS-only networking, security hardening |

---

# FOR INTERVIEWS: Key Messages

### 30-Second Version
> "I built a multi-tier AWS infrastructure that progresses from basic EC2-to-RDS integration to enterprise-grade security. Each lab teaches a pattern: credential-free access, incident response automation, edge security, and zero-internet exposure. It's fully automated with Terraform, documented, and tested."

### 2-Minute Version
> "Lab 1a establishes secure database connectivity using IAM roles and Secrets Manager—so credentials never touch application code. Lab 1b adds observability: CloudWatch logs, metrics, and alarms detect failures automatically, and recovery scripts fix issues without redeployment. Lab 2 adds global edge security with CloudFront, WAF, and 3-layer origin cloaking to protect the origin. Bonus-A is the hardening: the EC2 instance has no public IP, no SSH keys, and only accesses AWS services via VPC Endpoints. All 4 layers work together to demonstrate 'defense in depth'."

### 5-Minute Discussion Topics
1. **IAM Roles:** Why NOT hardcoded credentials (credentials in logs, environment variables, git history)
2. **Origin Cloaking:** The 3 layers (IP allowlist, custom header, WAF rules) and why defense-in-depth matters
3. **VPC Endpoints:** Why private AWS API access beats NAT Gateway for security-first architecture
4. **Incident Response:** Why automation matters (MTTR reduction, consistency, auditability)
5. **Least Privilege:** Why scoped IAM policies limit blast radius (Netflix model)

---

