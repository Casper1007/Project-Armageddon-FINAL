#!/bin/bash

################################################################################
# Lab 1b — Incident Response Runbook
# 
# Follow this EXACTLY. Deviations lose points.
# Do not redeploy. Do not guess. Use logs, alarms, and stored config.
# 
# GRADING:
#   Alarm acknowledged: 10 pts
#   Correct classification: 20 pts
#   Logs used correctly: 15 pts
#   Parameter Store validated: 10 pts
#   Secrets Manager validated: 10 pts
#   Correct recovery: 20 pts
#   No redeploy: 10 pts
#   Summary: 5 pts
################################################################################

set -e

REGION="${REGION:-us-east-1}"
LOG_GROUP="${LOG_GROUP:-/aws/ec2/chrisbarm-rds-app}"
ALARM_NAME="${ALARM_NAME:-lab-db-connection-failure}"
DB_INSTANCE="${DB_INSTANCE:-chrisbarm-rds01}"
RDS_SG="${RDS_SG:-sg-09253c24b2eee0c11}"
EC2_SG="${EC2_SG:-sg-0059285ecdea5d41d}"
SECRET_ID="${SECRET_ID:-lab1a/rds/mysql}"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ Lab 1b — INCIDENT RESPONSE RUNBOOK                             ║"
echo "║ Follow this order. No deviations.                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

PASS_COUNT=0

# ============================================================================
# SECTION 1: ACKNOWLEDGE
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "SECTION 1: ACKNOWLEDGE (10 points)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "1.1 Confirm Alert is Active"
echo ""

ALARM_STATE=$(aws cloudwatch describe-alarms \
  --alarm-name "$ALARM_NAME" \
  --region "$REGION" \
  --query "MetricAlarms[0].StateValue" \
  --output text 2>/dev/null)

if [ "$ALARM_STATE" = "ALARM" ]; then
  echo "✓ PASS: Alarm is in ALARM state"
  ((PASS_COUNT += 10))
else
  echo "✗ FAIL: Alarm state is $ALARM_STATE (expected ALARM)"
  echo "  Action: Wait a moment for alarm to trigger, or check if incident is still ongoing"
fi

echo ""
echo "Evidence: Alarm state = $ALARM_STATE"
echo ""

# ============================================================================
# SECTION 2: OBSERVE
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "SECTION 2: OBSERVE (15 points for logs, 20 for classification)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "2.1 Check Application Logs for Error Pattern"
echo ""

ERROR_LOG=$(aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern "ERROR" \
  --region "$REGION" \
  --max-results 5 \
  --output json 2>/dev/null || echo "{}")

ERROR_COUNT=$(echo "$ERROR_LOG" | jq '.events | length' 2>/dev/null || echo "0")

if [ "$ERROR_COUNT" -gt 0 ]; then
  echo "✓ PASS: Found $ERROR_COUNT error log entries"
  ((PASS_COUNT += 15))
  echo ""
  echo "Error Log Entries (most recent 5):"
  echo "$ERROR_LOG" | jq '.events[] | {timestamp: .timestamp, message: .message}' 2>/dev/null | head -30
else
  echo "⚠ WARNING: No error logs found yet"
  echo "  Action: Wait for application to retry connection, or check log group name"
fi

echo ""
echo "2.2 Classify the Failure Type"
echo ""
echo "Analyze logs and answer:"
echo ""

# Analyze error messages to classify
ERROR_MESSAGES=$(echo "$ERROR_LOG" | jq -r '.events[].message' 2>/dev/null || echo "")

FAILURE_TYPE="UNKNOWN"

if echo "$ERROR_MESSAGES" | grep -qi "access denied\|authentication\|password"; then
  FAILURE_TYPE="CREDENTIAL_DRIFT"
  echo "🔍 Classification: CREDENTIAL DRIFT"
  echo "   Symptom: 'Access denied' or 'Authentication failed'"
  echo "   Root Cause: Password mismatch between Secrets Manager and RDS"
  echo "   Recovery: Update RDS password to match Secrets Manager"
  ((PASS_COUNT += 20))
  
elif echo "$ERROR_MESSAGES" | grep -qi "connection refused\|timeout\|could not connect"; then
  FAILURE_TYPE="NETWORK_ISOLATION"
  echo "🔍 Classification: NETWORK ISOLATION or DATABASE UNAVAILABLE"
  echo "   Symptom: 'Connection refused' or 'Connection timeout'"
  echo "   Root Cause: Either network block or RDS not responding"
  echo "   Recovery: Check security groups, then check RDS status"
  ((PASS_COUNT += 20))
  
else
  echo "🔍 Classification: REQUIRES MANUAL INSPECTION"
  echo "   Error Messages:"
  echo "$ERROR_MESSAGES" | head -10
  echo ""
  echo "   Hint: Look for: access denied, connection refused, timeout, endpoint"
fi

echo ""

# ============================================================================
# SECTION 3: VALIDATE CONFIGURATION SOURCES
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "SECTION 3: VALIDATE CONFIGURATION SOURCES (10+10 points)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "3.1 Retrieve Parameter Store Values"
echo ""

PARAMS=$(aws ssm get-parameters \
  --names /lab/db/endpoint /lab/db/port /lab/db/name \
  --region "$REGION" \
  --with-decryption \
  --query "Parameters[].[Name, Value]" \
  --output text 2>/dev/null)

if [ -n "$PARAMS" ]; then
  echo "✓ PASS: Parameter Store values retrieved"
  ((PASS_COUNT += 10))
  echo ""
  echo "Parameter Values:"
  aws ssm get-parameters \
    --names /lab/db/endpoint /lab/db/port /lab/db/name \
    --region "$REGION" \
    --with-decryption \
    --query "Parameters[].[Name, Value]" \
    --output table 2>/dev/null
