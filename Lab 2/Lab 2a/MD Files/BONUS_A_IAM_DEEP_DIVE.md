# Bonus A: Least-Privilege IAM Deep Dive

## Philosophy

**"Least privilege is not optional—it's compliance."**

Instead of using AWS managed policies like `AmazonSSMManagedInstanceCore`, we build **scoped, inline policies** that grant only the minimum permissions needed for this specific instance.

---

## The 5-Policy Strategy

### 1️⃣ SSM Session Manager (Core)

**Purpose**: Enable shell access via Session Manager (replaces SSH)

**Policy**:
```json
{
  "Sid": "SSMSessionManagerCore",
  "Effect": "Allow",
  "Action": [
    "ssmmessages:CreateControlChannel",
    "ssmmessages:CreateDataChannel",
    "ssmmessages:OpenControlChannel",
    "ssmmessages:OpenDataChannel",
    "ec2messages:AcknowledgeMessage",
    "ec2messages:DeleteMessage",
    "ec2messages:FailMessage",
    "ec2messages:GetEndpoint",
    "ec2messages:GetMessages"
  ],
  "Resource": "*"
}
```

**Why no resource scoping here**?
- These are agent-to-control-plane APIs, not resource-specific
- AWS doesn't support principal-level scoping for these actions
- Resource "*" is acceptable because actions are generic (not admin)

**Real-world use**:
```bash
# From laptop
aws ssm start-session --target i-xxxxx
# EC2 agent uses these permissions to communicate with SSM service
```

---

### 2️⃣ CloudWatch Logs (Write-Only)

**Purpose**: Allow app to write logs; restrict to specific log group

**Policy**:
```json
{
  "Sid": "CloudWatchLogsWrite",
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogStream",
    "logs:PutLogEvents",
    "logs:DescribeLogStreams"
  ],
  "Resource": "arn:aws:logs:us-east-1:123456789012:log-group:/aws/ec2/bonus-a-rds-app:*"
}
```

**Scoping strategy**:
- ✅ **DO** specify exact log group ARN
- ✅ **DO** use wildcard at end (`*`) for log streams
- ❌ **DON'T** use `logs:*` (too broad)
- ❌ **DON'T** omit resource scoping (allows writing to any log group)

**Real-world use**:
```bash
# App running on EC2 writes to CloudWatch
# IAM policy limits writes to /aws/ec2/bonus-a-rds-app only
aws logs put-log-events \
  --log-group-name /aws/ec2/bonus-a-rds-app \
  --log-stream-name app.log \
  --log-events timestamp=$(date +%s000),message="App started"
```

**Interview talking point**:
> "We scope CloudWatch logs to a specific log group ARN. This prevents the instance from accidentally writing to other teams' log groups."

---

### 3️⃣ Secrets Manager (Read-Specific Secret)

**Purpose**: Read only the Lab 1a RDS credentials; deny everything else

**Policy**:
```json
{
  "Sid": "GetLabSecret",
  "Effect": "Allow",
  "Action": [
    "secretsmanager:GetSecretValue"
  ],
  "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:lab1a/rds/mysql*"
}
```

**Why the wildcard at end**?
- Secrets Manager adds a 6-character suffix to secret ARNs automatically
- Example: `lab1a/rds/mysql` → `lab1a/rds/mysql-AbCdEf`
- The `*` ensures we match the actual ARN

**Scoping strategy**:
- ✅ **DO** specify exact secret name with wildcard (`secret:lab1a/rds/mysql*`)
- ✅ **DO** limit action to `GetSecretValue` only (no `PutSecret`, `DeleteSecret`)
- ❌ **DON'T** use `secretsmanager:*` (allows secret manipulation)
- ❌ **DON'T** use `secretsmanager:GetSecretValue` with `Resource: "*"` (reads all secrets)

**Real-world use**:
```bash
# App reads DB credentials during startup
aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql
# Returns JSON: { "username": "admin", "password": "***", "host": "...", ... }
```

**Interview talking point**:
> "The instance can read only the Lab 1a RDS secret. If credentials for other services exist (e.g., third-party APIs), this instance cannot access them. That's defense-in-depth."

---

### 4️⃣ Parameter Store (Read-Only Path)

**Purpose**: Read parameters under `/lab/` path; nothing else

