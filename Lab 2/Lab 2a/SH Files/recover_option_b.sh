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

RECOVERY_SG_IDS=""

# Prefer values recorded during injection
if [ -f "incident_state_option_b.json" ]; then
  RDS_SG=$(jq -r '.rds_security_group // empty' incident_state_option_b.json 2>/dev/null)
  RECOVERY_SG_IDS=$(jq -r '.revoked_group_ids[]?' incident_state_option_b.json 2>/dev/null | tr -d '\r')
fi

# Resolve RDS security group if still invalid
if [ -z "$RDS_SG" ] || ! aws ec2 describe-security-groups --group-ids "$RDS_SG" --region "$REGION" --output text >/dev/null 2>&1; then
  RDS_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=chrisbarm-rds-sg01" \
    --region "$REGION" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null)
fi

if [ -z "$RECOVERY_SG_IDS" ]; then
  if [ -z "$EC2_SG" ] || [ "$EC2_SG" = "None" ]; then
    EC2_SG=$(aws ec2 describe-security-groups \
      --group-ids "$RDS_SG" \
      --region "$REGION" \
      --query "SecurityGroups[0].IpPermissions[?FromPort==\`3306\`].UserIdGroupPairs[0].GroupId | [0]" \
      --output text 2>/dev/null)
  fi
  RECOVERY_SG_IDS="$EC2_SG"
fi

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
  
  if [ -n "$RECOVERY_SG_IDS" ]; then
    while read -r SG_ID; do
      if [[ -z "$SG_ID" || "$SG_ID" != sg-* ]]; then
        continue
      fi
      aws ec2 authorize-security-group-ingress \
        --group-id "$RDS_SG" \
        --protocol tcp \
        --port 3306 \
        --source-group "$SG_ID" \
        --region "$REGION" > /dev/null || true
    done <<< "$RECOVERY_SG_IDS"
    echo "✓ Security group rule authorized"
  else
    echo "⚠ Warning: EC2 security group not found; cannot add rule"
  fi
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
echo "     aws cloudwatch describe-alarms --alarm-names lab-db-connection-failure"
echo ""
echo "  4. Check logs for recovery:"
echo "     aws logs tail /aws/ec2/chrisbarm-rds-app --follow"
echo ""
echo "  5. Expected: Alarm transitions to OK within 5 minutes"
echo ""

# Save recovery completion time
echo "{\"recovery_type\": \"network_isolation\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"status\": \"completed\"}" > recovery_complete.json