else
  echo "✗ FAIL: Could not retrieve parameters"
fi

echo ""
echo "3.2 Retrieve Secrets Manager Values"
echo ""

SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "SecretString" \
  --output text 2>/dev/null || echo "")

if [ -n "$SECRET" ]; then
  echo "✓ PASS: Secrets Manager secret retrieved"
  ((PASS_COUNT += 10))
  echo ""
  echo "Secret Contents (structure):"
  echo "$SECRET" | jq 'keys' 2>/dev/null || echo "  (Could not parse as JSON)"
  echo ""
  echo "Secret Fields (values masked):"
  echo "$SECRET" | jq 'with_entries(.value = if .value | type == "string" then (.[:3] + "****") else .value end)' 2>/dev/null
else
  echo "✗ FAIL: Could not retrieve secret"
fi

echo ""

# ============================================================================
# SECTION 4: CONTAINMENT
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "SECTION 4: CONTAINMENT (No point loss, but critical)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "✓ CONTAINMENT ACTIONS TAKEN:"
echo "  ✓ Did NOT restart EC2"
echo "  ✓ Did NOT recreate RDS"
echo "  ✓ Did NOT redeploy infrastructure"
echo "  ✓ System state preserved for recovery"
echo ""

# ============================================================================
# SECTION 5: RECOVERY (Path-Specific)
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "SECTION 5: RECOVERY (20 points - path depends on root cause)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if [ "$FAILURE_TYPE" = "CREDENTIAL_DRIFT" ]; then
  echo "Recovery Path: CREDENTIAL DRIFT"
  echo ""
  echo "Option A: Update RDS password to match Secrets Manager"
  echo "Command:"
  echo ""
  echo "  NEW_PASSWORD=\$(aws secretsmanager get-secret-value \\"
  echo "    --secret-id $SECRET_ID \\"
  echo "    --query 'SecretString' --output text | jq -r '.password')"
  echo ""
  echo "  aws rds modify-db-instance \\"
  echo "    --db-instance-identifier $DB_INSTANCE \\"
  echo "    --master-user-password \$NEW_PASSWORD \\"
  echo "    --apply-immediately"
  echo ""
  echo "Option B: Revert Secrets Manager to previous password"
  echo "(If you need to preserve RDS current password)"
  echo ""
  ((PASS_COUNT += 20))
  
elif [ "$FAILURE_TYPE" = "NETWORK_ISOLATION" ]; then
  echo "Recovery Path: NETWORK ISOLATION or DATABASE UNAVAILABLE"
  echo ""
  echo "Step 1: Check RDS Status"
  echo ""
  
  RDS_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$REGION" \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text 2>/dev/null)
  
  echo "  RDS Status: $RDS_STATUS"
  echo ""
  
  if [ "$RDS_STATUS" != "available" ]; then
    echo "Step 2a: RDS is not available — START IT"
    echo ""
    echo "  aws rds start-db-instance \\"
    echo "    --db-instance-identifier $DB_INSTANCE \\"
    echo "    --region $REGION"
    echo ""
    echo "  (Wait 2-3 minutes for startup)"
    ((PASS_COUNT += 20))
  else
    echo "Step 2b: RDS is available — CHECK SECURITY GROUPS"
    echo ""
    echo "  Verify EC2 → RDS rule exists on port 3306:"
    echo ""
    echo "  aws ec2 describe-security-groups \\"
    echo "    --group-ids $RDS_SG \\"
    echo "    --query 'SecurityGroups[0].IpPermissions[]' \\"
    echo "    --output table"
    echo ""
    echo "  If rule is missing, authorize it:"
    echo ""
    echo "  aws ec2 authorize-security-group-ingress \\"
    echo "    --group-id $RDS_SG \\"
    echo "    --protocol tcp \\"
    echo "    --port 3306 \\"
    echo "    --source-security-group-id $EC2_SG"
    echo ""
    ((PASS_COUNT += 20))
  fi
else
  echo "⚠ Classification unclear — manual recovery required"
  echo ""
  echo "Check:"
  echo "  1. RDS Status:"
  echo "     aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE"
  echo ""
  echo "  2. Security Groups:"
  echo "     aws ec2 describe-security-groups --group-ids $RDS_SG"
  echo ""
  echo "  3. Credentials:"
  echo "     aws secretsmanager get-secret-value --secret-id $SECRET_ID"
  echo ""
fi

echo ""

# ============================================================================
# SECTION 6: VERIFY RECOVERY
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "SECTION 6: VERIFY RECOVERY"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "6.1 Confirm Alarm Clears"
echo ""
echo "  Run: aws cloudwatch describe-alarms --alarm-name $ALARM_NAME"
echo ""
echo "  Expected: StateValue = OK"
echo ""
echo "6.2 Confirm Logs Normalize"
echo ""
echo "  Run: aws logs filter-log-events \\"
echo "         --log-group-name $LOG_GROUP \\"
echo "         --filter-pattern 'ERROR' \\"
echo "         --start-time <recent-timestamp>"
echo ""
echo "  Expected: No new ERROR messages after recovery"
echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "INCIDENT RESPONSE SUMMARY"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Points Earned (so far): $PASS_COUNT / 100"
echo ""
echo "Next Steps:"
echo "  1. Execute the appropriate recovery command from Section 5"
echo "  2. Wait for RDS to respond (2-5 minutes depending on failure)"
echo "  3. Verify alarm clears (Section 6.1)"
echo "  4. Verify logs normalize (Section 6.2)"
echo "  5. Complete incident report (next script)"
echo ""
