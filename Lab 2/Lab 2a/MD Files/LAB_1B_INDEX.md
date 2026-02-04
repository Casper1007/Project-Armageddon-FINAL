# Lab 1b — Complete Index

## Start Here

1. **Read:** [LAB_1B_IMPLEMENTATION_SUMMARY.md](LAB_1B_IMPLEMENTATION_SUMMARY.md)
   - Overview of all 10 scripts
   - Workflow explanation
   - Grading rubric
   - Answer the 5 reflection questions

2. **Review:** [LAB_1B_INCIDENT_RESPONSE_GUIDE.md](LAB_1B_INCIDENT_RESPONSE_GUIDE.md)
   - Complete step-by-step walkthrough
   - Example incident response
   - Troubleshooting guide
   - Reflection question guidance

3. **Quick Reference:** [INCIDENT_RESPONSE_CHEATSHEET.sh](INCIDENT_RESPONSE_CHEATSHEET.sh)
   - One-page quick reference
   - All CLI commands
   - Three failure scenarios
   - Keep open during incident response

---

## Scripts by Purpose

### Phase 1: Inject Incident (Choose One)

| Script | Scenario | Error | Time |
|--------|----------|-------|------|
| [incident_inject_option_a.sh](incident_inject_option_a.sh) | Credential Drift | "Access denied for user" | 1 min |
| [incident_inject_option_b.sh](incident_inject_option_b.sh) | Network Isolation | "Connection refused" | 1 min |
| [incident_inject_option_c.sh](incident_inject_option_c.sh) | Database Interruption | "Endpoint unreachable" | 1 min |

### Phase 2: Run Incident Runbook (Mandatory - Graded)

| Script | Purpose | Points | Time |
|--------|---------|--------|------|
| [incident_runbook.sh](incident_runbook.sh) | Complete incident response with live scoring | 65-75 | 5 min |

### Phase 3: Execute Recovery (Choose Based on Classification)

| Script | Fixes | Time |
|--------|-------|------|
| [recover_option_a.sh](recover_option_a.sh) | Updates RDS password from Secrets Manager | 2-3 min |
| [recover_option_b.sh](recover_option_b.sh) | Restores EC2 → RDS security group rule | 1 min |
| [recover_option_c.sh](recover_option_c.sh) | Starts RDS instance | 3-5 min |

### Phase 4: Document & Report

| Script | Purpose | Time |
|--------|---------|------|
| [generate_incident_report.sh](generate_incident_report.sh) | Creates incident report template | 1 min |

---

## File Sizes

```
incident_inject_option_a.sh         4.0K  (Credential drift injection)
incident_inject_option_b.sh         4.3K  (Network isolation injection)
incident_inject_option_c.sh         3.8K  (Database interruption injection)
incident_runbook.sh                 14K   (Mandatory incident response)
recover_option_a.sh                 4.4K  (Credential recovery)
recover_option_b.sh                 4.3K  (Network recovery)
recover_option_c.sh                 4.7K  (Database recovery)
generate_incident_report.sh         5.8K  (Report template)
INCIDENT_RESPONSE_CHEATSHEET.sh     12K   (Quick reference)
LAB_1B_INCIDENT_RESPONSE_GUIDE.md   15K   (Complete guide)
LAB_1B_IMPLEMENTATION_SUMMARY.md    10K   (This summary)
LAB_1B_INDEX.md                     2K    (This index)
```

**Total: 84 KB of incident response framework**

---

## Quick Start (Copy & Paste)

```bash
cd ~/terraform_restart_fixed

# Set variables
export REGION="us-east-1"
export INSTANCE_ID="i-0968fd41f8aaa43eb"
export SECRET_ID="lab1a/rds/mysql"
export ALARM_NAME="lab-db-connection-failure"
export LOG_GROUP="/aws/ec2/chrisbarm-rds-app"
export DB_INSTANCE="chrisbarm-rds01"
export RDS_SG="sg-09253c24b2eee0c11"
export EC2_SG="sg-0059285ecdea5d41d"

# Display cheatsheet
bash INCIDENT_RESPONSE_CHEATSHEET.sh

# Run through workflow
bash incident_inject_option_a.sh  # Step 1: Inject incident
bash incident_runbook.sh          # Step 2: Run runbook (graded)
bash recover_option_a.sh          # Step 3: Execute recovery
bash generate_incident_report.sh  # Step 4: Create report
```

