#!/bin/bash
################################################################################
# Bonus-A Verification: Test 2 - VPC Endpoints Exist
#
# Expected: Service names should include:
#   - com.amazonaws.us-east-1.ssm
#   - com.amazonaws.us-east-1.ec2messages
#   - com.amazonaws.us-east-1.ssmmessages
#   - com.amazonaws.us-east-1.logs
#   - com.amazonaws.us-east-1.secretsmanager
#   - com.amazonaws.us-east-1.kms
#   - com.amazonaws.us-east-1.s3
################################################################################

set -e

VPC_ID="${1:?Usage: $0 <VPC_ID>}"
REGION="${2:-us-east-1}"

echo "======================================================================"
echo "Bonus-A Test 2: Verify VPC Endpoints Exist"
echo "======================================================================"
echo ""
echo "VPC ID: $VPC_ID"
echo "Region: $REGION"
echo ""

# Query all VPC endpoints for this VPC
echo "Querying VPC endpoints..."
ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region "$REGION" \
  --query "VpcEndpoints[].ServiceName" \
  --output text 2>/dev/null || echo "")

echo "Found endpoints:"
echo "$ENDPOINTS" | tr '\t' '\n'
echo ""

# Check for required services
REQUIRED_SERVICES=(
  "ssm"
  "ec2messages"
  "ssmmessages"
  "logs"
  "secretsmanager"
  "kms"
  "s3"
)

MISSING=0
for service in "${REQUIRED_SERVICES[@]}"; do
  if echo "$ENDPOINTS" | grep -q "$service"; then
    echo "✓ $service endpoint found"
  else
    echo "✗ $service endpoint MISSING"
    MISSING=$((MISSING + 1))
  fi
done

echo ""
if [ $MISSING -eq 0 ]; then
  echo "✓ PASS: All required VPC endpoints exist"
  exit 0
else
  echo "✗ FAIL: $MISSING endpoint(s) missing"
  exit 1
fi
