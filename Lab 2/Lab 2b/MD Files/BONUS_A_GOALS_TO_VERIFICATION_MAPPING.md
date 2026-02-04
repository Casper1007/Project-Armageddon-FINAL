# Bonus A: Design Goals ↔ Implementation Mapping

## Executive Summary

This document maps your **5 design goals** to **5 verification tests** and shows exactly where they're implemented in code and documented.

---

## Design Goal 1: EC2 is Private (No Public IP)

### 🎯 Design Goal
```
EC2 is private (no public IP)
```

### ✅ Implementation

**Terraform Code** (bonus_a.tf):
```hcl
resource "aws_instance" "bonus_a_ec2" {
  ami                         = "ami-0030e4319cbf4dbf2"
  instance_type               = var.ec2_instance_type
  subnet_id                   = local.private_subnet
  iam_instance_profile        = aws_iam_instance_profile.bonus_a_ec2_profile.name
  associate_public_ip_address = false  # ← KEY: No public IP
  vpc_security_group_ids      = [aws_security_group.bonus_a_ec2_sg.id]
  user_data                   = file("${path.module}/1a_user_data.sh")
}
```

**Why This Works**:
- `associate_public_ip_address = false` explicitly prevents public IP assignment
- Instance placed in private subnet (no route to IGW)
- No EIP (Elastic IP) attached

### 📋 Verification Test

```bash
# Test 1: Prove EC2 is private (no public IP)
aws ec2 describe-instances \
  --instance-ids <INSTANCE_ID> \
  --query "Reservations[].Instances[].PublicIpAddress"

# Expected: null ✓
```

**Automated Check**: [verify_bonus_a_comprehensive.sh](verify_bonus_a_comprehensive.sh) → **CHECK 1**

**Documentation**:
- 📖 [BONUS_A_ARCHITECTURE_GUIDE.md](BONUS_A_ARCHITECTURE_GUIDE.md) → Architecture Diagram section
- 📖 [BONUS_A_ARCHITECTURE_GUIDE.md](BONUS_A_ARCHITECTURE_GUIDE.md) → Private EC2 Instance section
- 📋 [BONUS_A_QUICK_REFERENCE.md](BONUS_A_QUICK_REFERENCE.md) → Test 1 section

---

## Design Goal 2: No SSH Required (Use SSM Session Manager)

### 🎯 Design Goal
```
No SSH required (use SSM Session Manager)
```

### ✅ Implementation

**Terraform Code** (bonus_a.tf):
```hcl
# Security group: NO SSH inbound rule
resource "aws_security_group" "bonus_a_ec2_sg" {
  name_prefix = "${local.bonus_a_prefix}-ec2-"
  description = "SG for private EC2 outbound to endpoints and RDS"
  vpc_id      = local.vpc_id

  # ← NO inbound rules (Session Manager handles access)

  egress {
    description     = "HTTPS to VPC endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.bonus_a_endpoints_sg.id]
  }
}

# IAM role: Session Manager permissions
resource "aws_iam_role_policy" "bonus_a_ssm_session" {
  name_prefix = "${local.bonus_a_prefix}-ssm-session-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMSessionManagerCore"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages"
        ]
        Resource = "*"
      }
    ]
  })
}
```

**Why This Works**:
- No SSH port (22) in security group
- No SSH key pair required (key_name = null)
- IAM role grants Session Manager permissions
- SSM agent talks to SSM service via VPC endpoints

### 📋 Verification Test

```bash
# Test 3: Prove Session Manager path works (no SSH)
aws ssm describe-instance-information \
  --query "InstanceInformationList[].InstanceId"

# Expected: your private EC2 instance ID appears ✓
```

**Practical Use**:
```bash
# Start interactive session (SSH-free)
aws ssm start-session --target i-xxxxx --region us-east-1

# Inside EC2 instance now:
$ whoami
ubuntu
```

**Automated Check**: [verify_bonus_a_comprehensive.sh](verify_bonus_a_comprehensive.sh) → **CHECK 3** & **CHECK 4**

**Documentation**:
- 📖 [BONUS_A_ARCHITECTURE_GUIDE.md](BONUS_A_ARCHITECTURE_GUIDE.md) → Security Groups section
- 📖 [BONUS_A_QUICK_REFERENCE.md](BONUS_A_QUICK_REFERENCE.md) → Session Manager section
- 📖 [BONUS_A_DEPLOYMENT_WALKTHROUGH.md](BONUS_A_DEPLOYMENT_WALKTHROUGH.md) → Phase 7

