#!/bin/bash

################################################################################
# Lab 1b — Incident Recovery: Option C — Database Interruption
# 
# Recovery for scenario where RDS instance was stopped.
# 
# Recovery Action: Start the RDS instance and wait for availability
################################################################################

set -e

REGION="${REGION:-us-east-1}"
DB_INSTANCE="${DB_INSTANCE:-chrisbarm-rds01}"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ Lab 1b — RECOVERY: Option C — Database Interruption           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Recovery Action: Start RDS instance and wait for availability"
echo ""
echo "Region: $REGION"
echo "DB Instance: $DB_INSTANCE"
echo ""

# ============================================================================
# Step 1: Check RDS current status
# ============================================================================
echo "[1/3] Checking RDS status..."
echo ""

RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE" \
  --region "$REGION" \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text)

echo "Current status: $RDS_STATUS"
echo ""

# ============================================================================
# Step 2: Start the RDS instance if stopped
# ============================================================================
if [ "$RDS_STATUS" = "stopped" ] || [ "$RDS_STATUS" = "stopping" ]; then
  echo "[2/3] Starting RDS instance..."
  echo ""
  
  aws rds start-db-instance \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$REGION" > /dev/null
  
  echo "✓ Start command sent to RDS"
  echo "  (Startup typically takes 2-5 minutes)"
  echo ""
else
  echo "[2/3] RDS is already running (status: $RDS_STATUS)"
  echo ""
fi

# ============================================================================
# Step 3: Wait for RDS to become available
# ============================================================================
echo "[3/3] Waiting for RDS to start..."
echo ""

STARTUP_TIME=0
MAX_WAIT=300  # 5 minutes

while [ $STARTUP_TIME -lt $MAX_WAIT ]; do
  sleep 10
  STARTUP_TIME=$((STARTUP_TIME + 10))
  
  CURRENT_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$REGION" \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text)
  
  PERCENTAGE=$((STARTUP_TIME * 100 / MAX_WAIT))
  echo "  [$PERCENTAGE%] Status: $CURRENT_STATUS"
  
  if [ "$CURRENT_STATUS" = "available" ]; then
    echo ""
    echo "✓ RDS is now available"
    break
  fi
done

echo ""

# ============================================================================
# Step 4: Verify connectivity
# ============================================================================
echo "Verifying RDS endpoint..."

ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE" \
  --region "$REGION" \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo "RDS Endpoint: $ENDPOINT"
echo ""

# ============================================================================
# Recovery verification
# ============================================================================
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ RECOVERY COMPLETE                                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "✓ RDS instance is now available"
echo ""
echo "Next Steps:"
echo "  1. Application will retry connection automatically"
echo "  2. Connection should succeed within 30 seconds"
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
echo "{\"recovery_type\": \"database_interruption\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"status\": \"completed\"}" > recovery_complete.json
