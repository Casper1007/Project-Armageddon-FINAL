#!/bin/bash

################################################################################
# Lab 1a: EC2-Side Secrets Manager & IAM Verification
# Run this INSIDE the EC2 instance to verify IAM role assumes correctly
# and can access Secrets Manager
################################################################################

set -e

# ============================================================================
# CONFIGURATION - SET YOUR VARIABLES HERE
# ============================================================================
REGION="${REGION:-us-east-1}"
EXPECTED_ROLE_NAME="${EXPECTED_ROLE_NAME:-chrisbarm-ec2-role01}"
SECRET_ID="${SECRET_ID:-lab1a/rds/mysql}"

echo "============================================"
echo "Lab 1a EC2-Side IAM & Secrets Verification"
echo "============================================"
echo "Region: $REGION"
echo "Expected Role: $EXPECTED_ROLE_NAME"
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
# TEST 6: From inside EC2, verify instance identity is the expected role
# ============================================================================
echo ""
echo "[6/10] Checking: EC2 is assuming the expected role..."
CURRENT_ARN=$(aws sts get-caller-identity \
  --query "Arn" --output text 2>/dev/null)

if echo "$CURRENT_ARN" | grep -q ":assumed-role/$EXPECTED_ROLE_NAME/"; then
  test_result 0 "Running as expected role ($EXPECTED_ROLE_NAME)"
  echo "      Current ARN: $CURRENT_ARN"
else
  test_result 1 "Not running as expected role ($EXPECTED_ROLE_NAME)"
  echo "      Current ARN: $CURRENT_ARN"
fi

# ============================================================================
# TEST 7: From inside EC2, role can read the secret metadata
# ============================================================================
echo ""
echo "[7/10] Checking: Role can describe secret (metadata)..."
aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" >/dev/null 2>&1
test_result $? "Role can describe secret ($SECRET_ID)"

# ============================================================================
# TEST 8: From inside EC2, role can read the secret value
# ============================================================================
echo ""
echo "[8/10] Checking: Role can get secret value..."
SECRET_VALUE=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "SecretString" --output text 2>/dev/null)

if [ -n "$SECRET_VALUE" ]; then
  test_result 0 "Role can read secret value ($SECRET_ID)"
else
  test_result 1 "Role cannot read secret value or secret is empty ($SECRET_ID)"
fi

# ============================================================================
# BONUS: Display secret structure (for verification)
# ============================================================================
echo ""
echo "[BONUS] Secret contents (structure):"
echo "$SECRET_VALUE" | jq 'keys' 2>/dev/null || echo "  (Unable to parse as JSON)"

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "============================================"
echo "EC2-Side Test Summary"
echo "============================================"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
  echo "❌ Some tests failed. Review the failures above."
  exit 1
else
  echo "✅ All EC2-side checks passed!"
  exit 0
fi