---

## Design Goal 3: Private Subnets Don't Need NAT for AWS Services

### 🎯 Design Goal
```
Private subnets don't need NAT to talk to AWS control-plane services
```

### ✅ Implementation

**Terraform Code** (bonus_a.tf):
```hcl
# VPC Interface Endpoints (replace NAT for AWS APIs)

resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type = "Interface"
  subnet_ids        = local.endpoint_subnets
  security_group_ids = [aws_security_group.bonus_a_endpoints_sg.id]
  private_dns_enabled = true  # ← KEY: Route via private DNS
}

# EC2Messages, SSMMessages, Logs, SecretsManager, KMS (same pattern)
```

**Why This Works**:
- Interface Endpoints provide private access to AWS services
- Private DNS enabled (`private_dns_enabled = true`)
  - Routes `ssm.us-east-1.amazonaws.com` → endpoint ENI (10.0.x.x)
  - No internet traffic, no NAT needed
- EC2 can reach AWS control-plane via HTTPS (443) only

**Example Traffic Flow**:
```
EC2 (10.0.101.x)
  ↓
SSM Endpoint ENI (10.0.x.x)
  ↓
AWS SSM Service (internal)
  ↓
Response back through endpoint
  ✓ All inside VPC, zero internet exposure
```

### 📋 Verification Test

```bash
# Test 2: Prove VPC endpoints exist
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query "VpcEndpoints[].ServiceName"

# Expected: list includes:
# - com.amazonaws.us-east-1.ssm
# - com.amazonaws.us-east-1.ec2messages
# - com.amazonaws.us-east-1.ssmmessages
# - com.amazonaws.us-east-1.logs
# - com.amazonaws.us-east-1.secretsmanager
# - com.amazonaws.us-east-1.kms
# - com.amazonaws.us-east-1.s3
✓
```

**Proof Inside EC2**:
```bash
# Inside EC2 session, resolve endpoint DNS:
$ nslookup ssm.us-east-1.amazonaws.com
Name:      ssm.us-east-1.amazonaws.com
Address:   10.0.101.x  (← Private IP! Not internet)

# Verify HTTPS connectivity
$ curl -v https://ssm.us-east-1.amazonaws.com/
* Connected to ssm.us-east-1.amazonaws.com (10.0.101.x) port 443 (#0)
* TLS handshake succeeds
✓ All internal, no NAT needed
```

**Automated Check**: [verify_bonus_a_comprehensive.sh](verify_bonus_a_comprehensive.sh) → **CHECK 2**

**Documentation**:
- 📖 [BONUS_A_ARCHITECTURE_GUIDE.md](BONUS_A_ARCHITECTURE_GUIDE.md) → VPC Endpoints section (detailed breakdown)
- 📖 [BONUS_A_ARCHITECTURE_GUIDE.md](BONUS_A_ARCHITECTURE_GUIDE.md) → Architecture Diagram
- 📖 [BONUS_A_QUICK_REFERENCE.md](BONUS_A_QUICK_REFERENCE.md) → VPC Endpoints section

---

## Design Goal 4: Use VPC Interface Endpoints (Specific Services)

### 🎯 Design Goal
```
Use VPC Interface Endpoints for:
  - SSM, EC2Messages, SSMMessages (Session Manager)
  - CloudWatch Logs
  - Secrets Manager
  - KMS (optional but realistic)
Use S3 Gateway Endpoint (common "gotcha" for private environments)
```

### ✅ Implementation

**Terraform Code** (bonus_a.tf):

**Interface Endpoints**:
```hcl
# Each follows this pattern:
resource "aws_vpc_endpoint" "ssm" {
  vpc_id                = local.vpc_id
  service_name          = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type     = "Interface"  # ← Interface type
  subnet_ids            = local.endpoint_subnets
  security_group_ids    = [aws_security_group.bonus_a_endpoints_sg.id]
  private_dns_enabled   = true  # ← Essential for DNS resolution
}
# (Repeated for: ec2messages, ssmmessages, logs, secretsmanager, kms)
```

