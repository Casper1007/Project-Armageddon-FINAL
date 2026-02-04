# Bonus-A Lab Index & Navigation Guide

## 🎯 What is Bonus-A?

**Bonus-A** is a production-hardened AWS architecture lab that teaches:
- Private compute (EC2 with no public IP)
- VPC Interface Endpoints for AWS service access
- Session Manager for shell access (no SSH)
- Least-privilege IAM policies
- Real-world security practices from Netflix, Stripe, AWS

**Difficulty:** Intermediate | **Time:** 15-20 minutes | **Concepts:** Security, Networking, IAM

---

## 📋 Quick Navigation

### For Beginners: Start Here
1. Read: [BONUS_A_SETUP_GUIDE.md](BONUS_A_SETUP_GUIDE.md) - Full walkthrough with explanations
2. Review: [BONUS_A_QUICK_REFERENCE.md](BONUS_A_QUICK_REFERENCE.md) - One-page cheat sheet
3. Deploy: Follow deployment steps (15 min)
4. Verify: Run all 5 tests (5 min)

### For Experienced Users: Quick Start
1. Review: [BONUS_A_IMPLEMENTATION_SUMMARY.md](BONUS_A_IMPLEMENTATION_SUMMARY.md) - Architecture overview
2. Deploy: `terraform apply -auto-approve`
3. Test: `bash run_bonus_a_verification.sh <INSTANCE_ID> <VPC_ID>`
4. Access: `aws ssm start-session --target <INSTANCE_ID>`

