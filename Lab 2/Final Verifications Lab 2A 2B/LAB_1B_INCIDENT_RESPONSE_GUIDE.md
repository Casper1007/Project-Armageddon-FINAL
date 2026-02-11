# Lab 1b — Incident Response: Complete Walkthrough

> "Anyone can deploy. Professionals recover."

---

## Overview

This lab teaches operational maturity: **diagnosing failures using logs and alarms, then recovering using stored configuration — without redeploys**.

You have three failure scenarios. You don't know which one will be injected. Your job is to:
1. ✓ Acknowledge the alarm
2. ✓ Observe the logs
3. ✓ Classify the failure
4. ✓ Validate configuration sources
5. ✓ Execute recovery
6. ✓ Verify resolution

---

## Scripts Provided

| Script | Purpose |
|--------|---------|
| `incident_inject_option_a.sh` | Inject credential drift scenario |
| `incident_inject_option_b.sh` | Inject network isolation scenario |
| `incident_inject_option_c.sh` | Inject database interruption scenario |
| `incident_runbook.sh` | Run mandatory response steps (generates points) |
| `recover_option_a.sh` | Recovery for credential drift |
| `recover_option_b.sh` | Recovery for network isolation |
| `recover_option_c.sh` | Recovery for database interruption |
| `generate_incident_report.sh` | Create incident report template |

---

## Prerequisites

```bash
# Set these environment variables
export REGION="us-east-1"
export INSTANCE_ID="i-0968fd41f8aaa43eb"
export SECRET_ID="lab1a/rds/mysql"
export ALARM_NAME="lab-db-connection-failure"
export LOG_GROUP="/aws/ec2/chrisbarm-rds-app"
export DB_INSTANCE="chrisbarm-rds01"
export RDS_SG="sg-09253c24b2eee0c11"
export EC2_SG="sg-0059285ecdea5d41d"
```

---

## WORKFLOW: Incident Response From Start to Finish

### Phase 1: INJECT AN INCIDENT

Choose one scenario to simulate:

#### Option A: Secret Drift (Credential Mismatch)
```bash
bash incident_inject_option_a.sh
```
**What Happens:**
- Password changed in Secrets Manager
- RDS still has old password
- Application authentication fails
- Error: "Access denied for user 'admin'"

---

#### Option B: Network Isolation (SG Rule Removed)
```bash
bash incident_inject_option_b.sh
```
**What Happens:**
- EC2 → RDS security group rule removed
- Application connection times out
- Error: "Connection refused"

---

#### Option C: Database Interruption (RDS Stopped)
```bash
bash incident_inject_option_c.sh
```
**What Happens:**
- RDS instance is stopped
- Application cannot reach endpoint
- Error: "Connection refused" or "Endpoint unreachable"

---

### Phase 2: MONITOR THE INCIDENT

After injection, watch what happens:

```bash
# Terminal 1: Watch CloudWatch Logs
aws logs tail "$LOG_GROUP" --follow

# Terminal 2: Watch CloudWatch Alarm
watch -n 5 "aws cloudwatch describe-alarms --alarm-name $ALARM_NAME --query 'MetricAlarms[0].{State:StateValue,Timestamp:StateUpdatedTime}'"

# Terminal 3: Watch SNS Notifications
# Check your email for SNS alert
```

**Expected Timeline:**
- Application starts failing immediately
- CloudWatch Logs show ERROR messages (5-30 seconds)
- CloudWatch Alarm triggers (within 5 minutes)
- SNS email notification sent

---

### Phase 3: EXECUTE INCIDENT RESPONSE RUNBOOK

**THIS IS THE GRADED PART. FOLLOW IT EXACTLY.**

```bash
bash incident_runbook.sh
```

**What It Does:**
1. Confirms alarm is in ALARM state (10 pts)
2. Shows you error logs (15 pts)
3. Classifies the failure type (20 pts)
4. Validates Parameter Store (10 pts)
5. Validates Secrets Manager (10 pts)
6. Guides you through recovery steps (20 pts)
7. Verifies you didn't redeploy (10 pts)

**Output:**
- Your current score (out of 100)
- Specific recovery commands for YOUR failure type
- Instructions for next steps

---

### Phase 4: EXECUTE RECOVERY

Based on what the runbook identified, run the appropriate recovery script:

#### Recovery A: Credential Drift
```bash
bash recover_option_a.sh
```
**What It Does:**
- Retrieves password from Secrets Manager
- Updates RDS to use that password
- Waits for RDS to apply changes
- Verifies success

---

#### Recovery B: Network Isolation
```bash
bash recover_option_b.sh
```
**What It Does:**
- Checks RDS security group state
- Re-authorizes EC2 → RDS on port 3306
- Verifies rule is now present

---

#### Recovery C: Database Interruption
```bash
bash recover_option_c.sh
```
**What It Does:**
- Checks RDS status
- Starts RDS if stopped
- Waits for startup completion (2-5 min)
- Verifies endpoint is available

