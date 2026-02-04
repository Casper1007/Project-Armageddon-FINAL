# Bonus-A: Quick Reference Card

## One-Page Cheat Sheet for Private EC2 + VPC Endpoints

---

## Architecture at a Glance

```
Private EC2 ──→ VPC Endpoints ──→ AWS Services (no internet)
     ↓                  ↓
  No public IP      7 endpoints
  Session Mgr        (SSM, EC2Messages, SSMMessages, 
  IAM-based          Logs, SecretsManager, KMS, S3)
  Scoped IAM         Private DNS enabled
  
DESIGN: Private-by-default, minimal NAT, least-privilege IAM
```

---

## Deployment (5 minutes)

```bash
# 1. Deploy infrastructure
cd terraform_restart_fixed
terraform apply -auto-approve

# 2. Capture outputs
INSTANCE_ID=$(terraform output -raw bonus_a_instance_id)
VPC_ID=$(terraform output -raw bonus_a_vpc_id)
REGION="us-east-1"

echo "Instance: $INSTANCE_ID"
echo "VPC: $VPC_ID"
```

---

## Verification: The 5 Tests

### Test 1: EC2 is Private (No Public IP)
```bash
bash verify_bonus_a_1_private_ip.sh $INSTANCE_ID
# Expected: PublicIpAddress = null ✓
```

### Test 2: VPC Endpoints Exist
```bash
bash verify_bonus_a_2_vpc_endpoints.sh $VPC_ID
# Expected: 7 endpoints (ssm, ec2messages, ssmmessages, logs, 
#           secretsmanager, kms, s3) ✓
```

### Test 3: Session Manager Works
```bash
bash verify_bonus_a_3_session_manager.sh $INSTANCE_ID
# Expected: Instance appears in managed instances ✓
# Wait 2-3 min for SSM agent to register
```

### Test 4: Config Store Access (From Inside EC2)
```bash
# FROM YOUR WORKSTATION:
aws ssm start-session --target $INSTANCE_ID --region $REGION

# INSIDE THE SESSION:
bash verify_bonus_a_4_config_stores.sh

# Expected: Can read SSM param + Secrets Manager secret ✓
```

### Test 5: CloudWatch Logs Works
```bash
bash verify_bonus_a_5_cloudwatch_logs.sh /aws/ec2/bonus-a-rds-app
# Expected: Can write test event to logs ✓
```

### Run All Tests
```bash
bash run_bonus_a_verification.sh $INSTANCE_ID $VPC_ID $REGION
```

---

## Session Manager Access (No SSH Required)

### Option 1: Interactive Shell
```bash
# Start session
aws ssm start-session --target $INSTANCE_ID --region us-east-1

# Get shell inside
sh

# Run commands
whoami
cat /etc/os-release
curl -s https://logs.us-east-1.amazonaws.com
```

### Option 2: Run Command (Non-Interactive)
```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cat /etc/os-release"]' \
  --targets "Key=instanceids,Values=$INSTANCE_ID" \
  --region us-east-1
```

### Option 3: VS Code (AWS Toolkit Extension)
- Install: **AWS Toolkit**
- Configure: SSM Session Manager
- Opens terminal directly in editor

---

## VPC Endpoints: What They Do

| Endpoint | Service | Port | Purpose |
|----------|---------|------|---------|
| **ssm** | Systems Manager | 443 | Agent registration |
| **ec2messages** | EC2 Messages | 443 | Instance communication |
| **ssmmessages** | SSM Messages | 443 | Session shell I/O |
| **logs** | CloudWatch Logs | 443 | App logging |
| **secretsmanager** | Secrets Manager | 443 | DB credentials |
| **kms** | Key Management | 443 | Encryption keys |
| **s3** | S3 (Gateway) | Layer 3 | Packages, data |

**KEY INSIGHT:** All Interface Endpoints use HTTPS (443) from private subnet

---

## Least-Privilege IAM Policy

```json
{
  "Statement": [
    {
      "Sid": "SSMSessionManager",
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
      "Action": "ssm:GetParameter(s)",
      "Resource": "arn:aws:ssm:us-east-1:ACCOUNT:parameter/lab/*"
      ↑ SCOPED to /lab/* path only
    }
  ]
}
```

**Why it matters:** If EC2 credentials leak, attacker can only:
- Read `/lab/*` parameters (not all params)
- Read `lab1a/rds/mysql` secret (not all secrets)
- Cannot delete DB, launch EC2, etc.

---

## Security Groups in Action

### Endpoints Security Group
```
Inbound:  HTTPS from private subnets (10.0.101.0/24, 10.0.102.0/24)
Outbound: Allow all (endpoints don't initiate)
```

