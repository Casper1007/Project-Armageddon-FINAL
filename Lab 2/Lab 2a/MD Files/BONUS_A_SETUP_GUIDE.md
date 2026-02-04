# Bonus-A: Private Compute with VPC Endpoints & SSM Session Manager

## Overview

**Bonus-A** is a production-hardened AWS architecture lab that demonstrates:

- **Private compute** (no public IP, no SSH)
- **VPC Interface Endpoints** for AWS service access (SSM, CloudWatch, Secrets Manager, KMS)
- **S3 Gateway Endpoint** for package repositories
- **Least-privilege IAM** with scoped permissions
- **Session Manager** for secure shell access (no bastion host, no SSH key)

This matches **real-world practices** in regulated organizations (finance, healthcare, government) and advanced cloud shops that prioritize security and compliance.

---

## Architecture Design

```
┌─────────────────────────────────────────┐
│         VPC (10.0.0.0/16)               │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │  Private Subnet                  │   │
│  │                                  │   │
│  │  ┌──────────────────────────┐    │   │
│  │  │   Private EC2            │    │   │
│  │  │   (no public IP)         │    │   │
│  │  │   IAM role scoped        │    │   │
│  │  │   Access via Session Mgr │    │   │
│  │  └──────────────────────────┘    │   │
│  │           ↓ HTTPS/443             │   │
│  └──────────────────────────────────┘   │
│           ↓ Route via Endpoints         │
├─────────────────────────────────────────┤
│  VPC Interface Endpoints                │
│  ├─ SSM (Systems Manager)               │
│  ├─ EC2Messages                         │
│  ├─ SSMMessages                         │
│  ├─ CloudWatch Logs                     │
│  ├─ Secrets Manager                     │
│  ├─ KMS                                 │
│  └─ S3 Gateway                          │
├─────────────────────────────────────────┤
│  AWS API Layer (no internet required)   │
│  ├─ SSM Session Manager ← shell access  │
│  ├─ CloudWatch Logs ← app logging       │
│  ├─ Secrets Manager ← DB credentials    │
│  └─ SSM Parameter Store ← config        │
└─────────────────────────────────────────┘
```

### Key Differences from Lab 1a

| Aspect | Lab 1a | Bonus-A |
|--------|--------|---------|
| **Public IP** | Yes | No |
| **Access Method** | SSH (port 22) | Session Manager (HTTPS) |
| **Internet Egress** | Via NAT Gateway | Via VPC Endpoints only |
| **IAM Scope** | Broad | Scoped to specific resources |
| **Secrets Access** | Key-based | IAM-based + Secrets Manager endpoint |
| **Compliance** | Standard | Production-hardened |

---

## Why VPC Endpoints?

### Interface Endpoints (HTTPS on 443)
- Provide private connectivity to AWS services
- Eliminate need for NAT Gateway → save cost
- Eliminate internet exposure for APIs
- Support DNS resolution within VPC

### Gateway Endpoints (S3)
- Layer 3 routing (no ENI)
- Free
- Used for package repos (yum, apt) and data transfer

### Security Benefit
```
TRADITIONAL (NAT-based)
EC2 (private) → NAT Gateway → Internet Gateway → AWS API
  ↑ Multiple hops, costs, potential exposure

BONUS-A (Endpoint-based)
EC2 (private) → VPC Endpoint (private ENI) → AWS API
  ↑ Direct private path, no internet
```

---

## Deployment Steps

### 1. Prerequisites
```bash
cd /path/to/terraform_restart_fixed

# Ensure existing Lab 1a infrastructure is in place
terraform state list | grep aws_vpc
terraform state list | grep aws_instance
```

### 2. Deploy Bonus-A Infrastructure
```bash
# Plan (review resources to be created)
terraform plan -target=aws_vpc_endpoint.ssm -target=aws_vpc_endpoint.ec2messages \
  -target=aws_vpc_endpoint.ssmmessages -target=aws_vpc_endpoint.logs \
  -target=aws_vpc_endpoint.secretsmanager -target=aws_vpc_endpoint.kms \
  -target=aws_vpc_endpoint.s3 -target=aws_instance.bonus_a_ec2 \
  -target=aws_iam_role.bonus_a_ec2_role

# Apply
terraform apply -auto-approve

# Capture outputs
INSTANCE_ID=$(terraform output -raw bonus_a_instance_id)
VPC_ID=$(terraform output -raw bonus_a_vpc_endpoints | grep -o '"' | wc -l)
```

### 3. Wait for SSM Agent Registration
```bash
# Takes 2-3 minutes for agent to register
watch -n 5 'aws ssm describe-instance-information \
  --query "InstanceInformationList[?InstanceId=='\''$INSTANCE_ID'\''].InstanceId" \
  --region us-east-1'

# Exit when instance ID appears (Ctrl+C)
```

---

## Student Verification: The 5 Tests

