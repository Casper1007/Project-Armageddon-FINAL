#!/bin/bash

################################################################################
# Lab 1b — Incident Injection: Option C — Database Interruption
# 
# SCENARIO: RDS instance is stopped
# This simulates database maintenance that wasn't communicated
# 
# RESULT: Cannot reach database at all
# ERROR MESSAGE: Connection refused or endpoint unreachable
################################################################################

set -e

REGION="${REGION:-us-east-1}"
DB_INSTANCE="${DB_INSTANCE:-chrisbarm-rds01}"

echo "============================================"
echo "Incident Injection: Option C — Database Interruption"
echo "============================================"
echo ""
echo "SCENARIO: RDS instance stopped."
echo "         Application cannot reach database endpoint."
echo ""
echo "RESULT: Connection refused."
echo "        Error: Cannot reach database endpoint"
echo ""
echo "Region: $REGION"
echo "DB Instance: $DB_INSTANCE"
echo ""

# ============================================================================
# Step 1: Check current RDS status
# ============================================================================
echo "[1/3] Checking current RDS status..."
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE" \
  --region "$REGION" \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text)

echo "Current RDS status: $RDS_STATUS"

# ============================================================================
# Step 2: Stop the RDS instance
# ============================================================================
echo ""
echo "[2/3] Stopping RDS instance..."
aws rds stop-db-instance \
  --db-instance-identifier "$DB_INSTANCE" \
  --region "$REGION" > /dev/null

echo "✓ Stop command sent to RDS"

# ============================================================================
# Step 3: Wait and verify stopping
# ============================================================================
echo ""
echo "[3/3] Waiting for RDS to stop (this takes ~30 seconds)..."

for i in {1..6}; do
  sleep 5
  CURRENT_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$REGION" \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text)
  
  echo "  Status: $CURRENT_STATUS"
  
  if [ "$CURRENT_STATUS" = "stopped" ]; then
    echo "✓ RDS is now stopped"
    break
  fi
done

echo ""

# ============================================================================
# Result: RDS is stopped
# ============================================================================
echo "============================================"
echo "INCIDENT INJECTED"
echo "============================================"
echo ""
echo "✓ RDS Instance: STOPPED"
echo "✗ Endpoint reachable: NO"
echo ""
echo "Expected Result:"
echo "  - Application connection attempts will fail immediately"
echo "  - Error message: Cannot connect to endpoint"
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
INCIDENT_STATE_FILE="incident_state_option_c.json"
cat > "$INCIDENT_STATE_FILE" <<EOF
{
  "scenario": "database_interruption",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "$REGION",
  "db_instance": "$DB_INSTANCE",
  "action_taken": "stop_db_instance",
  "notes": "RDS instance stopped. Application cannot reach database endpoint. Restart required for recovery."
}
EOF

echo "Incident state saved to: $INCIDENT_STATE_FILE"