**Gateway Endpoint** (S3 - special case):
```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = local.vpc_id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  # S3 uses Gateway type (no subnet/SG config needed)
  # Routes through main private route table automatically
}
```

**Why Each Endpoint Matters**:

| Endpoint | Purpose | Why Needed |
|----------|---------|-----------|
| **SSM** | Agent registration | EC2 to report to Systems Manager |
| **EC2Messages** | Session Manager support | Handler for console access |
| **SSMMessages** | Session Manager shell | Interactive shell I/O |
| **Logs** | CloudWatch Logs delivery | App writes logs centrally |
| **Secrets Manager** | Credential retrieval | App reads DB passwords at startup |
| **KMS** | Encryption operations | Optional but realistic for key rotations |
| **S3** (Gateway) | Package repos, golden AMIs | OS package installs without yum internet |

### 📋 Verification Test

```bash
# Test 2: Prove all required VPC endpoints exist
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query "VpcEndpoints[].[ServiceName, State]" \
  --output table

# Expected: ALL 7 in "available" state
✓ com.amazonaws.us-east-1.ssm                  | available
✓ com.amazonaws.us-east-1.ec2messages          | available
✓ com.amazonaws.us-east-1.ssmmessages          | available
✓ com.amazonaws.us-east-1.logs                 | available
✓ com.amazonaws.us-east-1.secretsmanager       | available
✓ com.amazonaws.us-east-1.kms                  | available
✓ com.amazonaws.us-east-1.s3                   | available
```

**Automated Check**: [verify_bonus_a_comprehensive.sh](verify_bonus_a_comprehensive.sh) → **CHECK 2**

**Documentation**:
- 📖 [BONUS_A_ARCHITECTURE_GUIDE.md](BONUS_A_ARCHITECTURE_GUIDE.md) → VPC Endpoints section (7 endpoints explained)
- 📖 [BONUS_A_QUICK_REFERENCE.md](BONUS_A_QUICK_REFERENCE.md) → VPC Endpoints CLI commands

---

## Design Goal 5: Least-Privilege IAM (Specific Secrets & Parameters)

### 🎯 Design Goal
```
Tighten IAM:
  - GetSecretValue only for your secret
  - GetParameter(s) only for your path
```

### ✅ Implementation

**Terraform Code** (bonus_a.tf):

**Policy 1: Secrets Manager (Scoped)**
```hcl
resource "aws_iam_role_policy" "bonus_a_secrets_manager" {
  name_prefix = "${local.bonus_a_prefix}-secrets-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetLabSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"  # ← Only GetSecretValue
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:lab1a/rds/mysql*"
        # ↑ Only THIS secret, not all secrets
      }
    ]
  })
}
```

**Policy 2: Parameter Store (Scoped Path)**
```hcl
resource "aws_iam_role_policy" "bonus_a_parameter_store" {
  name_prefix = "${local.bonus_a_prefix}-params-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetLabParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",          # ← Only read
          "ssm:GetParameters",          # ↑
          "ssm:GetParametersByPath"     # ↑
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/lab/*"
        # ↑ Only /lab/* path (not /prod/*, etc.)
      }
    ]
  })
}
```

**What's NOT Allowed**:
```hcl
# ❌ This is TOO broad:
Resource = "*"  # Read all secrets/parameters

# ❌ This is TOO many actions:
Action = "secretsmanager:*"  # Can delete, rotate, manage

# ❌ This is wrong scoping:
Resource = "arn:aws:ssm:...:parameter/prod/*"  # Wrong path
```

### 📋 Verification Test

```bash
# Test 4: Prove instance can read BOTH config stores
# (Scoped access, not blanket)

# Inside EC2 session:

# Read parameter (only under /lab/ path)
$ aws ssm get-parameter --name /lab/db/endpoint
{
  "Parameter": {
    "Name": "/lab/db/endpoint",
    "Value": "chrisbarm-rds01.xxxxx.us-east-1.rds.amazonaws.com"
  }
}
✓ Success

# Read secret (only lab1a/rds/mysql)
$ aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql
{
  "SecretString": "{\"username\": \"admin\", \"password\": \"...\", ...}"
}
✓ Success

# Try to read OTHER parameter (should fail)
$ aws ssm get-parameter --name /prod/api/key
Error: User is not authorized to perform: ssm:GetParameter

# Try to read OTHER secret (should fail)
$ aws secretsmanager get-secret-value --secret-id prod/other/key
Error: User is not authorized to perform: secretsmanager:GetSecretValue

✓ Least-privilege verified!
```