### Test 1: Prove EC2 is Private
```bash
bash verify_bonus_a_1_private_ip.sh <INSTANCE_ID> [REGION]

# Expected Output:
# Result: PublicIpAddress = null
# ✓ PASS: Instance is private (no public IP assigned)
```

### Test 2: Prove VPC Endpoints Exist
```bash
bash verify_bonus_a_2_vpc_endpoints.sh <VPC_ID> [REGION]

# Expected Output:
# ✓ ssm endpoint found
# ✓ ec2messages endpoint found
# ✓ ssmmessages endpoint found
# ✓ logs endpoint found
# ✓ secretsmanager endpoint found
# ✓ kms endpoint found
# ✓ s3 endpoint found
# ✓ PASS: All required VPC endpoints exist
```

### Test 3: Prove Session Manager Works
```bash
bash verify_bonus_a_3_session_manager.sh <INSTANCE_ID> [REGION]

# Expected Output:
# Managed instances in region:
# <INSTANCE_ID>
# ✓ PASS: Instance is registered with SSM
# You can now access the instance with:
#   aws ssm start-session --target <INSTANCE_ID> --region us-east-1
```

### Test 4: Prove Config Store Access (From Inside EC2)
```bash
# From your workstation:
aws ssm start-session --target <INSTANCE_ID> --region us-east-1

# Inside the session (on the EC2 instance):
bash verify_bonus_a_4_config_stores.sh [PARAM_NAME] [SECRET_ID] [REGION]

# Expected Output:
# Test 1: Retrieving parameter from SSM Parameter Store...
#   ✓ Parameter retrieved: <endpoint-value>
# Test 2: Retrieving secret from Secrets Manager...
#   ✓ Secret retrieved (contains valid credentials)
# ✓ PASS: EC2 can access both Parameter Store and Secrets Manager
```

### Test 5: Prove CloudWatch Logs Endpoint Works
```bash
bash verify_bonus_a_5_cloudwatch_logs.sh /aws/ec2/bonus-a-rds-app [REGION]

# Expected Output:
# Test 1: Checking if log group exists...
#   ✓ Log group exists: /aws/ec2/bonus-a-rds-app
# Test 2: Checking log streams...
#   ℹ No log streams yet (normal if app hasn't started logging)
# Test 3: Testing CloudWatch Logs endpoint write capability...
#   ✓ Successfully wrote test event to CloudWatch Logs
# ✓ PASS: CloudWatch Logs endpoint is functional
```

---

## Using Session Manager (Shell Access Without SSH)

### Option 1: CLI Access
```bash
# Start interactive session
aws ssm start-session --target <INSTANCE_ID> --region us-east-1

# Inside session, get shell
sh

# Now you can run commands
whoami
aws ssm get-parameter --name /lab/db/endpoint
aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql
```

### Option 2: VS Code Session Manager Plugin
Install extension: **AWS Toolkit** → Configure → SSM Session Manager
Opens terminal directly in VS Code.

### Option 3: Script Execution (Non-Interactive)
```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cat /etc/os-release"]' \
  --targets "Key=instanceids,Values=$INSTANCE_ID" \
  --region us-east-1
```

---

## Least-Privilege IAM Explained

### EC2 Role Policy: Scoped Permissions

```json
{
  "Statement": [
    {
      "Sid": "SSMSessionManagerCore",
      "Effect": "Allow",
      "Action": [
        "ssmmessages:CreateControlChannel",
        "ec2messages:GetMessages"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsWrite",
      "Effect": "Allow",
      "Action": "logs:PutLogEvents",
      "Resource": "arn:aws:logs:us-east-1:ACCOUNT:log-group:/aws/ec2/bonus-a-rds-app:*"
      ↑ SCOPED to specific log group
    },
    {
      "Sid": "GetLabSecret",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:lab1a/rds/mysql*"
      ↑ SCOPED to lab secret only
    },
    {
      "Sid": "GetLabParameters",
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "arn:aws:ssm:us-east-1:ACCOUNT:parameter/lab/*"
      ↑ SCOPED to /lab/* path only
    }
  ]
}
```

**Benefits:**
- If EC2 credentials leaked, attacker can only access `/lab/*` params and `lab1a/rds/mysql` secret
- No `s3:GetObject` on all buckets
- No `rds:DeleteDBInstance` or other destructive actions
- Follows **principle of least privilege** (PoLP)

---

## Real-Company Credibility

### Regulated Organizations Use This Pattern

| Industry | Why | Example |
|----------|-----|---------|
| **Finance** | PCI-DSS, SOC2 compliance | No internet exposure for APIs |
| **Healthcare** | HIPAA requirements | Isolated private network for PHI |
| **Government** | FedRAMP, NIST 800-53 | Strict network segmentation |
| **Enterprise** | Risk management | Reduced blast radius from compromise |

### Mature Cloud Practices
- **Netflix, Airbnb, Pinterest, Stripe**: Private compute default
- **AWS re:Invent talks**: "Private-first architecture"
- **CIS AWS Foundations Benchmark**: Recommends VPC endpoints for APIs
- **OWASP Cloud Top 10**: Network exposure as critical risk

