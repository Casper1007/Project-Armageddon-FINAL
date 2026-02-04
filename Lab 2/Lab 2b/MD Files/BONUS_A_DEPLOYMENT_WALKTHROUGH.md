# Bonus A: End-to-End Deployment & Verification Walkthrough

## Overview

This document guides you step-by-step from infrastructure deployment through comprehensive verification, matching the design goals and verification requirements.

---

## Phase 1: Pre-Deployment Validation (10 minutes)

### Step 1.1: Verify AWS Credentials
```bash
# Confirm you're in the right AWS account
aws sts get-caller-identity
# Expected output:
# {
#   "UserId": "AIDAI...",
#   "Account": "123456789012",
#   "Arn": "arn:aws:iam::123456789012:user/yourname"
# }

# Check your current region
echo $AWS_REGION  # or aws configure get region
# Expected: us-east-1 (or your target region)
```

### Step 1.2: Verify Terraform State
```bash
# Check current state
cd /path/to/terraform_restart_fixed

# List current resources
terraform state list | head -20

# If state is stale, plan to see what changed
terraform plan | grep -i bonus_a
```

### Step 1.3: Validate Variables
```bash
# Create terraform.tfvars (or review existing)
cat terraform.tfvars

# Should include:
# aws_region = "us-east-1"
# project_name = "chrisbarm"
# vpc_cidr = "10.0.0.0/16"
# db_username = "admin"
# db_password = "YourPassword123!"  # ⚠️ Use Secrets Manager in real orgs
```

---

## Phase 2: Terraform Plan & Review (10 minutes)

### Step 2.1: Generate Plan
```bash
terraform plan -out=bonus_a.tfplan

# This creates a plan file (safe to commit to git)
# Output should show ~15-20 resource additions:
#   + 1 EC2 instance (private)
#   + 7 VPC endpoints
#   + 2 security groups
#   + 1 IAM role
#   + 4 IAM policies
#   + 1 CloudWatch log group
#   + 1 instance profile
```

### Step 2.2: Review Plan Details
```bash
# Check EC2 instance details
terraform plan -out=bonus_a.tfplan | grep -A10 "aws_instance.bonus_a_ec2"

# Verify these critical settings:
# ✅ associate_public_ip_address = false  (PRIVATE)
# ✅ subnet_id = aws_subnet.chrisbarm_private_subnets[0].id
# ✅ iam_instance_profile = aws_iam_instance_profile.bonus_a_ec2_profile.name

# Check VPC endpoints
terraform plan -out=bonus_a.tfplan | grep -A5 "vpc_endpoint"

# Verify endpoints:
# ✅ private_dns_enabled = true  (for service discovery)
# ✅ security_group_ids includes bonus_a_endpoints_sg
```

### Step 2.3: Save Plan for Audit
```bash
# Terraform plan files are binary, convert to JSON for review
terraform show -json bonus_a.tfplan | jq .resource_changes > plan_changes.json

# Review in your IDE or version control
cat plan_changes.json | jq '.[] | select(.type == "aws_instance")'
```

---

## Phase 3: Deploy Infrastructure (5 minutes)

### Step 3.1: Apply Plan
```bash
terraform apply bonus_a.tfplan

# Monitor output for:
# ✓ aws_vpc_endpoint.ssm: Creation complete
# ✓ aws_vpc_endpoint.ec2messages: Creation complete
# ... (all 7 endpoints)
# ✓ aws_iam_role.bonus_a_ec2_role: Creation complete
# ✓ aws_instance.bonus_a_ec2: Creation complete
# ✓ aws_cloudwatch_log_group.bonus_a_logs: Creation complete
# 
# Apply complete! Resources: 20 added.
```

### Step 3.2: Capture Outputs
```bash
# Export outputs for verification scripts
terraform output -json > outputs.json

# Extract key IDs
INSTANCE_ID=$(terraform output -raw bonus_a_instance_id)
VPC_ID=$(terraform output -raw chrisbarm_vpc_id | tr -d '"')
PRIVATE_IP=$(terraform output -raw bonus_a_instance_private_ip)
PUBLIC_IP=$(terraform output -raw bonus_a_instance_public_ip)
SESSION_CMD=$(terraform output -raw bonus_a_session_manager_ready)

# Display for reference
echo "Instance ID: $INSTANCE_ID"
echo "VPC ID: $VPC_ID"
echo "Private IP: $PRIVATE_IP"
echo "Public IP: $PUBLIC_IP"  # Should be null
echo "Session Command: $SESSION_CMD"

# Save for next phase
cat > deployment_ids.sh <<EOF
export INSTANCE_ID="$INSTANCE_ID"
export VPC_ID="$VPC_ID"
export AWS_REGION="us-east-1"
EOF
```

