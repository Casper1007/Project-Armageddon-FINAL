#!/bin/bash
################################################################################
# Bonus-A Verification: Test 4 - Config Store Access from Session
#
# MUST be run FROM INSIDE the EC2 instance (via SSM Session Manager)
#
# Expected: Both commands should return values (no permission errors)
#   - aws ssm get-parameter should return /lab/db/endpoint value
#   - aws secretsmanager get-secret-value should return JSON with credentials
#
# Usage (from your workstation):
#   1. aws ssm start-session --target <INSTANCE_ID> --region us-east-1
#   2. [Inside session] bash
#   3. [Inside session] bash verify_bonus_a_4_config_stores.sh
################################################################################

set -e

DB_ENDPOINT_PARAM="${1:-/lab/db/endpoint}"
SECRET_ID="${2:-lab1a/rds/mysql}"
REGION="${3:-us-east-1}"

echo "======================================================================"
echo "Bonus-A Test 4: Verify Config Store Access from EC2"
echo "======================================================================"
echo ""
echo "Parameter name: $DB_ENDPOINT_PARAM"
echo "Secret ID:      $SECRET_ID"
echo "Region:         $REGION"
echo ""
echo "(This test must be run FROM INSIDE the EC2 instance via SSM Session)"
echo ""

ERRORS=0

# Test 1: Get parameter
echo "Test 1: Retrieving parameter from SSM Parameter Store..."
PARAM_VALUE=$(aws ssm get-parameter \
  --name "$DB_ENDPOINT_PARAM" \
  --region "$REGION" \
  --query "Parameter.Value" \
  --output text 2>/dev/null || echo "ERROR")

if [ "$PARAM_VALUE" = "ERROR" ]; then
  echo "  ✗ FAIL: Could not retrieve parameter"
  ERRORS=$((ERRORS + 1))
else
  echo "  ✓ Parameter retrieved: $PARAM_VALUE"
fi

echo ""

# Test 2: Get secret
echo "Test 2: Retrieving secret from Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "SecretString" \
  --output text 2>/dev/null || echo "ERROR")

if [ "$SECRET_JSON" = "ERROR" ]; then
  echo "  ✗ FAIL: Could not retrieve secret"
  ERRORS=$((ERRORS + 1))
else
  # Parse JSON safely (check if it's valid JSON with username)
  if echo "$SECRET_JSON" | grep -q '"username"'; then
    echo "  ✓ Secret retrieved (contains valid credentials)"
  else
    echo "  ✗ Secret retrieved but format unexpected"
    ERRORS=$((ERRORS + 1))
  fi
fi

echo ""
if [ $ERRORS -eq 0 ]; then
  echo "✓ PASS: EC2 can access both Parameter Store and Secrets Manager"
  exit 0
else
  echo "✗ FAIL: $ERRORS error(s) accessing config stores"
  echo ""
  echo "Troubleshooting:"
  echo "  1. Check IAM role policy includes secretsmanager:GetSecretValue"
  echo "  2. Check IAM role policy includes ssm:GetParameter(s)"
  echo "  3. Verify Secrets Manager endpoint is configured"
  echo "  4. Verify SSM Parameter endpoint is configured"
  exit 1
fi