---

### Phase 5: VERIFY RECOVERY

```bash
# Verify alarm clears
aws cloudwatch describe-alarms \
  --alarm-name "$ALARM_NAME" \
  --query "MetricAlarms[0].StateValue"

# Expected: OK

# Verify no new errors
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern "ERROR" \
  --start-time "$(date -d '5 minutes ago' +%s)000"

# Expected: Empty or only old errors

# Test application
curl http://<EC2_IP>/list

# Expected: HTTP 200 with data
```

---

### Phase 6: DOCUMENT THE INCIDENT

```bash
bash generate_incident_report.sh
```

**Complete these sections:**

1. **What Failed?**
   - Be specific: "Application cannot authenticate to RDS"
   - Not vague: "System is broken"

2. **How Was It Detected?**
   - Alarm triggered
   - SNS email received
   - Logs showed errors

3. **Root Cause**
   - Which scenario was it?
   - What evidence proves it?

4. **Time to Recovery**
   - When did alarm trigger?
   - When did you start recovery?
   - When was it fixed?

5. **Recovery Action**
   - Exactly what did you do?
   - Paste CLI output as proof

6. **Proof of Recovery**
   - Alarm state is OK
   - Application returns data
   - No new errors in logs

7. **Preventive Measures**
   - One way to SPEED recovery
   - One way to PREVENT recurrence

8. **Reflection Questions**
   - Answer A, B, C, D, E (see below)

---

## REFLECTION QUESTIONS (Answer These)

### A) Why might Parameter Store still exist alongside Secrets Manager?

**Think About:**
- Parameter Store is better for non-rotating configuration
- Secrets Manager is better for rotating credentials
- Sometimes you want config and secrets in different places
- Different teams may manage them

**Example Answer:**
> Parameter Store is used for infrastructure configuration (endpoints, ports, non-sensitive values) that changes infrequently. Secrets Manager is used for credentials that may rotate. By separating them, we can have different retention policies, audit trails, and access controls for each.

---

### B) What breaks first during secret rotation?

**Think About:**
- Application uses old credential
- Secret changes in Secrets Manager
- RDS hasn't been updated yet
- Or: Application hasn't reloaded yet
- Authentication fails

**Example Answer:**
> If a credential is rotated, the application breaks first if it doesn't reload the new value from Secrets Manager. The database still accepts the old credential for a brief moment, but the application tries to use the new credential that hasn't been applied to the database yet. This is credential drift, which is exactly what Option A simulates.

---

### C) Why should alarms be based on symptoms instead of causes?

**Think About:**
- You alarm on "DB connection errors" (symptom)
- Not on "RDS password changed" (cause)
- Why? Because multiple causes create the same symptom
- Symptoms are observable; causes require diagnosis

**Example Answer:**
> Alarms should alert on the business impact (no database connection = application fails) rather than internal events. If we alarm on "Secrets Manager secret updated," we get false positives (secret may have been auto-rotated correctly). If we alarm on "3+ connection errors in 5 minutes," we catch all failure modes: credential drift, network blocks, database stops. Symptoms are what users experience.

---

### D) How does this lab reduce mean time to recovery (MTTR)?

**Think About:**
- Without stored config, you'd redeploy everything
- With Parameter Store + Secrets Manager, you change values
- Runbook gives you a process so you don't waste time guessing
- Logs tell you exactly what failed
- Alarms tell you immediately

**Example Answer:**
> This lab reduces MTTR from 30+ minutes (redeploy, test) to 5 minutes (diagnose, recover, verify) by:
> 1. Providing clear observability (logs + alarms)
> 2. Storing configuration centrally (Parameter Store + Secrets Manager)
> 3. Following a structured runbook so we don't waste time on false leads
> 4. Using AWS CLI to verify instead of guessing

---

### E) What would you automate next?

**Think About:**
- What parts of recovery could run without human intervention?
- Detecting failure patterns
- Triggering recovery automatically
- Notifying the right people

**Example Answer:**
> I would automate failure detection by:
> 1. Creating a Lambda function triggered by the CloudWatch Alarm
> 2. Lambda runs the runbook script to classify failure
> 3. Based on classification, Lambda runs the appropriate recovery script
> 4. Lambda sends detailed SNS notification with recovery confirmation
> This would reduce MTTR to 30 seconds and prevent accidental misdiagnosis.

---

## GRADING RUBRIC (100 Points Total)

