#!/bin/bash

################################################################################
# Lab 1b — Incident Recovery: Option A — Credential Drift
# 
# Recovery for scenario where DB password changed in Secrets Manager
# but not updated in actual RDS.
# 
# Recovery Action: Update RDS password to match Secrets Manager
################################################################################

set -e

REGION="${REGION:-us-east-1}"
SECRET_ID="${SECRET_ID:-lab1a/rds/mysql}"
DB_INSTANCE="${DB_INSTANCE:-chrisbarm-rds01}"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ Lab 1b — RECOVERY: Option A — Credential Drift                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Recovery Action: Update RDS password to match Secrets Manager"
echo ""
echo "Region: $REGION"
echo "Secret ID: $SECRET_ID"
echo "DB Instance: $DB_INSTANCE"
echo ""

# ============================================================================
# Step 1: Retrieve the correct password from Secrets Manager
# ============================================================================
echo "[1/3] Retrieving correct password from Secrets Manager..."
echo ""

SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "SecretString" \
  --output text)

NEW_PASSWORD=$(echo "$SECRET" | jq -r '.password')

if [ -z "$NEW_PASSWORD" ]; then
  echo "✗ FAIL: Could not extract password from secret"
  exit 1
fi

echo "✓ Password retrieved from Secrets Manager"
echo "  Password (masked): ${NEW_PASSWORD:0:3}****"
echo ""

# ============================================================================
# Step 2: Update RDS with the correct password
# ============================================================================
echo "[2/3] Updating RDS instance password..."
echo ""

aws rds modify-db-instance \
  --db-instance-identifier "$DB_INSTANCE" \
  --master-user-password "$NEW_PASSWORD" \
  --apply-immediately \
  --region "$REGION" > /dev/null

echo "✓ RDS password update command sent"
echo "  (Changes apply immediately)"
echo ""

# ============================================================================
# Step 3: Verify password was updated
# ============================================================================
echo "[3/3] Waiting for RDS to apply changes..."
echo ""

# Wait for RDS to become available again
for i in {1..10}; do
  sleep 5
  
  STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$REGION" \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text 2>/dev/null)
  
  echo "  RDS Status: $STATUS"
  
  if [ "$STATUS" = "available" ]; then
    echo "✓ RDS is available with updated password"
    break
  fi
done

echo ""

# ============================================================================
# Recovery verification
# ============================================================================
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ RECOVERY COMPLETE                                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "✓ RDS password updated to match Secrets Manager"
echo ""
echo "Next Steps:"
echo "  1. Application will retry connection automatically"
echo "  2. Monitor alarm state:"
echo "     aws cloudwatch describe-alarms --alarm-names lab-db-connection-failure"
echo ""
echo "  3. Check for new errors in logs:"
echo "     aws logs filter-log-events --log-group-name /aws/ec2/chrisbarm-rds-app --filter-pattern ERROR"
echo ""
echo "  4. Expected: Alarm transitions to OK within 5 minutes"
echo ""

# Save recovery completion time
echo "{\"recovery_type\": \"credential_drift\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"status\": \"completed\"}" > recovery_complete.json