### Bonus-A EC2 Security Group
```
Inbound:  NONE (all access via Session Manager)
Outbound: 
  - HTTPS 443 → Endpoint SG (for AWS APIs)
  - MySQL 3306 → RDS (Lab 1a connectivity)
```

### RDS Security Group (Lab 1a)
```
Inbound additions for Bonus-A:
  - MySQL 3306 from bonus_a_ec2_sg (new rule added)
```

---

## Troubleshooting Flowchart

```
Session Manager not working?
│
├─ Instance registered with SSM?
│  └─ No → Wait 2-3 min, check IAM role
│
├─ VPC endpoints exist?
│  └─ No → terraform apply (check for errors)
│
├─ Security group allows 443 egress?
│  └─ No → Verify bonus_a_ec2_sg rules
│
└─ Check logs:
   aws ec2 describe-instances --instance-ids $INSTANCE_ID
   aws ssm describe-instance-information

Secrets Manager not accessible from EC2?
│
└─ Inside session, run:
   aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql --debug
   
   Look for errors about endpoint resolution or access denied
```

---

## Real-World Companies Using This Pattern

| Company | Why | Notes |
|---------|-----|-------|
| **Netflix** | Private-first security | Zero-trust architecture |
| **Stripe** | PCI-DSS compliance | No internet exposure for APIs |
| **Airbnb** | Microservices isolation | VPC per team |
| **Pinterest** | Security at scale | Reduced NAT complexity |
| **AWS** | Best practice | Used in their own environments |

---

## Grading Checklist (100 points)

- [ ] Test 1 PASS: EC2 private (15 pts)
- [ ] Test 2 PASS: 7 VPC endpoints exist (20 pts)
- [ ] Test 3 PASS: Session Manager registered (20 pts)
- [ ] Test 4 PASS: Config stores accessible (20 pts)
- [ ] Test 5 PASS: CloudWatch Logs working (15 pts)
- [ ] Session Manager shell access confirmed (bonus +5 pts)
- [ ] NAT route commented with explanation (bonus +5 pts)
- [ ] Written report of findings (bonus +10 pts)

---

## Key Files

```
bonus_a.tf                           ← Terraform (VPC endpoints + EC2 + IAM)
verify_bonus_a_1_private_ip.sh       ← Test 1 script
verify_bonus_a_2_vpc_endpoints.sh    ← Test 2 script
verify_bonus_a_3_session_manager.sh  ← Test 3 script
verify_bonus_a_4_config_stores.sh    ← Test 4 script (run from EC2)
verify_bonus_a_5_cloudwatch_logs.sh  ← Test 5 script
run_bonus_a_verification.sh          ← Run all tests (1-3, 5 auto)
BONUS_A_SETUP_GUIDE.md               ← Full documentation
BONUS_A_QUICK_REFERENCE.md           ← This file
```

---

## Interview Soundbites

**"Tell us about your private compute architecture..."**

→ "We implemented a private EC2 with VPC endpoints for all AWS services—no internet exposure. Used Session Manager for shell access instead of SSH. Implemented least-privilege IAM scoped to specific resources. This matches patterns used by Netflix and Stripe for security and compliance."

**"How did you handle access without a bastion host?"**

→ "Session Manager provides secure shell access via AWS IAM, with full CloudTrail audit trail and optional MFA. No SSH keys to manage, no bastion EC2 to maintain."

**"What about package installation in private subnets?"**

→ "We used S3 Gateway Endpoint for yum/apt repositories. For production, golden AMIs are pre-baked with dependencies, avoiding internet dependencies entirely."

---

## Quick Commands

```bash
# Deploy
terraform apply -auto-approve

# Get instance details
aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[].Instances[]"

# Check SSM agent status
aws ssm describe-instance-information --query "InstanceInformationList[].{Id:InstanceId,Status:PingStatus}"

# List VPC endpoints
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[].ServiceName"

# Open session
aws ssm start-session --target $INSTANCE_ID

# Destroy (cleanup)
terraform destroy -auto-approve
```

---

## Additional Resources

- **AWS VPC Endpoints:** https://docs.aws.amazon.com/vpc/latest/privatelink/
- **Session Manager:** https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
- **Least-Privilege:** https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#grant-least-privilege
- **CIS AWS Foundations:** https://www.cisecurity.org/cis-benchmarks#aws
- **OWASP Cloud Top 10:** https://owasp.org/www-project-cloud-top-10/

---

**Status:** ✅ Ready for deployment
**Estimated Time:** 15 minutes (5 min deploy + 3 min SSM register + 7 min testing)
**Difficulty:** Intermediate (assumes AWS CLI familiarity)
