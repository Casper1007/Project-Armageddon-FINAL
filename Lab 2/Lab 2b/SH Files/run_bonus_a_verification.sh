#!/bin/bash
################################################################################
# Bonus-A Quick Start: Run All Verification Tests in Order
#
# This script automates running all 5 verification tests and displays results
# 
# Usage:
#   bash run_bonus_a_verification.sh <INSTANCE_ID> <VPC_ID> [REGION]
################################################################################

set -e

INSTANCE_ID="${1:?Usage: $0 <INSTANCE_ID> <VPC_ID> [REGION]}"
VPC_ID="${2:?Usage: $0 <INSTANCE_ID> <VPC_ID> [REGION]}"
REGION="${3:-us-east-1}"

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    BONUS-A VERIFICATION TEST SUITE                        ║"
echo "║              Private EC2 + VPC Endpoints + Session Manager                ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

PASSED=0
FAILED=0

# Test 1
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 1: EC2 is Private (No Public IP)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if bash verify_bonus_a_1_private_ip.sh "$INSTANCE_ID" "$REGION" 2>&1; then
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi
echo ""

# Test 2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 2: VPC Endpoints Exist"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if bash verify_bonus_a_2_vpc_endpoints.sh "$VPC_ID" "$REGION" 2>&1; then
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi
echo ""

# Test 3
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 3: Session Manager Path Works"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if bash verify_bonus_a_3_session_manager.sh "$INSTANCE_ID" "$REGION" 2>&1; then
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi
echo ""

# Test 4 (Manual - needs to run from inside EC2)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 4: Config Store Access (MANUAL - run from inside EC2)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ℹ This test must be run FROM INSIDE the EC2 instance"
echo ""
echo "Instructions:"
echo "  1. aws ssm start-session --target $INSTANCE_ID --region $REGION"
echo "  2. [Inside session] sh"
echo "  3. [Inside session] bash verify_bonus_a_4_config_stores.sh"
echo ""
echo "⏭  Skipping for now (requires manual execution)"
echo ""

# Test 5
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 5: CloudWatch Logs Endpoint Functional"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if bash verify_bonus_a_5_cloudwatch_logs.sh "/aws/ec2/bonus-a-rds-app" "$REGION" 2>&1; then
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi
echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                           TEST SUMMARY                                    ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo "  Manual: 1 (Test 4 - Config Stores, run from inside EC2)"
echo ""

if [ $FAILED -eq 0 ]; then
  echo "✓ All automated tests PASSED"
  echo ""
  echo "Next Steps:"
  echo "  1. Run Test 4 from inside EC2:"
  echo "     aws ssm start-session --target $INSTANCE_ID --region $REGION"
  echo "  2. Inside session: bash verify_bonus_a_4_config_stores.sh"
  echo "  3. Use Session Manager to confirm app functionality"
  echo ""
  exit 0
else
  echo "✗ Some tests FAILED - review logs above"
  exit 1
fi