### Why Session Manager > SSH?

| Aspect | SSH | Session Manager |
|--------|-----|-----------------|
| **Secret Storage** | SSH keys on workstation | IAM credentials (temporary) |
| **Audit Trail** | Limited to syslog | CloudTrail + CloudWatch Logs |
| **Multi-factor** | Optional | Built-in with IAM MFA |
| **No Bastion** | Need jump host | Direct private connection |
| **Cost** | Must maintain instances | Built into AWS (free) |

---

## Optional: NAT Gateway (Commented in Terraform)

If your org needs general internet access for package installation:

```hcl
# Uncomment in bonus_a.tf:
resource "aws_route" "bonus_a_nat_route" {
  route_table_id            = aws_route_table.bonus_a_private_rt.id
  destination_cidr_block    = "0.0.0.0/0"
  nat_gateway_id            = aws_nat_gateway.chrisbarm_nat01.id
}
```

**Tradeoff**: NAT enables yum/apt but adds cost and complexity. Better practice: **use golden AMIs** (pre-baked with dependencies).

---

## Troubleshooting

### Session Manager Not Working

```bash
# 1. Check instance is registered
aws ssm describe-instance-information --query "InstanceInformationList[].InstanceId"

# 2. Check IAM role has SSM permissions
aws iam get-role-policy --role-name bonus-a-ec2-* --policy-name bonus-a-ssm-session-*

# 3. Check VPC endpoints are available
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID"

# 4. Check security group allows 443 outbound
aws ec2 describe-security-groups --group-ids $SG_ID
```

### Secrets Manager Not Accessible from EC2

```bash
# Inside session:
aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql --debug

# Look for endpoint resolution errors
# If error: "AWS service may not be available in this region"
# → Verify secretsmanager endpoint exists in this VPC
```

### CloudWatch Logs Not Receiving Events

```bash
# Check log group exists
aws logs describe-log-groups --log-group-name-prefix /aws/ec2

# Check metric filters
aws logs describe-metric-filters --log-group-name /aws/ec2/bonus-a-rds-app

# From EC2, check network connectivity to endpoint
curl -v https://logs.us-east-1.amazonaws.com
```

---

## Grading Rubric (Bonus-A Lab)

| Test | Points | Evidence |
|------|--------|----------|
| **Test 1: EC2 Private** | 15 | CLI output shows `PublicIpAddress = null` |
| **Test 2: VPC Endpoints** | 20 | All 7 endpoints (ssm, ec2messages, ssmmessages, logs, secretsmanager, kms, s3) exist |
| **Test 3: Session Manager** | 20 | Instance appears in `describe-instance-information` output |
| **Test 4: Config Stores** | 20 | Successfully read both SSM param and Secrets Manager secret from EC2 |
| **Test 5: CloudWatch Logs** | 15 | Log group exists, can write test event via endpoint |
| **Bonus: NAT Optional** | +5 | Commented NAT route with explanation |
| **Bonus: Terraform Quality** | +5 | Well-documented, follows best practices |
| **Bonus: Report** | +10 | Written explanation of architecture and security benefits |
| **TOTAL** | **100** | |

---

## Deliverables Checklist

- [ ] `bonus_a.tf` deployed with all 7 endpoints + private EC2
- [ ] `verify_bonus_a_1_private_ip.sh` passes
- [ ] `verify_bonus_a_2_vpc_endpoints.sh` passes
- [ ] `verify_bonus_a_3_session_manager.sh` passes
- [ ] `verify_bonus_a_4_config_stores.sh` passes (from EC2)
- [ ] `verify_bonus_a_5_cloudwatch_logs.sh` passes
- [ ] Session Manager successfully used to access EC2 shell
- [ ] Written report explaining architecture and security benefits

---

## Key Takeaways

**For Career/Interview:**
1. "We implemented private compute with VPC endpoints—no internet exposure"
2. "Session Manager eliminated SSH management—no bastion host needed"
3. "Least-privilege IAM scoped to specific resources—limited blast radius"
4. "This matches patterns used by Netflix, Stripe, AWS best practices"

**Technical Wins:**
- ✅ Eliminated NAT Gateway complexity
- ✅ Improved security posture (no public IP, no SSH)
- ✅ Demonstrated VPC endpoint mastery
- ✅ Implemented least-privilege IAM (real-world pattern)
- ✅ Proved AWS service access works without internet

---

## Next Steps

1. Run `terraform apply` to deploy Bonus-A infrastructure
2. Wait 2-3 minutes for SSM agent registration
3. Run all 5 verification scripts
4. Use Session Manager to access EC2 and confirm app works
5. Write summary report of findings

**Questions?** Refer to AWS documentation:
- VPC Endpoints: https://docs.aws.amazon.com/vpc/latest/privatelink/
- Session Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
- Least-privilege: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#grant-least-privilege
