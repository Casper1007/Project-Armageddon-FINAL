#!/bin/bash

################################################################################
# Lab 1a: Comprehensive Secrets Manager & IAM Verification
# Tests: Secret existence, IAM role attachment, policy compliance
################################################################################

set -e

# ============================================================================
# CONFIGURATION - SET YOUR VARIABLES HERE
# ============================================================================
REGION="${REGION:-us-east-1}"
INSTANCE_ID="${INSTANCE_ID:-i-0968fd41f8aaa43eb}"
SECRET_ID="${SECRET_ID:-lab1a/rds/mysql}"

echo "============================================"
echo "Lab 1a Secrets & IAM Verification"
echo "============================================"
echo "Region: $REGION"
echo "Instance ID: $INSTANCE_ID"
echo "Secret ID: $SECRET_ID"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# Helper function for test results
test_result() {
  local result=$1
  local message=$2
  if [ $result -eq 0 ]; then
    echo "✓ PASS: $message"
    ((PASS_COUNT++))
  else
    echo "✗ FAIL: $message"
    ((FAIL_COUNT++))
  fi
}

# ============================================================================
# TEST 1: Secret exists
# ============================================================================
echo ""
echo "[1/10] Checking: Secret exists..."
aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" >/dev/null 2>&1
test_result $? "Secret exists ($SECRET_ID)"

# ============================================================================
# TEST 2: EC2 instance has an IAM instance profile attached
# ============================================================================
echo ""
echo "[2/10] Checking: EC2 instance has IAM instance profile..."
PROFILE_ARN=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].IamInstanceProfile.Arn" \
  --output text 2>/dev/null)

if echo "$PROFILE_ARN" | grep -q '^arn:aws:iam::'; then
  test_result 0 "Instance has IAM role attached ($INSTANCE_ID)"
else
  test_result 1 "Instance has IAM role attached ($INSTANCE_ID) - got: $PROFILE_ARN"
fi

# ============================================================================
# TEST 3: Extract the instance profile name
# ============================================================================
echo ""
echo "[3/10] Extracting: Instance profile name..."
PROFILE_NAME=$(echo "$PROFILE_ARN" | awk -F/ '{print $NF}')

if [ -n "$PROFILE_NAME" ] && [ "$PROFILE_NAME" != "None" ]; then
  test_result 0 "Instance profile resolved: $PROFILE_NAME"
else
  test_result 1 "Instance profile could not be resolved"
  exit 1
fi

# ============================================================================
# TEST 4: Resolve instance profile → role name
# ============================================================================
echo ""
echo "[4/10] Resolving: Role name from instance profile..."
ROLE_NAME=$(aws iam get-instance-profile \
  --instance-profile-name "$PROFILE_NAME" \
  --query "InstanceProfile.Roles[0].RoleName" \
  --output text 2>/dev/null)

if [ -n "$ROLE_NAME" ] && [ "$ROLE_NAME" != "None" ]; then
  test_result 0 "Role name resolved: $ROLE_NAME"
else
  test_result 1 "Role name could not be resolved"
  exit 1
fi

# ============================================================================
# TEST 5: Role has Secrets Manager read capability
# ============================================================================
echo ""
echo "[5/10] Checking: Role has Secrets Manager policy..."
POLICY_OUTPUT=$(aws iam list-attached-role-policies \
  --role-name "$ROLE_NAME" \
  --query "AttachedPolicies[].PolicyArn" \
  --output text 2>/dev/null)

if echo "$POLICY_OUTPUT" | grep -Eq 'SecretsManager|secretsmanager'; then
  test_result 0 "Role has Secrets Manager-related policy ($ROLE_NAME)"
else
  test_result 1 "Role lacks Secrets Manager-related managed policies ($ROLE_NAME)"
fi

# ============================================================================
# TEST 6: From inside EC2, verify instance identity is the expected role
# ============================================================================
echo ""
echo "[6/10] Checking: EC2 instance is assuming the expected role..."
echo "         [Run this check FROM INSIDE THE EC2 INSTANCE]"
echo ""
echo "ssh/ssm-session into $INSTANCE_ID and run:"
echo "  aws sts get-caller-identity --query 'Arn' --output text"
echo ""
echo "Expected to contain: :assumed-role/$ROLE_NAME/"
echo ""

# ============================================================================
# TEST 7: From inside EC2, role can read the secret metadata
# ============================================================================
echo ""
echo "[7/10] Checking: Role can describe secret (metadata only)..."
echo "         [Run this check FROM INSIDE THE EC2 INSTANCE]"
echo ""
echo "ssh/ssm-session into $INSTANCE_ID and run:"
cat > /tmp/ec2_test_7.sh <<'EOF'
REGION="${REGION:-us-east-1}"
SECRET_ID="${SECRET_ID:-lab1a/rds/mysql}"
aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" >/dev/null 2>&1 \
  && echo "PASS: Role can describe secret ($SECRET_ID)" \
  || (echo "FAIL: Role cannot describe secret ($SECRET_ID)"; exit 1)
EOF
echo "  $(cat /tmp/ec2_test_7.sh | grep -A 5 'aws secretsmanager')"
echo ""

# ============================================================================
# TEST 8: From inside EC2, role can read the secret value
# ============================================================================
echo ""
echo "[8/10] Checking: Role can get secret value..."
echo "         [Run this check FROM INSIDE THE EC2 INSTANCE]"
echo ""
echo "ssh/ssm-session into $INSTANCE_ID and run:"
cat > /tmp/ec2_test_8.sh <<'EOF'
REGION="${REGION:-us-east-1}"
SECRET_ID="${SECRET_ID:-lab1a/rds/mysql}"
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "SecretString" --output text >/dev/null 2>&1 \
  && echo "PASS: Role can read secret value ($SECRET_ID)" \
  || (echo "FAIL: Role cannot read secret value ($SECRET_ID)"; exit 1)
EOF
echo "  $(cat /tmp/ec2_test_8.sh | grep -A 5 'aws secretsmanager')"
echo ""

# ============================================================================
# TEST 9 (OPTIONAL): Fail if secret rotation is disabled
# ============================================================================
echo ""
echo "[9/10] OPTIONAL - Checking: Secret rotation status..."
ROTATION_STATUS=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "RotationEnabled" \
  --output text 2>/dev/null)

if echo "$ROTATION_STATUS" | grep -qi '^True$'; then
  test_result 0 "Rotation enabled ($SECRET_ID)"
else
  echo "ℹ  INFO: Rotation disabled or unknown ($SECRET_ID) - Status: $ROTATION_STATUS"
fi

# ============================================================================
# TEST 10 (OPTIONAL): Fail if secret policy allows wildcard principal
# ============================================================================
echo ""
echo "[10/10] OPTIONAL - Checking: Secret resource policy (no wildcard)..."
POLICY=$(aws secretsmanager get-resource-policy \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "ResourcePolicy" \
  --output text 2>/dev/null)

if echo "$POLICY" | grep -q '"Principal":"\*"'; then
  test_result 1 "Secret resource policy allows wildcard principal"
else
  test_result 0 "No wildcard principal detected in resource policy"
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "============================================"
echo "Test Summary"
echo "============================================"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
  echo "❌ Some tests failed. Review the failures above."
  exit 1
else
  echo "✅ All automated checks passed!"
  echo ""
  echo "Next: Run EC2-side checks (tests 6-8) from inside the instance:"
  echo "  ssh -i <key> ec2-user@<instance-ip>"
  echo "  OR use AWS Systems Manager Session Manager:"
  echo "    aws ssm start-session --target $INSTANCE_ID --region $REGION"
  exit 0
fi