### Step 3.3: Verify Terraform State
```bash
# Check state contains all resources
terraform state list | grep bonus_a

# Expected:
# aws_cloudwatch_log_group.bonus_a_logs
# aws_iam_instance_profile.bonus_a_ec2_profile
# aws_iam_role.bonus_a_ec2_role
# aws_iam_role_policy.bonus_a_cloudwatch_logs
# aws_iam_role_policy.bonus_a_parameter_store
# aws_iam_role_policy.bonus_a_secrets_manager
# aws_iam_role_policy.bonus_a_ssm_session
# aws_instance.bonus_a_ec2
# aws_security_group.bonus_a_ec2_sg
# aws_security_group.bonus_a_endpoints_sg
# aws_vpc_endpoint.ec2messages
# aws_vpc_endpoint.kms
# aws_vpc_endpoint.logs
# aws_vpc_endpoint.s3
# aws_vpc_endpoint.secretsmanager
# aws_vpc_endpoint.ssm
# aws_vpc_endpoint.ssmmessages
```

---

## Phase 4: Initialization Wait (3-5 minutes)

### Step 4.1: Wait for EC2 Initialization
```bash
# EC2 boots and runs user_data script (1a_user_data.sh)
# Monitor in AWS Console > EC2 > Instances

# Check instance status
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text

# Expected progression:
# pending → running → (waits for SSM agent registration)

# Wait for running state
while true; do
  STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].State.Name" \
    --output text)
  
  if [ "$STATE" = "running" ]; then
    echo "✓ Instance is running"
    break
  else
    echo "Instance state: $STATE (waiting...)"
    sleep 5
  fi
done
```

### Step 4.2: Wait for SSM Agent Registration
```bash
# SSM agent must register with Systems Manager service
# This takes 2-3 minutes even after instance is running

# Check if instance appears in Fleet Manager
aws ssm describe-instance-information \
  --query "InstanceInformationList[?InstanceId=='$INSTANCE_ID'].InstanceId" \
  --output text

# Expected: empty initially, then "$INSTANCE_ID" after 2-3 minutes

# Wait loop
echo "Waiting for SSM agent to register (2-3 minutes)..."
for i in {1..30}; do
  RESULT=$(aws ssm describe-instance-information \
    --query "InstanceInformationList[?InstanceId=='$INSTANCE_ID'].InstanceId" \
    --output text)
  
  if [ -n "$RESULT" ] && [ "$RESULT" = "$INSTANCE_ID" ]; then
    echo "✓ SSM agent registered successfully"
    break
  fi
  
  echo "Attempt $i/30: SSM agent registering... (waiting 10 seconds)"
  sleep 10
done

# If still not registered after 5 minutes
if [ -z "$RESULT" ]; then
  echo "⚠ SSM agent not registered yet. Common causes:"
  echo "  1. VPC endpoints not ready (should be immediate, but check)"
  echo "  2. EC2 security group not allowing endpoint access"
  echo "  3. Instance IAM role missing SSM permissions"
fi
```

### Step 4.3: Verify EC2 Can Reach VPC Endpoints

If SSM agent registration is stuck, diagnostics:

```bash
# From EC2 instance (requires other access method):
# Try to reach SSM endpoint directly
curl -v https://ssm.us-east-1.amazonaws.com/

# Check endpoint connectivity
nslookup ssm.us-east-1.amazonaws.com
# Should resolve to 10.0.x.x (private IP) via VPC endpoint

# Verify VPC endpoint exists and is ready
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.us-east-1.ssm" \
  --query "VpcEndpoints[].State" \
  --output text
# Expected: available
```

---

## Phase 5: Verification (Run Comprehensive Tests)

### Step 5.1: Run Full Verification Script
```bash
# Source deployment IDs
source deployment_ids.sh

# Run comprehensive verification
bash verify_bonus_a_comprehensive.sh $INSTANCE_ID $VPC_ID

# This runs all 5 main checks + 2 bonus checks
# Expected output format:
# ═══════════════════════════════════════════════════════════════
# CHECK 1: Verify EC2 Instance is PRIVATE (No Public IP)
# ✓ Instance has NO public IP (as expected)
#
# CHECK 2: Verify VPC Endpoints Exist
# ✓ ssm endpoint present
# ✓ ec2messages endpoint present
# ... (all 6 required endpoints)
#
# CHECK 3: Verify Session Manager Access
# ✓ Instance i-xxxxx appears in Session Manager Fleet
#
# etc.
```

