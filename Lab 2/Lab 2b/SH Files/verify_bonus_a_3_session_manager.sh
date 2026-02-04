#!/bin/bash
################################################################################
# Bonus-A Verification: Test 3 - Session Manager Path Works (SSM Agent Ready)
#
# Expected: Instance ID should appear in the instance information list
# This proves the SSM agent is registered and Session Manager can reach it
################################################################################

set -e

INSTANCE_ID="${1:?Usage: $0 <INSTANCE_ID>}"
REGION="${2:-us-east-1}"

echo "======================================================================"
echo "Bonus-A Test 3: Verify Session Manager Path Works"
echo "======================================================================"
echo ""
echo "Instance ID: $INSTANCE_ID"
echo "Region:      $REGION"
echo ""

echo "Querying SSM managed instances..."
echo "(Note: May take 2-3 minutes for SSM agent to register after instance launch)"
echo ""

# Query managed instances
MANAGED_INSTANCES=$(aws ssm describe-instance-information \
  --region "$REGION" \
  --query "InstanceInformationList[].InstanceId" \
  --output text 2>/dev/null || echo "")

echo "Managed instances in region:"
echo "$MANAGED_INSTANCES" | tr '\t' '\n'
echo ""

# Check if our instance is in the list
if echo "$MANAGED_INSTANCES" | grep -q "$INSTANCE_ID"; then
  echo "✓ PASS: Instance $INSTANCE_ID is registered with SSM"
  echo ""
  echo "You can now access the instance with:"
  echo "  aws ssm start-session --target $INSTANCE_ID --region $REGION"
  exit 0
else
  echo "✗ FAIL: Instance $INSTANCE_ID is NOT registered with SSM"
  echo ""
  echo "Troubleshooting:"
  echo "  1. Wait 2-3 minutes for SSM agent to register"
  echo "  2. Check IAM role has ssm:* permissions"
  echo "  3. Verify VPC endpoints for SSM, EC2Messages, SSMMessages exist"
  echo "  4. Check security group allows HTTPS (443) outbound to endpoints"
  exit 1
fi