| Category | Points | How to Earn |
|----------|--------|-----------|
| Alarm acknowledged (Section 1.1) | 10 | Run runbook, show alarm is ALARM |
| Correct failure classification (Section 2.2) | 20 | Runbook identifies if A/B/C correctly |
| Logs used properly (Section 2.1) | 15 | Show ERROR messages from CloudWatch |
| Parameter Store validated (Section 3.1) | 10 | Run `aws ssm get-parameters` |
| Secrets Manager validated (Section 3.2) | 10 | Run `aws secretsmanager get-secret-value` |
| Correct recovery action (Section 5) | 20 | Execute correct recovery script, show success |
| No redeploy / no hardcoding (Section 4) | 10 | Prove you used stored config, no new EC2/RDS |
| Clear incident report (Section 6) | 5 | Complete all sections with evidence |
| **TOTAL** | **100** | |

---

## Common Issues & Troubleshooting

### "Runbook says UNKNOWN classification"

**Problem:** Logs don't contain clear error messages

**Solution:**
- Wait 1-2 minutes for application to retry
- Check if log group name is correct
- Manually grep logs: `aws logs tail $LOG_GROUP --follow`

### "Alarm never fires"

**Problem:** No alarm in the system

**Solution:**
- Verify alarm exists: `aws cloudwatch describe-alarms --alarm-name $ALARM_NAME`
- If missing, Lab 1b infrastructure not complete
- Check that application is logging connection failures

### "Recovery succeeded but alarm didn't clear"

**Problem:** Alarm still ALARM after fix

**Solution:**
- Alarms clear after 5 minutes of normal operation
- Application must retry successfully
- Check logs for new errors: `aws logs tail $LOG_GROUP --follow`

### "Application still fails after recovery"

**Problem:** Recovery script ran but application still can't connect

**Solution:**
- Verify recovery output said "✓"
- Check RDS status: `aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE`
- For credential drift: Verify password matches: `aws secretsmanager get-secret-value --secret-id $SECRET_ID | jq '.SecretString'`
- For network: Verify SG rule: `aws ec2 describe-security-groups --group-ids $RDS_SG`

---

## Example: Full Incident Response (Option A — Credential Drift)

### Step 1: Inject Incident
```bash
$ bash incident_inject_option_a.sh
[INFO] Secret changed in Secrets Manager, RDS password unchanged
[✓] Incident injected
```

### Step 2: Watch It Break
```bash
$ aws logs tail /aws/ec2/chrisbarm-rds-app --follow
[ERROR] Access denied for user 'admin'@'10.0.1.15'
[ERROR] DB connection failed, retrying...
```

### Step 3: Run Runbook
```bash
$ bash incident_runbook.sh
[✓] Alarm is ALARM (10 pts)
[✓] Found ERROR logs (15 pts)
[✓] Classification: CREDENTIAL_DRIFT (20 pts)
[✓] Parameter Store values retrieved (10 pts)
[✓] Secrets Manager secret retrieved (10 pts)
Points: 65/100
Recovery: Update RDS password...
```

### Step 4: Execute Recovery
```bash
$ bash recover_option_a.sh
[✓] Password retrieved from Secrets Manager
[✓] RDS password updated
[✓] RDS is available with new password
```

### Step 5: Verify
```bash
$ aws cloudwatch describe-alarms --alarm-name lab-db-connection-failure
StateValue: OK  ← Alarm cleared!

$ curl http://10.0.1.15/list
{"data": [...]}  ← Application works!
```

### Step 6: Report
```bash
$ bash generate_incident_report.sh
[✓] Report template created: incident_report_20260120_143022.md

Edit and submit with:
- What failed: Credential drift
- Root cause: Password changed in Secrets Manager but not in RDS
- Time to recovery: 5 minutes
- Recovery action: Updated RDS password
- Preventive measure: Automated drift detection every 5 minutes
- Reflection answers: (complete all)
```

---

## Success Criteria

You have completed Lab 1b when:

✅ Runbook executes without errors  
✅ Correct failure type identified from logs  
✅ Recovery script executes without redeploy  
✅ Alarm transitions to OK after recovery  
✅ Application returns HTTP 200  
✅ Incident report completed with all sections  
✅ Reflection questions answered thoughtfully  

---

## What This Proves

By completing Lab 1b, you demonstrate:

- ✓ **Observability skills** — Can read and interpret logs/alarms
- ✓ **Diagnostic skills** — Can classify failures without guessing
- ✓ **Configuration management** — Can use Parameter Store + Secrets Manager
- ✓ **Operational discipline** — Follow runbooks, no cowboy recovery
- ✓ **Cloud-native thinking** — Recover with configuration, not redeploys
- ✓ **On-call readiness** — Can operate systems under pressure

This is **mid-level engineer** capability.

---

## Timeline

| Phase | Time | What Happens |
|-------|------|--------------|
| Inject | 1 min | Incident created |
| Break | 1-2 min | Application starts failing |
| Alarm | 5 min | CloudWatch alarm triggers |
| Runbook | 5 min | Classify and guide |
| Recover | 5-10 min | Run recovery script |
| Verify | 5 min | Confirm alarm clears |
| Report | 10 min | Document incident |
| **Total** | **~40 minutes** | |

---

End of Lab 1b Incident Response Guide