**Policy**:
```json
{
  "Sid": "GetLabParameters",
  "Effect": "Allow",
  "Action": [
    "ssm:GetParameter",
    "ssm:GetParameters",
    "ssm:GetParametersByPath"
  ],
  "Resource": "arn:aws:ssm:us-east-1:123456789012:parameter/lab/*"
}
```

**Scoping strategy**:
- ✅ **DO** use path-based scoping (`/lab/*`)
- ✅ **DO** include `GetParametersByPath` for discovery
- ✅ **DO** omit `PutParameter`, `DeleteParameter` (read-only)
- ❌ **DON'T** use `ssm:GetParameter` with `Resource: "*"` (reads all parameters)
- ❌ **DON'T** use `ssm:PutParameter` (write access)

**Real-world use**:
```bash
# App reads DB endpoint and port during startup
aws ssm get-parameters-by-path --path /lab/db/ --recursive

# Returns:
# /lab/db/endpoint = rds-instance.xxxxxx.us-east-1.rds.amazonaws.com
# /lab/db/port = 3306
# /lab/db/name = labdb
```

**Interview talking point**:
> "The instance can discover and read parameters under `/lab/*`. If another team creates `/prod/db/endpoint`, this instance cannot access it. Parameter paths become organizational boundaries."

---

## Anti-Patterns (What NOT to Do)

### ❌ Anti-Pattern 1: Wildcard Everything
```json
{
  "Effect": "Allow",
  "Action": "*",
  "Resource": "*"
}
```
**Why it's bad**: 
- Instance can do anything (not least-privilege)
- Security interviews will fail instantly
- No compliance value (CIS, SOC2, PCI-DSS require scoping)

---

### ❌ Anti-Pattern 2: Managed Policies Only
```hcl
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```
**Why it's okay (but not ideal)**:
- Managed policies are maintained by AWS
- But they grant broader permissions than needed
- For production, inline policies + managed policies in layers is better

---

### ❌ Anti-Pattern 3: Resource Wildcards Without Reason
```json
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": "*"
}
```
**Why it's bad**:
- Instance reads all secrets in the account
- Violates least-privilege
- If instance is compromised, attacker gets all secrets

---

### ❌ Anti-Pattern 4: Overly-Scoped Actions (too narrow)
```json
{
  "Effect": "Allow",
  "Action": "ssm:GetParameter",
  "Resource": "arn:aws:ssm:us-east-1:123456789012:parameter/lab/db/endpoint"
}
```
**Why it's suboptimal**:
- Only allows exact path (not paths under `/lab/`)
- Requires updating policy every time a new parameter is added
- Better: use `/lab/*` to allow path discovery

---

## Real-World Scenario: Privilege Escalation Attack

### Attack Flow
```
Attacker compromises EC2 instance
         ↓
Attacker tries: aws iam list-users  ← NOT in policy
         ↓
Error: Access Denied (policy boundary prevents escape)
         ↓
Attacker can only:
  - Read /lab/* parameters
  - Read lab1a/rds/mysql secret
  - Write to /aws/ec2/bonus-a-rds-app logs
  - Use Session Manager
         ↓
Lateral movement blocked! 🛡️
```

### If We Used iam:*
```
Attacker compromises EC2 instance
         ↓
Attacker tries: aws iam create-access-key --user-name admin
         ↓
Success! Creates backdoor credentials
         ↓
Account fully compromised 😱
```

---

## Terraform Implementation

### Full IAM Role + Policies (Copy-Paste Ready)

```hcl
# IAM Role
resource "aws_iam_role" "bonus_a_ec2_role" {
  name_prefix = "bonus-a-ec2-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Policy 1: SSM Session Manager
resource "aws_iam_role_policy" "bonus_a_ssm_session" {
  name_prefix = "bonus-a-ssm-session-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
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
    }]
  })
}

# Policy 2: CloudWatch Logs (scoped)
resource "aws_iam_role_policy" "bonus_a_cloudwatch_logs" {
  name_prefix = "bonus-a-cloudwatch-logs-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CloudWatchLogsWrite"
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/bonus-a-rds-app:*"
    }]
  })
}

# Policy 3: Secrets Manager (scoped)
resource "aws_iam_role_policy" "bonus_a_secrets_manager" {
  name_prefix = "bonus-a-secrets-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "GetLabSecret"
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:lab1a/rds/mysql*"
    }]
  })
}

# Policy 4: Parameter Store (scoped path)
resource "aws_iam_role_policy" "bonus_a_parameter_store" {
  name_prefix = "bonus-a-params-"
  role        = aws_iam_role.bonus_a_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "GetLabParameters"
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/lab/*"
    }]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "bonus_a_ec2_profile" {
  name_prefix = "bonus-a-ec2-profile-"
  role        = aws_iam_role.bonus_a_ec2_role.name
}

# Attach to EC2
resource "aws_instance" "bonus_a_ec2" {
  # ... other config ...
  iam_instance_profile = aws_iam_instance_profile.bonus_a_ec2_profile.name
}

# Data source for account ID
data "aws_caller_identity" "current" {}
```