---

## Grading (100 Points)

```
10 pts — Alarm acknowledged (runbook: StateValue == ALARM)
20 pts — Correct classification (runbook identifies A/B/C)
15 pts — Logs used (runbook finds ERROR messages)
10 pts — Parameter Store validated (runbook: aws ssm get-parameters)
10 pts — Secrets Manager validated (runbook: aws secretsmanager get-secret-value)
20 pts — Correct recovery (recovery script succeeds)
10 pts — No redeploy/hardcoding (configuration-based only)
 5 pts — Clear incident report (all sections completed)
────────────────────────
100 pts — TOTAL
```

---

## Three Failure Scenarios (You don't know which one will be injected)

### Scenario A: Credential Drift
- **Symptom:** "Access denied for user 'admin'@'10.0.1.15'"
- **Cause:** Password changed in Secrets Manager, not in RDS
- **Root Cause:** Secret rotation incomplete, RDS not updated
- **Recovery:** `bash recover_option_a.sh` (updates RDS password)
- **Time:** 2-3 minutes

### Scenario B: Network Isolation
- **Symptom:** "Connection refused" or "Connection timeout"
- **Cause:** EC2 → RDS security group rule removed
- **Root Cause:** Accidental SG misconfiguration
- **Recovery:** `bash recover_option_b.sh` (restores SG rule)
- **Time:** 1-2 minutes

### Scenario C: Database Interruption
- **Symptom:** "Cannot connect to endpoint" or "Endpoint unreachable"
- **Cause:** RDS instance stopped
- **Root Cause:** Maintenance or accidental stop
- **Recovery:** `bash recover_option_c.sh` (starts RDS)
- **Time:** 3-5 minutes

---

## The 5 Reflection Questions (Answer These in Incident Report)

### A) Why Parameter Store + Secrets Manager?
Parameter Store for non-rotating config, Secrets Manager for rotating credentials. Different access policies, retention, audit trails.

### B) What Breaks First During Rotation?
Application breaks first if it reads new credential before database is updated. Credential drift scenario.

### C) Why Alarms on Symptoms?
Multiple causes create same symptom. Symptoms are observable; causes require diagnosis. Better to alarm on "3+ DB errors" than "secret changed."

### D) How Does This Reduce MTTR?
Configuration (no redeploy) vs. redeployment (30+ min saved). Runbook (no guessing) (10 min saved). Logging (immediate diagnosis) (5 min saved). Total: 5-10 min MTTR vs. 45-60 min.

### E) What Would You Automate Next?
Lambda triggered by CloudWatch Alarm. Runs classification, executes recovery, sends SNS update. MTTR: 30 seconds.

---

## Expected Timeline

| Phase | Duration |
|-------|----------|
| Setup | 5 min |
| Read docs | 10 min |
| Inject incident | 1 min |
| Watch break | 2-5 min |
| Run runbook | 5 min |
| Execute recovery | 5-10 min |
| Verify | 5 min |
| Report | 10 min |
| **Total** | **~50 min** |

---

## Success Checklist

- [ ] All 10 scripts created and executable
- [ ] Documentation complete (3 guides)
- [ ] Quick reference (cheatsheet) ready
- [ ] Incident injection tested (one scenario)
- [ ] Runbook executes without errors
- [ ] Correct failure identified
- [ ] Recovery script executes successfully
- [ ] Alarm clears to OK
- [ ] Application returns HTTP 200
- [ ] Incident report completed
- [ ] All 5 reflection questions answered

---

## Next Steps

1. **Read** the implementation summary
2. **Review** the full incident response guide
3. **Open** the cheatsheet in another terminal
4. **Inject** an incident using one of the three scripts
5. **Run** the incident runbook
6. **Execute** the appropriate recovery script
7. **Verify** recovery succeeded
8. **Document** findings in incident report

---

## Support

If anything fails:

1. Check [LAB_1B_INCIDENT_RESPONSE_GUIDE.md](LAB_1B_INCIDENT_RESPONSE_GUIDE.md#common-issues--troubleshooting)
2. Verify environment variables are set correctly
3. Check AWS CLI has correct credentials
4. Verify Lab 1a infrastructure still exists
5. Review error messages carefully — they guide diagnostics

---

**Lab 1b: Incident Response Framework**

Complete. Ready to use. 100 points available.

Let's break something and recover it properly.

