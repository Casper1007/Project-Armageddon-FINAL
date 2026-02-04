#!/bin/bash
################################################################################
# Bonus-A Verification: Test 1 - EC2 is Private (No Public IP)
#
# Expected: PublicIpAddress should be null (private instance only)
# Acceptable output: 
#   - null
#   - (empty line)
#   - NOT an IP address like 54.123.45.67
################################################################################

set -e

INSTANCE_ID="${1:?Usage: $0 <INSTANCE_ID>}"
REGION="${2:-us-east-1}"

echo "======================================================================"
echo "Bonus-A Test 1: Verify EC2 is Private (No Public IP)"
echo "======================================================================"
echo ""
echo "Instance ID: $INSTANCE_ID"
echo "Region:      $REGION"
echo ""

# Query public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[].Instances[].PublicIpAddress" \
  --output text 2>/dev/null || echo "None")

# Normalize empty string to "null" for clarity
if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "None" ]; then
  PUBLIC_IP="null"
fi

echo "Result: PublicIpAddress = $PUBLIC_IP"
echo ""

# Validation
if [ "$PUBLIC_IP" = "null" ]; then
  echo "✓ PASS: Instance is private (no public IP assigned)"
  exit 0
else
  echo "✗ FAIL: Instance has public IP ($PUBLIC_IP), should be null"
  exit 1
fi