---

## Policy Testing (IAM Policy Simulator)

### Test 1: Can instance read its own secret?
```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:role/bonus-a-ec2-xxxxx \
  --action-names secretsmanager:GetSecretValue \
  --resource-arns arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:lab1a/rds/mysql
# Expected: "EvaluationResult": "allowed"
```

### Test 2: Can instance read a different secret?
```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:role/bonus-a-ec2-xxxxx \
  --action-names secretsmanager:GetSecretValue \
  --resource-arns arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:prod/api/key
# Expected: "EvaluationResult": "implicitDeny"
```

### Test 3: Can instance escalate privileges?
```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:role/bonus-a-ec2-xxxxx \
  --action-names iam:CreateAccessKey \
  --resource-arns arn:aws:iam::ACCOUNT:user/admin
# Expected: "EvaluationResult": "implicitDeny"
```

---

## Interview Script

**Interviewer**: "Walk me through your IAM design for Bonus A."

**You**:
> "We use four inline policies scoped to specific resources:
> 
> **First**, Session Manager permissions for SSM communication—these are agent-level, so Resource '*' is acceptable.
> 
> **Second**, CloudWatch Logs scoped to a single log group ARN. This prevents the instance from writing to other teams' logs.
> 
> **Third**, Secrets Manager scoped to the Lab 1a RDS secret only. We use a wildcard suffix because Secrets Manager adds a random suffix to ARNs.
> 
> **Fourth**, Parameter Store scoped to the `/lab/*` path. This allows discovery and reading, but denies access to `/prod/*` or other paths.
> 
> If this instance is compromised, an attacker is trapped—they can't escalate to IAM, can't read other secrets, can't write to other log groups. That's defense-in-depth."

**Interviewer**: "What if we need the instance to read a parameter in `/prod/api/key`?"

**You**:
> "We'd add a new statement to the Parameter Store policy:
> ```json
> {
>   "Sid": "GetProdAPIKey",
>   "Effect": "Allow",
>   "Action": "ssm:GetParameter",
>   "Resource": "arn:aws:ssm:us-east-1:ACCOUNT:parameter/prod/api/key"
> }
> ```
> This is explicit and auditable—security teams can review exactly what this instance needs. We never use `Resource: '*'` with administrative actions."

---

## Real Company Examples

| Company | Approach | Takeaway |
|---------|----------|----------|
| **Google Cloud** | Workload Identity + minimal scopes | Service accounts never get blanket permissions |
| **Amazon** | Resource-based policies + principal policies | Double-check at both ends |
| **GitHub** | Fine-grained PATs with repo/action scopes | Tokens are narrower than ever |
| **HashiCorp Vault** | Least-privilege database credentials | Rotate frequently, scope by role |

---

## Cost of Getting This Right

| Item | Cost | ROI |
|------|------|-----|
| Design time | 1-2 hours | High: prevents breaches |
| Policy updates | 15 min per request | Medium: slower deployment |
| Audit overhead | 10% increase | High: compliance-required |
| Incident response (if breached) | $10K-1M+ | Critical: prevented by good IAM |

**Bottom line**: Least-privilege IAM costs 1-2 hours upfront; a breach costs millions.

---

## Checklist for Your Policies

- [ ] Policies are inline (not just managed)
- [ ] Resource ARNs are specific (no `*` for secrets/parameters)
- [ ] Actions are minimal (no `*` for privileged operations)
- [ ] Resource paths are organizational (e.g., `/lab/`, `/prod/`)
- [ ] Scoping is auditable (can explain each permission)
- [ ] Policies are tested (IAM Policy Simulator)
- [ ] Deny policies exist (if needed; e.g., deny cross-account access)

---

**Document Version**: 1.0  
**Last Updated**: January 21, 2026