### Step 5.2: Individual Verification Commands (if script fails)

**Test 1: Private IP Only**
```bash
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].[PrivateIpAddress, PublicIpAddress]" \
  --output text

# Expected:
# 10.0.101.x      null
```

**Test 2: VPC Endpoints Exist**
```bash
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "VpcEndpoints[].[ServiceName, State]" \
  --output table

# Expected: 7 endpoints in "available" state
# - com.amazonaws.us-east-1.ssm
# - com.amazonaws.us-east-1.ec2messages
# - com.amazonaws.us-east-1.ssmmessages
# - com.amazonaws.us-east-1.logs
# - com.amazonaws.us-east-1.secretsmanager
# - com.amazonaws.us-east-1.kms
# - com.amazonaws.us-east-1.s3
```

**Test 3: Session Manager Ready**
```bash
aws ssm describe-instance-information \
  --query "InstanceInformationList[?InstanceId=='$INSTANCE_ID']" \
  --output table

# Expected: 1 row with instance details
```

**Test 4: Start Session Manager (Interactive)**
```bash
# This opens an interactive shell on the EC2 instance
aws ssm start-session --target "$INSTANCE_ID" --region us-east-1

# Once connected:
$ aws ssm get-parameter --name /lab/db/endpoint --query Parameter.Value --output text
$ aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql | jq .
$ exit
```

**Test 5: CloudWatch Logs**
```bash
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/ec2/bonus-a" \
  --query "logGroups[].[logGroupName, retentionInDays]" \
  --output table

# Expected:
# /aws/ec2/bonus-a-rds-app     7
```

---

## Phase 6: Generate Verification Report

### Step 6.1: JSON Report
```bash
# The comprehensive script already generates this
cat bonus_a_verification_report_*.json | jq .

# Expected structure:
{
  "timestamp": "2026-01-21T14:30:45-05:00",
  "instance_id": "i-0123456789abcdef0",
  "vpc_id": "vpc-12345678",
  "aws_region": "us-east-1",
  "checks": [
    {
      "check": "Private IP",
      "status": "pass",
      "message": "No public IP assigned"
    },
    ... (all checks)
  ],
  "summary": {
    "total_checks": 7,
    "passed": 7,
    "failed": 0
  }
}
```

### Step 6.2: HTML Report (Optional)
```bash
# Convert JSON to HTML for stakeholder review
python3 << 'EOF'
import json
from datetime import datetime

report_file = "bonus_a_verification_report_20260121_143045.json"
with open(report_file) as f:
    data = json.load(f)

html = f"""
<html>
<head>
  <title>Bonus A Verification Report</title>
  <style>
    body {{ font-family: Arial; margin: 20px; }}
    .pass {{ color: green; font-weight: bold; }}
    .fail {{ color: red; font-weight: bold; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
  </style>
</head>
<body>
  <h1>Bonus A Verification Report</h1>
  <p><strong>Instance:</strong> {data['instance_id']}</p>
  <p><strong>VPC:</strong> {data['vpc_id']}</p>
  <p><strong>Region:</strong> {data['aws_region']}</p>
  <p><strong>Timestamp:</strong> {data['timestamp']}</p>
  
  <h2>Summary</h2>
  <p>
    <strong>Total:</strong> {data['summary']['total_checks']} |
    <span class="pass">Passed: {data['summary']['passed']}</span> |
    <span class="fail">Failed: {data['summary']['failed']}</span>
  </p>
  
  <h2>Detailed Results</h2>
  <table>
    <tr>
      <th>Check</th>
      <th>Status</th>
      <th>Message</th>
    </tr>
"""

for check in data['checks']:
    status_class = "pass" if check['status'] == "pass" else "fail"
    html += f"""
    <tr>
      <td>{check['check']}</td>
      <td class="{status_class}">{check['status'].upper()}</td>
      <td>{check['message']}</td>
    </tr>
"""

html += """
  </table>
</body>
</html>
"""

with open("bonus_a_report.html", "w") as f:
    f.write(html)

print("✓ Report saved to bonus_a_report.html")
EOF
```

---

## Phase 7: Session Manager Access Demo

### Step 7.1: Start Interactive Session
```bash
# Open shell on private EC2 instance
aws ssm start-session --target "$INSTANCE_ID" --region us-east-1

# You now have a bash shell. Try:
$ whoami
# output: ubuntu (or ec2-user)

$ hostname
# output: ip-10-0-101-x

$ curl http://169.254.169.254/latest/meta-data/local-ipv4
# output: 10.0.101.x

$ curl http://169.254.169.254/latest/meta-data/public-ipv4
# output: (empty - no public IP!)
```

