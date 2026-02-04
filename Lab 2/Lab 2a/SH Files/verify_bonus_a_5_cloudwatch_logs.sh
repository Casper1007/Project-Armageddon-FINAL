#!/bin/bash
################################################################################
# Bonus-A Verification: Test 5 - CloudWatch Logs Endpoint Functional
#
# Expected: Log streams should exist or be creatable in the Bonus-A log group
# This verifies the CloudWatch Logs VPC endpoint is working
################################################################################

set -e

LOG_GROUP="${1:?Usage: $0 <LOG_GROUP_NAME>}"
REGION="${2:-us-east-1}"

echo "======================================================================"
echo "Bonus-A Test 5: Verify CloudWatch Logs Endpoint is Functional"
echo "======================================================================"
echo ""
echo "Log group: $LOG_GROUP"
echo "Region:    $REGION"
echo ""

ERRORS=0

# Test 1: Check if log group exists
echo "Test 1: Checking if log group exists..."
LOG_GROUP_EXISTS=$(aws logs describe-log-groups \
  --log-group-name-prefix "$LOG_GROUP" \
  --region "$REGION" \
  --query "logGroups[?logGroupName=='$LOG_GROUP'].logGroupName" \
  --output text 2>/dev/null || echo "")

if [ -n "$LOG_GROUP_EXISTS" ]; then
  echo "  ✓ Log group exists: $LOG_GROUP_EXISTS"
else
  echo "  ✗ Log group NOT found"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# Test 2: Check for log streams (if any logs written yet)
echo "Test 2: Checking log streams..."
LOG_STREAMS=$(aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --region "$REGION" \
  --query "logStreams[].logStreamName" \
  --output text 2>/dev/null || echo "")

if [ -n "$LOG_STREAMS" ]; then
  echo "  ✓ Log streams found:"
  echo "$LOG_STREAMS" | tr '\t' '\n' | sed 's/^/    - /'
else
  echo "  ℹ No log streams yet (normal if app hasn't started logging)"
fi

echo ""

# Test 3: Attempt to create a test log stream (from workstation)
echo "Test 3: Testing CloudWatch Logs endpoint write capability..."
TEST_STREAM="bonus-a-test-stream-$(date +%s)"
TEST_MSG="Bonus-A verification test at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

if aws logs create-log-stream \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name "$TEST_STREAM" \
  --region "$REGION" 2>/dev/null; then
  
  # Try to put an event
  if aws logs put-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "$TEST_STREAM" \
    --log-events timestamp=$(date +%s)000,message="$TEST_MSG" \
    --region "$REGION" 2>/dev/null; then
    
    echo "  ✓ Successfully wrote test event to CloudWatch Logs"
  else
    echo "  ✗ Could not write test event to CloudWatch Logs"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "  ✗ Could not create test log stream"
  ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
  echo "✓ PASS: CloudWatch Logs endpoint is functional"
  exit 0
else
  echo "✗ FAIL: $ERRORS error(s) with CloudWatch Logs"
  echo ""
  echo "Troubleshooting:"
  echo "  1. Check log group exists: aws logs describe-log-groups --region $REGION"
  echo "  2. Check CloudWatch Logs endpoint is created and enabled"
  echo "  3. Verify security group allows HTTPS (443) from private subnets"
  echo "  4. Verify IAM role has logs:CreateLogStream, logs:PutLogEvents"
  exit 1
fi
