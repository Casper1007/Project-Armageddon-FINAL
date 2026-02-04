#!/bin/bash

################################################################################
# Lab 1b — Incident Recovery: Option B — Network Isolation
# 
# Recovery for scenario where EC2 security group was removed
# from RDS inbound rule.
# 
# Recovery Action: Restore EC2 → RDS security group rule
################################################################################

set -e

REGION="${REGION:-us-east-1}"
RDS_SG="${RDS_SG:-sg-09253c24b2eee0c11}"
EC2_SG="${EC2_SG:-sg-0059285ecdea5d41d}"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ Lab 1b — RECOVERY: Option B — Network Isolation               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Recovery Action: Restore EC2 → RDS security group rule on port 3306"
echo ""
echo "Region: $REGION"
echo "RDS Security Group: $RDS_SG"
echo "EC2 Security Group: $EC2_SG"
echo ""

# ============================================================================
# Step 1: Check current RDS security group state
# ============================================================================
echo "[1/3] Checking RDS security group rules..."
echo ""

RULE_EXISTS=$(aws ec2 describe-security-groups \
  --group-ids "$RDS_SG" \
  --region "$REGION" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`3306\` && UserIdGroupPairs[?GroupId=='$EC2_SG']] | length(@)" \
  --output text)

if [ "$RULE_EXISTS" -gt 0 ]; then
  echo "ℹ Rule already exists: EC2 → RDS on port 3306"
  echo "  No action needed"
else
  echo "✗ Rule missing: EC2 → RDS on port 3306"
  echo "  Action: Adding rule..."
  echo ""
  
  # ============================================================================
  # Step 2: Authorize EC2 security group access
  # ============================================================================
  echo "[2/3] Authorizing EC2 security group access to RDS..."
  echo ""
  
  aws ec2 authorize-security-group-ingress \
    --group-id "$RDS_SG" \
    --protocol tcp \
    --port 3306 \
    --source-security-group-id "$EC2_SG" \
    --region "$REGION" > /dev/null
  
  echo "✓ Security group rule authorized"
  echo ""
fi

# ============================================================================
# Step 3: Verify rule is now present
# ============================================================================
echo "[3/3] Verifying rule..."
echo ""

RULE_CHECK=$(aws ec2 describe-security-groups \
  --group-ids "$RDS_SG" \
  --region "$REGION" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`3306\`]" \
  --output json)

echo "✓ Current RDS inbound rules on port 3306:"
echo "$RULE_CHECK" | jq '.'

echo ""

# ============================================================================
# Recovery verification
# ============================================================================
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ RECOVERY COMPLETE                                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "✓ EC2 security group access to RDS restored"
echo ""
echo "Next Steps:"
echo "  1. Application will retry connection automatically"
echo "  2. Connection should succeed within 1-2 seconds"
echo ""
echo "  3. Monitor alarm state:"
echo "     aws cloudwatch describe-alarms --alarm-name lab-db-connection-failure"
echo ""
echo "  4. Check logs for recovery:"
echo "     aws logs tail /aws/ec2/chrisbarm-rds-app --follow"
echo ""
echo "  5. Expected: Alarm transitions to OK within 5 minutes"
echo ""

# Save recovery completion time
echo "{\"recovery_type\": \"network_isolation\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"status\": \"completed\"}" > recovery_complete.json