### Step 7.2: Read Configuration Stores
```bash
# Inside the session:

# Get database endpoint
$ aws ssm get-parameter --name /lab/db/endpoint \
  --query Parameter.Value --output text
# output: chrisbarm-rds01.xxxxxx.us-east-1.rds.amazonaws.com

# Get database credentials
$ aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql \
  --query SecretString --output text | jq .
# output:
# {
#   "username": "admin",
#   "password": "YourPassword123!",
#   "host": "chrisbarm-rds01.xxxxxx.us-east-1.rds.amazonaws.com",
#   "port": 3306,
#   "dbname": "labdb"
# }

# Connect to RDS (if you have mysql client installed)
$ mysql -h $(aws ssm get-parameter --name /lab/db/endpoint \
  --query Parameter.Value --output text) \
  -u admin -p labdb
# (enter password from secrets)
# mysql> SELECT 1;
# +---+
# | 1 |
# +---+
# | 1 |
# +---+
```

### Step 7.3: Verify Least-Privilege Isolation
```bash
# Inside the session, try to escalate (should fail):

# Try to list IAM users (NOT permitted)
$ aws iam list-users
# Error: User: arn:aws:iam::123456789012:assumed-role/bonus-a-ec2-xxxxx/i-0123456789abcdef0
#        is not authorized to perform: iam:ListUsers

# Try to read a different secret (NOT permitted)
$ aws secretsmanager get-secret-value --secret-id prod/api/key
# Error: User is not authorized to perform: secretsmanager:GetSecretValue

# Try to write to a different log group (NOT permitted)
$ aws logs put-log-events \
  --log-group-name /aws/lambda/prod-handler \
  --log-stream-name test \
  --log-events timestamp=$(date +%s000),message="test"
# Error: User is not authorized to perform: logs:PutLogEvents

# ✓ All privilege escalations blocked!
```

### Step 7.4: Exit Session
```bash
$ exit
# or Ctrl+D

# Back to your local shell
```

---

## Phase 8: Troubleshooting (If Anything Fails)

### Issue: "EC2 instance does not appear in Fleet Manager"

**Diagnosis**:
```bash
# Check EC2 status
aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].[State.Name, LaunchTime]"

# Check VPC endpoints are ready
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.us-east-1.ssm" \
  --query "VpcEndpoints[0].State"

# Check security group allows endpoint access
aws ec2 describe-security-groups \
  --group-ids $(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
    --output text) \
  --query "SecurityGroups[0].IpPermissionsEgress"
```

**Fix**:
1. Wait 2-3 more minutes (SSM agent registration is delayed)
2. Check endpoint security group allows HTTPS 443 from EC2 SG
3. Verify instance IAM role has SSM permissions (should be automatic)
4. Restart SSM agent (if you can access EC2 another way):
   ```bash
   sudo systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent
   ```

### Issue: "Failed to start session: not available"

**Fix**:
```bash
# Wait longer for VPC endpoint DNS propagation (private DNS enabled)
# Then try again

aws ssm start-session --target "$INSTANCE_ID" --debug 2>&1 | head -50
```

### Issue: "Access Denied" reading secrets/parameters

**Fix**:
```bash
# Check IAM role attached to instance
aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].IamInstanceProfile.Arn"

# Check role's policies
ROLE=$(aws iam get-instance-profile \
  --instance-profile-name <name-from-above> \
  --query "InstanceProfile.Roles[0].RoleName" --output text)

aws iam list-role-policies --role-name "$ROLE" --output table

# Verify secret ARN matches policy resource
aws secretsmanager describe-secret --secret-id lab1a/rds/mysql \
  --query ARN
# Should match: "arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:lab1a/rds/mysql*"
```

---

## Phase 9: Cleanup (Optional)

### Destroy Bonus A Resources
```bash
# If you need to tear down:
terraform destroy -auto-approve

# Verify resources are deleted
terraform state list | grep -i bonus
# Should return nothing
```

---

## Interview Talking Points Summary

After completing this walkthrough, you can confidently explain:

**"I deployed a private EC2 instance using Terraform with VPC Interface Endpoints for SSM, Logs, and Secrets Manager. The instance has no public IP, uses Session Manager instead of SSH, and the IAM role is scoped to specific secrets and parameters. All infrastructure-as-code is version-controlled and follows least-privilege security patterns. The deployment validated through automated scripts, confirming private IP, endpoint readiness, and configuration store access. This architecture mirrors production practices in regulated orgs."**

---

**Document Version**: 1.0  
**Last Updated**: January 21, 2026
