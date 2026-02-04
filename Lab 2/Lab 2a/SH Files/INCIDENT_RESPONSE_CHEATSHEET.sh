#!/bin/bash

################################################################################
# Lab 1b — Incident Response Quick Reference
# Keep this open during your incident response
################################################################################

cat > incident_response_cheatsheet.txt <<'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║ Lab 1b — INCIDENT RESPONSE CHEAT SHEET                                   ║
║ Keep this open in another terminal during incident response               ║
╚═══════════════════════════════════════════════════════════════════════════╝

═══════════════════════════════════════════════════════════════════════════════
STEP 1: SET YOUR VARIABLES (DO THIS FIRST)
═══════════════════════════════════════════════════════════════════════════════

export REGION="us-east-1"
export INSTANCE_ID="i-0968fd41f8aaa43eb"
export SECRET_ID="lab1a/rds/mysql"
export ALARM_NAME="lab-db-connection-failure"
export LOG_GROUP="/aws/ec2/chrisbarm-rds-app"
export DB_INSTANCE="chrisbarm-rds01"
export RDS_SG="sg-09253c24b2eee0c11"
export EC2_SG="sg-0059285ecdea5d41d"

═══════════════════════════════════════════════════════════════════════════════
STEP 2: INJECT AN INCIDENT
═══════════════════════════════════════════════════════════════════════════════

# Option A: Credential Drift
bash incident_inject_option_a.sh

# Option B: Network Isolation
bash incident_inject_option_b.sh

# Option C: Database Interruption
bash incident_inject_option_c.sh

═══════════════════════════════════════════════════════════════════════════════
STEP 3: RUN INCIDENT RUNBOOK (THIS IS THE GRADED PART)
═══════════════════════════════════════════════════════════════════════════════

bash incident_runbook.sh

# This will:
# - Check alarm state (10 pts)
# - Show error logs (15 pts)
# - Classify failure (20 pts)
# - Validate configs (20 pts)
# - Guide recovery (20 pts)
# - Score you out of 100

═══════════════════════════════════════════════════════════════════════════════
STEP 4: EXECUTE RECOVERY BASED ON RUNBOOK CLASSIFICATION
═══════════════════════════════════════════════════════════════════════════════

# If Credential Drift (Option A):
bash recover_option_a.sh

# If Network Isolation (Option B):
bash recover_option_b.sh

# If Database Interruption (Option C):
bash recover_option_c.sh

═══════════════════════════════════════════════════════════════════════════════
STEP 5: VERIFY RECOVERY
═══════════════════════════════════════════════════════════════════════════════

# Check Alarm State
aws cloudwatch describe-alarms \
  --alarm-name "$ALARM_NAME" \
  --region "$REGION" \
  --query "MetricAlarms[0].StateValue" \
  --output text

# Expected: OK (not ALARM)

# Check for New Errors
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern "ERROR" \
  --region "$REGION" | head -20

# Expected: Empty or only old errors

═══════════════════════════════════════════════════════════════════════════════
STEP 6: GENERATE INCIDENT REPORT
═══════════════════════════════════════════════════════════════════════════════

bash generate_incident_report.sh

# This creates: incident_report_YYYYMMDD_HHMMSS.md
# Edit it and answer all questions:
# - What failed?
# - How was it detected?
# - Root cause?
# - Time to recovery?
# - Recovery action?
# - Two preventive measures?
# - Five reflection questions (A-E)?

═══════════════════════════════════════════════════════════════════════════════
QUICK CLI REFERENCE (Paste these as needed)
═══════════════════════════════════════════════════════════════════════════════

# Watch logs in real-time
aws logs tail "$LOG_GROUP" --follow --region "$REGION"

# Check alarm (run every 30 seconds)
aws cloudwatch describe-alarms \
  --alarm-name "$ALARM_NAME" \
  --region "$REGION" | jq '.MetricAlarms[0] | {State: .StateValue, Updated: .StateUpdatedTime}'

# Get Parameter Store values
aws ssm get-parameters \
  --names /lab/db/endpoint /lab/db/port /lab/db/name \
  --region "$REGION" \
  --with-decryption \
  --query "Parameters[].[Name, Value]" \
  --output table

# Get Secrets Manager value
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query "SecretString" --output text | jq '.'

# Check RDS Status
aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE" \
  --region "$REGION" \
  --query "DBInstances[0].[DBInstanceIdentifier, DBInstanceStatus, DBInstanceArn]" \
  --output table

# Check RDS Security Group Rules
aws ec2 describe-security-groups \
  --group-ids "$RDS_SG" \
  --region "$REGION" \
  --query "SecurityGroups[0].IpPermissions" \
  --output table

═══════════════════════════════════════════════════════════════════════════════
GRADING BREAKDOWN (100 points)
═══════════════════════════════════════════════════════════════════════════════

[ 10 pts ] Alarm acknowledged (alarm is ALARM)
[ 20 pts ] Correct failure classification
[ 15 pts ] Logs used to diagnose
[ 10 pts ] Parameter Store validated
[ 10 pts ] Secrets Manager validated
[ 20 pts ] Correct recovery executed
[ 10 pts ] No redeploy, no hardcoding
[  5 pts ] Clear incident report
─────────────────
[ 100 pts ] TOTAL

═══════════════════════════════════════════════════════════════════════════════
THREE FAILURE SCENARIOS (You don't know which one will be injected)
═══════════════════════════════════════════════════════════════════════════════

[A] Credential Drift
    - Symptom: "Access denied for user 'admin'"
    - Cause: Password changed in Secrets Manager, not in RDS
    - Recovery: Update RDS password to match Secrets Manager
    - Time: ~2 minutes

[B] Network Isolation
    - Symptom: "Connection refused" or "Connection timeout"
    - Cause: EC2 security group removed from RDS inbound rule
    - Recovery: Re-authorize EC2 security group on port 3306
    - Time: ~1 minute

[C] Database Interruption
    - Symptom: "Cannot reach endpoint" or "Connection refused"
    - Cause: RDS instance is stopped
    - Recovery: Start RDS instance
    - Time: ~3-5 minutes

═══════════════════════════════════════════════════════════════════════════════
FIVE REFLECTION QUESTIONS (Answer all)
═══════════════════════════════════════════════════════════════════════════════

A) Why might Parameter Store still exist alongside Secrets Manager?
   HINT: Different data types, rotation policies, access patterns

B) What breaks first during secret rotation?
   HINT: Application vs. Database, timing mismatch

C) Why should alarms be based on symptoms instead of causes?
   HINT: Multiple causes → same symptom, observable vs. inferred

D) How does this lab reduce mean time to recovery (MTTR)?
   HINT: Configuration vs. redeploy, runbook, observability

E) What would you automate next?
   HINT: Detection, recovery, notification, escalation

═══════════════════════════════════════════════════════════════════════════════
REMEMBER
═══════════════════════════════════════════════════════════════════════════════

✓ Follow the runbook EXACTLY — deviations lose points
✓ Use logs and alarms — don't guess
✓ Use stored configuration — no hardcoding
✓ Do NOT redeploy EC2 or RDS
✓ Document everything — paste CLI output in incident report
✓ Answer reflection questions thoughtfully

This is operational maturity. You've got this.

═══════════════════════════════════════════════════════════════════════════════
EOF

cat incident_response_cheatsheet.txt
