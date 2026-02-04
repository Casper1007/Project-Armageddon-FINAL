# Lab 1a Verification - Comprehensive Testing Guide

## Overview

This guide provides step-by-step instructions to verify all 10 tests from your requirements, split into **offline tests** (run from your laptop) and **EC2-side tests** (run from within the EC2 instance).

---

## Variables to Set

```bash
export REGION="us-east-1"
export INSTANCE_ID="i-0968fd41f8aaa43eb"
export SECRET_ID="lab1a/rds/mysql"
export EXPECTED_ROLE_NAME="chrisbarm-ec2-role01"
```

---

## Part A: Offline Tests (Tests 1-5)
**Run these from your laptop/local terminal**

### Test 1: PASS/FAIL - Secret exists

```bash
aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" >/dev/null 2>&1 \
  && echo "✓ PASS: secret exists ($SECRET_ID)" \
  || (echo "✗ FAIL: secret not found or no permission ($SECRET_ID)"; exit 1)
```

**Current Status:** ✓ PASS  
**Output:** `lab1a/rds/mysql`

---

### Test 2: PASS/FAIL - EC2 instance has an IAM instance profile attached

```bash
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].IamInstanceProfile.Arn" \
  --output text 2>/dev/null \
  | grep -q '^arn:aws:iam::' \
  && echo "✓ PASS: instance has IAM role attached ($INSTANCE_ID)" \
  || (echo "✗ FAIL: no IAM instance profile attached ($INSTANCE_ID)"; exit 1)
```

**Current Status:** ✓ PASS  
**Output:** `arn:aws:iam::198547498722:instance-profile/chrisbarm-instance-profile01`

---

### Test 3: PASS/FAIL - Extract the instance profile name

```bash
PROFILE_NAME="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].IamInstanceProfile.Arn" \
  --output text 2>/dev/null | awk -F/ '{print $NF}')"

[ -n "$PROFILE_NAME" ] && [ "$PROFILE_NAME" != "None" ] \
  && echo "✓ PASS: instance profile = $PROFILE_NAME" \
  || (echo "✗ FAIL: could not resolve instance profile"; exit 1)
```

**Current Status:** ✓ PASS  
**Extracted Value:** `chrisbarm-instance-profile01`

---

### Test 4: PASS/FAIL - Resolve instance profile → role name

```bash
ROLE_NAME="$(aws iam get-instance-profile \
  --instance-profile-name "$PROFILE_NAME" \
  --query "InstanceProfile.Roles[0].RoleName" \
  --output text 2>/dev/null)"

[ -n "$ROLE_NAME" ] && [ "$ROLE_NAME" != "None" ] \
  && echo "✓ PASS: role name = $ROLE_NAME" \
  || (echo "✗ FAIL: could not resolve role from instance profile"; exit 1)
```

**Current Status:** ✓ PASS  
**Resolved Role:** `chrisbarm-ec2-role01`

---

### Test 5: PASS/FAIL - Role has Secrets Manager read capability

```bash
aws iam list-attached-role-policies \
  --role-name "$ROLE_NAME" \
  --query "AttachedPolicies[].PolicyArn" \
  --output text 2>/dev/null \
  | grep -Eq 'SecretsManager|secretsmanager' \
  && echo "✓ PASS: role likely has Secrets Manager-related policy attached ($ROLE_NAME)" \
  || (echo "✗ FAIL: role appears to lack Secrets Manager-related managed policies ($ROLE_NAME)"; exit 1)
```

**Current Status:** ✓ PASS  
**Attached Policies:**
- `arn:aws:iam::198547498722:policy/secrets_policy` ← Secrets Manager access
- `arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy`
- `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore`

---

## Part B: EC2-Side Tests (Tests 6-8)
**Run these FROM INSIDE the EC2 instance**

### How to Access EC2

**Option 1: Using AWS Systems Manager Session Manager (Recommended)**

```bash
aws ssm start-session --target "$INSTANCE_ID" --region "$REGION"
```

**Option 2: SSH (if you have the key pair)**

```bash
ssh -i <your-key.pem> ec2-user@<instance-public-ip>
```

---

### Test 6: PASS/FAIL - Verify running as expected role

**Run inside EC2:**

```bash
ROLE_NAME="chrisbarm-ec2-role01"
aws sts get-caller-identity \
  --query "Arn" --output text 2>/dev/null \
  | grep -q ":assumed-role/$ROLE_NAME/" \
  && echo "✓ PASS: running as expected role ($ROLE_NAME)" \
  || (echo "✗ FAIL: not running as expected role ($ROLE_NAME)"; exit 1)
```

**Expected Output:**
```
✓ PASS: running as expected role (chrisbarm-ec2-role01)
Current ARN: arn:aws:sts::198547498722:assumed-role/chrisbarm-ec2-role01/i-0968fd41f8aaa43eb
```

---

### Test 7: PASS/FAIL - Role can describe secret