### For Reviewers/Graders
1. Check: [Grading Rubric](#grading-rubric-100-points) below
2. Run: [Verification Scripts](#verification-scripts) in order
3. Score: 100 points available

---

## 📁 File Structure

### Terraform Infrastructure
```
bonus_a.tf (450+ lines)
├─ Locals & naming conventions
├─ Security Groups (3 total)
│  ├─ Endpoint SG
│  ├─ Bonus-A EC2 SG
│  └─ RDS ingress rule (for Lab 1a)
├─ VPC Interface Endpoints (6 resources)
│  ├─ SSM, EC2Messages, SSMMessages
│  ├─ CloudWatch Logs, Secrets Manager, KMS
│  └─ S3 Gateway Endpoint
├─ Private EC2 Instance
├─ CloudWatch Log Group
├─ Route Table Configuration
├─ IAM Role & Policies (4 policies)
│  ├─ SSM Session Manager
│  ├─ CloudWatch Logs (scoped)
│  ├─ Secrets Manager (scoped)
│  └─ Parameter Store (scoped)
└─ Outputs (7 values)
```

### Verification Scripts
```
verify_bonus_a_1_private_ip.sh       [Test: EC2 has no public IP]
verify_bonus_a_2_vpc_endpoints.sh    [Test: 7 endpoints exist]
verify_bonus_a_3_session_manager.sh  [Test: SSM agent registered]
verify_bonus_a_4_config_stores.sh    [Test: Config access from EC2]
verify_bonus_a_5_cloudwatch_logs.sh  [Test: Logs endpoint works]
run_bonus_a_verification.sh          [Automation: Run tests 1-3, 5]
```

### Documentation
```
BONUS_A_SETUP_GUIDE.md               [Complete walkthrough & explanations]
BONUS_A_QUICK_REFERENCE.md          [One-page cheat sheet]
BONUS_A_IMPLEMENTATION_SUMMARY.md   [Architecture overview & checklist]
BONUS_A_INDEX.md                     [This file - navigation guide]
```

---

## 🚀 Deployment Workflow

### 1. Review Architecture (5 min)
```bash
# Option A: Visual learners
cat BONUS_A_SETUP_GUIDE.md | head -100

# Option B: Summary
cat BONUS_A_IMPLEMENTATION_SUMMARY.md
```

### 2. Deploy Infrastructure (5 min)
```bash
cd terraform_restart_fixed

# Plan
terraform plan -out=bonus_a.plan

# Apply
terraform apply bonus_a.plan
# OR: terraform apply -auto-approve

# Capture outputs
INSTANCE_ID=$(terraform output -raw bonus_a_instance_id)
VPC_ID=$(terraform output -raw bonus_a_vpc_endpoints | grep -o vpc | head -1)
REGION="us-east-1"
```

### 3. Wait for SSM Agent (2-3 min)
```bash
# Agent registers automatically, but takes time
watch -n 5 'aws ssm describe-instance-information --query "InstanceInformationList[].InstanceId" --region us-east-1'

# Exit when your instance ID appears
```

### 4. Run Verification Tests (5 min)
```bash
# Option A: All at once
bash run_bonus_a_verification.sh $INSTANCE_ID $VPC_ID $REGION

# Option B: Individual tests
bash verify_bonus_a_1_private_ip.sh $INSTANCE_ID
bash verify_bonus_a_2_vpc_endpoints.sh $VPC_ID
bash verify_bonus_a_3_session_manager.sh $INSTANCE_ID
bash verify_bonus_a_5_cloudwatch_logs.sh "/aws/ec2/bonus-a-rds-app"

# Test 4 requires manual session (see below)
```

### 5. Manual Test 4: Config Store Access (3 min)
```bash
# Open Session Manager session
aws ssm start-session --target $INSTANCE_ID --region us-east-1

# Inside the session, run:
sh
bash verify_bonus_a_4_config_stores.sh /lab/db/endpoint lab1a/rds/mysql us-east-1

# Expected: Can read both parameter and secret
```

### 6. Explore Session Manager (5 min)
```bash
# Inside the session:
whoami
cat /etc/os-release
aws ssm get-parameter --name /lab/db/endpoint
aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql
```

---

## ✅ Verification Scripts

### Test 1: EC2 is Private
**Purpose:** Prove EC2 has no public IP

```bash
bash verify_bonus_a_1_private_ip.sh <INSTANCE_ID>

# Expected output:
# Result: PublicIpAddress = null
# ✓ PASS: Instance is private (no public IP assigned)
```

**Points:** 15

---

### Test 2: VPC Endpoints Exist
**Purpose:** Prove all 7 endpoints are deployed

```bash
bash verify_bonus_a_2_vpc_endpoints.sh <VPC_ID>

# Expected output:
# ✓ ssm endpoint found
# ✓ ec2messages endpoint found
# ✓ ssmmessages endpoint found
# ✓ logs endpoint found
# ✓ secretsmanager endpoint found
# ✓ kms endpoint found
# ✓ s3 endpoint found
# ✓ PASS: All required VPC endpoints exist
```

**Points:** 20

---

### Test 3: Session Manager Ready
**Purpose:** Prove SSM agent registered for shell access

```bash
bash verify_bonus_a_3_session_manager.sh <INSTANCE_ID>

# Expected output:
# Managed instances in region:
# <YOUR_INSTANCE_ID>
# ✓ PASS: Instance <INSTANCE_ID> is registered with SSM
# You can now access the instance with:
#   aws ssm start-session --target <INSTANCE_ID> --region us-east-1
```

**Points:** 20

---

### Test 4: Config Store Access (Manual from EC2)
**Purpose:** Prove EC2 can read secrets and parameters

```bash
# From your workstation:
aws ssm start-session --target <INSTANCE_ID>

# Inside the session:
bash verify_bonus_a_4_config_stores.sh /lab/db/endpoint lab1a/rds/mysql us-east-1

# Expected output:
# Test 1: Retrieving parameter from SSM Parameter Store...
#   ✓ Parameter retrieved: <value>
# Test 2: Retrieving secret from Secrets Manager...
#   ✓ Secret retrieved (contains valid credentials)
# ✓ PASS: EC2 can access both Parameter Store and Secrets Manager
```

**Points:** 20

---

### Test 5: CloudWatch Logs Endpoint
**Purpose:** Prove logs can be written via VPC endpoint

```bash
bash verify_bonus_a_5_cloudwatch_logs.sh "/aws/ec2/bonus-a-rds-app"

# Expected output:
# Test 1: Checking if log group exists...
#   ✓ Log group exists: /aws/ec2/bonus-a-rds-app
# Test 2: Checking log streams...
#   ℹ No log streams yet (normal if app hasn't started logging)
# Test 3: Testing CloudWatch Logs endpoint write capability...
#   ✓ Successfully wrote test event to CloudWatch Logs
# ✓ PASS: CloudWatch Logs endpoint is functional
```

**Points:** 15

---

## 🎓 Grading Rubric (100 Points)

| Test | Points | Pass Criteria |
|------|--------|---------------|
| **Test 1: EC2 Private** | 15 | `PublicIpAddress = null` |
| **Test 2: VPC Endpoints** | 20 | All 7 endpoints exist (ssm, ec2messages, ssmmessages, logs, secretsmanager, kms, s3) |
| **Test 3: Session Manager** | 20 | Instance registered in SSM managed instances |
| **Test 4: Config Stores** | 20 | Can read SSM parameter AND Secrets Manager secret from EC2 |
| **Test 5: CloudWatch Logs** | 15 | Can write test event to log group via endpoint |
| **Bonus: NAT Optional** | +5 | Commented route explanation (optional, for student choice) |
| **Bonus: Terraform Quality** | +5 | Well-commented, follows best practices |
| **Bonus: Written Report** | +10 | Document findings + explain security benefits |
| **TOTAL** | **100** | |

---

## 🔒 Security Model

### What This Architecture Provides

✅ **Private Compute**
- EC2 has no public IP
- Cannot be reached from internet directly
- Only accessible via Session Manager

✅ **Private AWS API Access**
- All API calls go through VPC endpoints (private)
- No internet exposure for credentials
- No NAT Gateway dependency

✅ **Least-Privilege Access**
- EC2 role scoped to specific resources
- Can only read specific secrets and parameters
- Limited blast radius if credentials leak

✅ **Audit Trail**
- CloudTrail logs all API calls
- Session Manager sessions logged
- Full accountability trail

### What This Architecture Protects Against

❌ **Internet Exposure Risk** (eliminated)
- No public IP = can't SSH from internet
- No internet gateway for instance = can't reach internet

❌ **Credential Compromise** (reduced)
- IAM role scoped to specific resources
- Stolen credentials can only access `/lab/*` params
- Cannot delete databases, terminate EC2, etc.

❌ **Bastion Host Complexity** (eliminated)
- No need for jump host
- Session Manager is built-in AWS service
- No additional EC2 to maintain/patch

---

## 💼 Real-World Context

### Who Uses This Pattern?

**Tech Leaders:**
- Netflix: Private-first microservices platform
- Stripe: PCI-DSS compliant payment processing
- Airbnb: Massive infrastructure at scale
- Pinterest, Uber: Security-first architecture

**Regulated Industries:**
- Finance (JPMorgan, Goldman, Robinhood)
- Healthcare (Optum, Moderna, health tech)
- Government (Federal agencies, defense)

**Why:**
- Security compliance (SOC2, HIPAA, FedRAMP, PCI-DSS)
- Regulatory requirements (no internet exposure)
- Risk management (minimize blast radius)
- Best practices (CIS Benchmarks, AWS Well-Architected)

---

## 🗣️ Interview Talking Points

**"Tell us about your private compute architecture..."**
> "I implemented a private EC2 with VPC endpoints for AWS services—no internet exposure. Used Session Manager instead of SSH for shell access. Implemented least-privilege IAM scoped to specific resources. This matches production patterns from Netflix and Stripe."

**"How did you secure API access?"**
> "Instead of NAT Gateway, I used VPC Interface Endpoints for all AWS services. This provides direct, private paths for API calls. More secure (no internet), cheaper (no NAT cost), and lower latency than NAT."

**"Explain your IAM strategy..."**
> "IAM role is scoped to specific resources: can only read one secret, one parameter path, write to one log group. If credentials leak, damage is limited. This is principle of least-privilege—standard in security interviews."

**"How does Session Manager work without SSH?"**
> "Session Manager provides shell access through IAM, with full CloudTrail audit trail. No keys to rotate, built-in MFA, automatic session logging. Every command runs under the IAM role."

---

## 🚀 Getting Started

### Minimum 15-Minute Path
```bash
# 1. Deploy (5 min)
terraform apply -auto-approve
INSTANCE_ID=$(terraform output -raw bonus_a_instance_id)
VPC_ID=$(terraform output -raw bonus_a_vpc_id)

# 2. Wait for SSM (3 min)
sleep 180 && aws ssm describe-instance-information

# 3. Test (5 min)
bash run_bonus_a_verification.sh $INSTANCE_ID $VPC_ID

# 4. Access (2 min)
aws ssm start-session --target $INSTANCE_ID
```

### Deeper Learning Path
1. Read [BONUS_A_SETUP_GUIDE.md](BONUS_A_SETUP_GUIDE.md) (20 min)
2. Review terraform code in [bonus_a.tf](bonus_a.tf) (10 min)
3. Deploy and test (15 min)
4. Write summary report (10 min)
5. Practice interview answers (5 min)

---

## 📚 Resources

**AWS Documentation:**
- [VPC Endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks#aws)

**Books & References:**
- AWS Well-Architected Framework (free)
- OWASP Cloud Top 10
- "Terraform: Up & Running" (Yevgeniy Brikman)

---

## ❓ Troubleshooting

### Instance Not Showing Up in SSM?
- Wait 2-3 minutes (agent registration)
- Check IAM role has `ssm:*` permissions
- Verify VPC endpoints created successfully
- Check security group allows 443 outbound

### Cannot Access Config Stores from EC2?
- Verify Secrets Manager endpoint created
- Verify Parameter Store endpoint created
- Check IAM policy includes correct ARNs
- From EC2 session: `curl https://secretsmanager.us-east-1.amazonaws.com`

### Terraform Apply Fails?
- Check VPC exists and has correct ID
- Verify RDS instance (chrisbarm-rds01) exists
- Ensure subnets exist: `aws ec2 describe-subnets`
- Check account limits not exceeded

---

## ✨ Next Steps

- [ ] Deploy infrastructure
- [ ] Run all 5 tests
- [ ] Document findings
- [ ] Practice interview answers
- [ ] Destroy resources (cleanup)

```bash
# Cleanup when done:
terraform destroy -auto-approve
```

---

## 📞 Questions?

Refer to:
1. **Quick answers:** [BONUS_A_QUICK_REFERENCE.md](BONUS_A_QUICK_REFERENCE.md)
2. **Deep dive:** [BONUS_A_SETUP_GUIDE.md](BONUS_A_SETUP_GUIDE.md)
3. **Overview:** [BONUS_A_IMPLEMENTATION_SUMMARY.md](BONUS_A_IMPLEMENTATION_SUMMARY.md)
4. **Code:** [bonus_a.tf](bonus_a.tf) (well-commented)

---

**Status:** ✅ Ready for deployment
**Difficulty:** Intermediate
**Time:** 15-20 minutes
**Career Value:** ⭐⭐⭐⭐⭐ (interview-credible architecture)
