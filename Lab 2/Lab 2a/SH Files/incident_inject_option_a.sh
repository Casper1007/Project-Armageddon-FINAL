#!/bin/bash

################################################################################
# Lab 1b — Incident Injection: Option A — Secret Drift
# 
# SCENARIO: DB password changed in Secrets Manager but NOT in RDS
# This simulates a failed secret rotation or credential drift
# 
# RESULT: Application cannot authenticate to RDS
# ERROR MESSAGE: Access denied for user 'admin'@'<ip>'
################################################################################

set -e

REGION="${REGION:-us-east-1}"
SECRET_ID="${SECRET_ID:-lab1a/rds/mysql}"
DB_INSTANCE="${DB_INSTANCE:-chrisbarm-rds01}"

echo "============================================"
echo "Incident Injection: Option A — Secret Drift"
echo "============================================"
echo ""
echo "SCENARIO: Database password changed in Secrets Manager"
echo "         but NOT updated in actual RDS instance."
echo ""
echo "RESULT: Application cannot authenticate."
echo "        Error: Access denied for user 'admin'@'<ip>'"
echo ""
echo "Region: $REGION"
echo "Secret ID: $SECRET_ID"
echo "DB Instance: $DB_INSTANCE"
echo ""

# ============================================================================
# Step 1: Get current secret
# ============================================================================
echo "[1/3] Retrieving current secret value..."
CURRENT_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "SecretString" \
  --output text)

echo "Current secret retrieved"

# ============================================================================
# Step 2: Generate new password
# ============================================================================
echo ""
echo "[2/3] Generating new password..."
# Use only alphanumeric characters to satisfy RDS password constraints.
NEW_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
echo "Generated new password: ${NEW_PASSWORD:0:8}****"

# ============================================================================
# Step 3: Update Secrets Manager with new password
# ============================================================================
echo ""
echo "[3/3] Updating Secrets Manager with new password..."
UPDATED_SECRET=$(echo "$CURRENT_SECRET" | jq --arg pwd "$NEW_PASSWORD" '.password = $pwd')

aws secretsmanager put-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --secret-string "$UPDATED_SECRET" > /dev/null

echo "✓ Secrets Manager updated with new password"
echo ""

# ============================================================================
# Result: RDS still has old password
# ============================================================================
echo "============================================"
echo "INCIDENT INJECTED"
echo "============================================"
echo ""
echo "✓ Secrets Manager password: CHANGED"
echo "✗ RDS password: UNCHANGED (still using old password)"
echo ""
echo "Expected Result:"
echo "  - Application will fail to authenticate"
echo "  - Error message: Access denied for user 'admin'@'<ip>'"
echo "  - CloudWatch alarm will trigger"
echo "  - SNS notification sent"
echo ""
echo "Next: Monitor CloudWatch Logs and Alarms"
echo "  aws logs tail /aws/ec2/lab-rds-app --follow"
echo "  aws cloudwatch describe-alarms --alarm-names lab-db-connection-failure"
echo ""

# ============================================================================
# Save incident state for recovery
# ============================================================================
INCIDENT_STATE_FILE="incident_state_option_a.json"
cat > "$INCIDENT_STATE_FILE" <<EOF
{
  "scenario": "secret_drift",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "$REGION",
  "secret_id": "$SECRET_ID",
  "db_instance": "$DB_INSTANCE",
  "old_password": "$(echo $CURRENT_SECRET | jq -r '.password')",
  "new_password": "$NEW_PASSWORD",
  "rds_actual_password": "$(echo $CURRENT_SECRET | jq -r '.password')",
  "notes": "RDS still has old password. Secrets Manager has new password. Authentication will fail."
}
EOF

echo "Incident state saved to: $INCIDENT_STATE_FILE"