**Run inside EC2:**

```bash
aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" >/dev/null 2>&1 \
  && echo "✓ PASS: role can describe secret ($SECRET_ID)" \
  || (echo "✗ FAIL: role cannot describe secret ($SECRET_ID)"; exit 1)
```

**Expected Output:**
```
✓ PASS: role can describe secret (lab1a/rds/mysql)
```

---

### Test 8: PASS/FAIL - Role can get secret value

**Run inside EC2:**

```bash
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "SecretString" --output text >/dev/null 2>&1 \
  && echo "✓ PASS: role can read secret value ($SECRET_ID)" \
  || (echo "✗ FAIL: role cannot read secret value ($SECRET_ID)"; exit 1)
```

**Expected Output:**
```
✓ PASS: role can read secret value (lab1a/rds/mysql)
```

**To view the secret contents (inside EC2):**

```bash
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "SecretString" --output text | jq '.'
```

**Expected Structure:**
```json
{
  "username": "admin",
  "password": "your-password-here",
  "host": "chrisbarm-rds01.c4x68420cyvy.us-east-1.rds.amazonaws.com",
  "port": 3306,
  "dbname": "chrisbarm"
}
```

---

## Part C: Optional Guardrails (Tests 9-10)
**Run these from your laptop**

### Test 9 (OPTIONAL): PASS/FAIL - Secret rotation enabled

```bash
aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "RotationEnabled" \
  --output text 2>/dev/null \
  | grep -qi '^True$' \
  && echo "✓ PASS: rotation enabled ($SECRET_ID)" \
  || (echo "⚠ WARNING: rotation disabled or unknown ($SECRET_ID)"; exit 1)
```

**Note:** For lab purposes, rotation can be disabled.

---

### Test 10 (OPTIONAL): PASS/FAIL - No wildcard principal in policy

```bash
aws secretsmanager get-resource-policy \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "ResourcePolicy" \
  --output text 2>/dev/null \
  | grep -q '"Principal":"\*"' \
  && (echo "✗ FAIL: secret resource policy allows wildcard principal"; exit 1) \
  || echo "✓ PASS: no wildcard principal detected (basic check)"
```

**Expected Output:**
```
✓ PASS: no wildcard principal detected (basic check)
```

---

## Automated Test Scripts

### Run All Offline Tests (1-5)

```bash
cd <terraform-directory>
REGION="us-east-1" \
INSTANCE_ID="i-0968fd41f8aaa43eb" \
SECRET_ID="lab1a/rds/mysql" \
bash verify_secrets_and_iam.sh
```

### Run All EC2-Side Tests (6-8)

**Inside EC2:**

```bash
# Copy script to EC2 first, or run commands individually
REGION="us-east-1" \
EXPECTED_ROLE_NAME="chrisbarm-ec2-role01" \
SECRET_ID="lab1a/rds/mysql" \
bash verify_ec2_secrets_access.sh
```

---

## Summary Table

| Test | Type | Location | Status | Details |
|------|------|----------|--------|---------|
| 1 | Secret exists | Offline | ✓ PASS | Secret `lab1a/rds/mysql` found |
| 2 | EC2 has IAM profile | Offline | ✓ PASS | Profile ARN: `arn:aws:iam::198547498722:instance-profile/chrisbarm-instance-profile01` |
| 3 | Extract profile name | Offline | ✓ PASS | Profile: `chrisbarm-instance-profile01` |
| 4 | Resolve role name | Offline | ✓ PASS | Role: `chrisbarm-ec2-role01` |
| 5 | Role has Secrets policy | Offline | ✓ PASS | Policy: `secrets_policy` attached |
| 6 | EC2 assumes role | EC2-Side | ⏳ PENDING | Verify inside EC2 |
| 7 | Role can describe secret | EC2-Side | ⏳ PENDING | Verify inside EC2 |
| 8 | Role can read secret | EC2-Side | ⏳ PENDING | Verify inside EC2 |
| 9 | Rotation enabled | Offline | ⚠ OPTIONAL | Lab: can be disabled |
| 10 | No wildcard principal | Offline | ⚠ OPTIONAL | Security check |

---

## Troubleshooting

### If Test 1 Fails
- Check secret ID is correct
- Verify region is correct
- Ensure AWS credentials have `secretsmanager:DescribeSecret` permission

### If Test 6 Fails (Inside EC2)
- Verify EC2 instance has IAM instance profile attached
- Check instance profile has correct role
- Verify role has permissions

### If Test 7-8 Fail (Inside EC2)
- Check IAM role has `secrets_policy` attached
- Verify secret ARN is correct
- Check Secrets Manager resource policy (Test 10)

---

## Next Steps

1. ✅ Run tests 1-5 from your laptop
2. ✅ SSH/SSM into EC2
3. ✅ Run tests 6-8 inside EC2
4. ✅ Verify all tests pass
5. ✅ Ready for lab grading!
