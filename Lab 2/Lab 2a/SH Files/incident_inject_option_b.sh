#!/bin/bash

################################################################################
# Lab 1b — Incident Injection: Option B — Network Isolation
# 
# SCENARIO: EC2 security group removed from RDS inbound rule
# This simulates firewall rules being accidentally modified
# 
# RESULT: Connection times out (TCP timeout on port 3306)
# ERROR MESSAGE: Connection refused or timeout
################################################################################

set -e

REGION="${REGION:-us-east-1}"
RDS_SG="${RDS_SG:-sg-09253c24b2eee0c11}"
EC2_SG="${EC2_SG:-sg-0059285ecdea5d41d}"

echo "============================================"
echo "Incident Injection: Option B — Network Isolation"
echo "============================================"
echo ""
echo "SCENARIO: EC2 security group removed from RDS inbound rule."
echo "         Application cannot reach database on port 3306."
echo ""
echo "RESULT: Connection timeout."
echo "        Error: Connection refused / Connection timeout"
echo ""
echo "Region: $REGION"
echo "RDS Security Group: $RDS_SG"
echo "EC2 Security Group: $EC2_SG"
echo ""

# ============================================================================
# Step 1: Get current RDS security group rules
# ============================================================================
echo "[1/3] Examining current RDS security group rules..."
aws ec2 describe-security-groups \
  --group-ids "$RDS_SG" \
  --region "$REGION" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`3306\`]" \
  | jq '.'

# ============================================================================
# Step 2: Find and revoke the EC2→RDS ingress rule
# ============================================================================
echo ""
echo "[2/3] Revoking EC2 security group access to RDS..."

# Get the current rule details
RULE_DETAILS=$(aws ec2 describe-security-groups \
  --group-ids "$RDS_SG" \
  --region "$REGION" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`3306\`][0]" \
  --output json)

# Revoke the rule
aws ec2 revoke-security-group-ingress \
  --group-id "$RDS_SG" \
  --region "$REGION" \
  --protocol tcp \
  --port 3306 \
  --source-security-group-id "$EC2_SG" > /dev/null 2>&1 || true

echo "✓ EC2→RDS access revoked on port 3306"

# ============================================================================
# Step 3: Verify rule is gone
# ============================================================================
echo ""
echo "[3/3] Verifying network isolation..."
RULE_COUNT=$(aws ec2 describe-security-groups \
  --group-ids "$RDS_SG" \
  --region "$REGION" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`3306\`] | length(@)" \
  --output text)

if [ "$RULE_COUNT" -eq 0 ]; then
  echo "✓ Network isolation complete — no inbound rules on 3306"
else
  echo "⚠ Warning: Inbound rules may still exist"
fi

echo ""

# ============================================================================
# Result: Network isolation achieved
# ============================================================================
echo "============================================"
echo "INCIDENT INJECTED"
echo "============================================"
echo ""
echo "✓ EC2→RDS access: REVOKED"
echo "✗ Port 3306 rule: REMOVED from RDS security group"
echo ""
echo "Expected Result:"
echo "  - Application connection attempts will timeout"
echo "  - Error message: Connection refused / timeout"
echo "  - CloudWatch alarm will trigger"
echo "  - SNS notification sent"
echo ""
echo "Next: Monitor CloudWatch Logs and Alarms"
echo "  aws logs tail /aws/ec2/lab-rds-app --follow"
echo "  aws cloudwatch describe-alarms --alarm-name lab-db-connection-failure"
echo ""

# ============================================================================
# Save incident state for recovery
# ============================================================================
INCIDENT_STATE_FILE="incident_state_option_b.json"
cat > "$INCIDENT_STATE_FILE" <<EOF
{
  "scenario": "network_isolation",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "$REGION",
  "rds_security_group": "$RDS_SG",
  "ec2_security_group": "$EC2_SG",
  "port": 3306,
  "action_taken": "revoke_ingress",
  "notes": "Revoked EC2 security group access to RDS on port 3306. Connection will timeout."
}
EOF

echo "Incident state saved to: $INCIDENT_STATE_FILE"