**Automated Check**: [verify_bonus_a_comprehensive.sh](verify_bonus_a_comprehensive.sh) → **CHECK 4**

**Documentation**:
- 📖 [BONUS_A_IAM_DEEP_DIVE.md](BONUS_A_IAM_DEEP_DIVE.md) → Complete IAM design (copy-paste policies)
- 📖 [BONUS_A_IAM_DEEP_DIVE.md](BONUS_A_IAM_DEEP_DIVE.md) → Anti-patterns section
- 📖 [BONUS_A_QUICK_REFERENCE.md](BONUS_A_QUICK_REFERENCE.md) → IAM Policy Reference
- 📖 [BONUS_A_ARCHITECTURE_GUIDE.md](BONUS_A_ARCHITECTURE_GUIDE.md) → IAM Role section

---

## Bonus Verification: CloudWatch Logs Delivery

### 🎯 Verification Requirement
```
Prove CloudWatch logs delivery path is available via endpoint
```

### ✅ Implementation

**Terraform Code** (bonus_a.tf):
```hcl
# 1. CloudWatch Logs VPC Endpoint
resource "aws_vpc_endpoint" "logs" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type = "Interface"
  subnet_ids        = local.endpoint_subnets
  security_group_ids = [aws_security_group.bonus_a_endpoints_sg.id]
  private_dns_enabled = true
}

# 2. IAM permission to write logs
resource "aws_iam_role_policy" "bonus_a_cloudwatch_logs" {
  name_prefix = "${local.bonus_a_prefix}-cloudwatch-logs-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/bonus-a-rds-app:*"
      }
    ]
  })
}

# 3. Log group
resource "aws_cloudwatch_log_group" "bonus_a_logs" {
  name              = "/aws/ec2/${local.bonus_a_prefix}-rds-app"
  retention_in_days = 7
}
```

### 📋 Verification Test

```bash
# Test 5: Prove CloudWatch logs delivery path is available
aws logs describe-log-streams \
  --log-group-name /aws/ec2/bonus-a-rds-app

# Expected: log group exists and is ready for writes
# {
#   "logStreams": [...]  (or empty if no logs yet)
# }
✓
```

**Automated Check**: [verify_bonus_a_comprehensive.sh](verify_bonus_a_comprehensive.sh) → **CHECK 5**

**Documentation**:
- 📖 [BONUS_A_ARCHITECTURE_GUIDE.md](BONUS_A_ARCHITECTURE_GUIDE.md) → CloudWatch Log Group section
- 📖 [BONUS_A_QUICK_REFERENCE.md](BONUS_A_QUICK_REFERENCE.md) → CloudWatch Logs CLI commands

---

## Summary: Goals ↔ Tests ↔ Code ↔ Docs

| Design Goal | Verification Test | Code File | Documentation |
|---|---|---|---|
| **EC2 is private** | No public IP | bonus_a.tf line ~380 | ARCH § Private EC2 |
| **No SSH needed** | Session Manager works | bonus_a.tf line ~250 | ARCH § Security Groups, IAM § SSM |
| **No NAT for APIs** | VPC endpoints exist | bonus_a.tf line ~110 | ARCH § VPC Endpoints |
| **Use specific endpoints** | All 7 endpoints available | bonus_a.tf line ~110-205 | ARCH § Components |
| **Least-privilege IAM** | Read scoped secrets/params | bonus_a.tf line ~240-330 | IAM_DEEP_DIVE § Full guide |
| **CloudWatch available** | Logs group ready | bonus_a.tf line ~400 | ARCH § CloudWatch |

---

## Interview Talking Points (Complete Answers)

### Q1: "Explain your Bonus A design in 2 minutes"
> "I deployed a private EC2 instance using Terraform with VPC Endpoints replacing NAT. Here's the key: the instance has no public IP, eliminating internet exposure. Session Manager provides SSH-free access via the SSM endpoint. The IAM role is scoped—readable only to a specific RDS secret and `/lab/*` parameters. All infrastructure is code, fully version-controlled, and verified by automated scripts. This mirrors practices at banks and healthcare firms that require PCI-DSS/HIPAA compliance."

### Q2: "Why VPC Endpoints instead of NAT?"
> "Three reasons: First, endpoints provide direct AWS API access without internet routing—no latency, no egress charges. Second, each endpoint is a subnet resource, not a single NAT Gateway bottleneck. Third, they're compliance-required in regulated orgs—they reduce attack surface by keeping AWS service traffic internal. Trade-off: endpoints cost ~$50/month vs. NAT's $33/month, but heavy API traffic breaks even fast."

### Q3: "Walk me through your IAM policies"
> "Four inline policies scoped to resources: (1) SSM agent communication—these are service APIs, not resource-specific. (2) CloudWatch Logs scoped to `/aws/ec2/bonus-a-rds-app` log group only, preventing writes to other teams' logs. (3) Secrets Manager scoped to `lab1a/rds/mysql*` secret—attackers can't read prod secrets if they compromise this instance. (4) Parameter Store scoped to `/lab/*` path—same defense-in-depth. If the instance is breached, an attacker is trapped—they can't escalate to IAM."

### Q4: "How would you verify this deployment?"
> "Five automated checks: (1) EC2 has no public IP (`PublicIpAddress = null`). (2) Seven VPC endpoints exist in the right VPC. (3) EC2 appears in Systems Manager Fleet Manager. (4) Session Manager session reads both config stores—Parameter Store and Secrets Manager. (5) CloudWatch log group is writable. Each check is a CLI command; they're all automated in a bash script that generates a JSON report for audit trails."

---

## Quick Reference: Files & Line Numbers

| File | Resource | Lines | Purpose |
|------|----------|-------|---------|
| bonus_a.tf | Endpoint SG | 30-55 | Security group allowing HTTPS from private subnets |
| bonus_a.tf | EC2 SG | 60-95 | Security group for EC2 (no inbound, HTTPS egress) |
| bonus_a.tf | SSM Endpoint | 110-125 | VPC Interface Endpoint for SSM |
| bonus_a.tf | EC2Messages Endpoint | 130-145 | For Session Manager support |
| bonus_a.tf | SSMMessages Endpoint | 150-165 | For Session Manager shell |
| bonus_a.tf | Logs Endpoint | 170-185 | For CloudWatch Logs |
| bonus_a.tf | Secrets Manager Endpoint | 190-205 | For credential retrieval |
| bonus_a.tf | KMS Endpoint | 210-225 | For encryption operations |
| bonus_a.tf | S3 Gateway Endpoint | 230-240 | For package repos |
| bonus_a.tf | IAM Role | 250-270 | Assume policy |
| bonus_a.tf | SSM Session Policy | 275-300 | Session Manager permissions |
| bonus_a.tf | CloudWatch Policy | 305-320 | Log write permissions (scoped) |
| bonus_a.tf | Secrets Policy | 325-340 | Secret read permissions (scoped) |
| bonus_a.tf | Parameters Policy | 345-360 | Parameter read permissions (scoped path) |
| bonus_a.tf | EC2 Instance | 375-390 | Private instance, no public IP |
| bonus_a.tf | Log Group | 395-405 | CloudWatch log group |

---

## Success Checklist

Before you claim victory, verify:

- [ ] EC2 instance boots without public IP
- [ ] All 7 VPC endpoints reach "available" state
- [ ] Security groups have correct HTTPS rules
- [ ] IAM role attaches successfully
- [ ] SSM agent registers in Fleet Manager (2-3 min)
- [ ] Session Manager session starts and returns shell
- [ ] Inside session: `aws ssm get-parameter --name /lab/db/endpoint` works
- [ ] Inside session: `aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql` works
- [ ] CloudWatch log group exists at `/aws/ec2/bonus-a-rds-app`
- [ ] verify_bonus_a_comprehensive.sh shows all checks passing
- [ ] JSON verification report generated successfully

---

## Next: Practice & Refinement

1. ✅ **Deploy it** (1 hour)
2. ✅ **Verify it** (15 min)
3. ✅ **Explain it** (30 min practice)
4. 🔄 **Customize it** (add S3 bucket policy, rotate secrets, etc.)
5. 🚀 **Deploy to production** (with additional hardening)

---

**Document Version**: 1.0  
**Purpose**: Cross-reference design goals ↔ verification ↔ code ↔ documentation  
**Last Updated**: January 21, 2026
