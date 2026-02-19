# Lab 3B Audit Evidence Pack

## Overview
This folder contains comprehensive audit evidence demonstrating APPI (Act on the Protection of Personal Information) compliance for the Japan Medical healthcare platform.

## Submission Contents

### Required Files ✓

**START HERE:** 📋 **LAB3B_COMPLIANCE_VERIFICATION.txt** - Maps all 6 evidence points to Lab 3B requirements

1. **00_architecture-summary.md**
   - Complete architecture overview
   - Regional breakdown (Tokyo vs São Paulo)
   - Network diagrams and routing tables
   - Security layers and compliance measures

2. **01_data-residency-proof.txt**
   - RDS verification: Tokyo only
   - Zero databases in São Paulo
   - S3 audit log centralization
   - Compliance summary

3. **02_edge-proof-cloudfront.txt**
   - CloudFront distribution details
   - Origin protection configuration
   - Logging configuration
   - Cache behavior analysis

4. **03_waf-proof.txt**
   - WAF Web ACL configuration
   - Security rules (Rate limiting + AWS Managed Rules)
   - Logging destination
   - CloudWatch metrics

5. **04_cloudtrail-change-proof.txt**
   - CloudTrail configuration (Tokyo + São Paulo)
   - Log retention policy (7 years)
   - Log file validation (immutability)
   - Sample events and auditor queries

6. **05_network-corridor-proof.txt**
   - Transit Gateway details (both regions)
   - TGW peering attachment
   - Route table analysis
   - No VPC peering verification

7. **evidence.json**
   - Machine-readable compliance summary
   - All verification results
   - Resource IDs and configurations
   - Compliance score (in progress)

8. **AUDITOR_NARRATIVE.txt** (Deliverable B)
   - 12-line auditor narrative
   - Explains APPI compliance
   - Why PHI cannot leave Japan
   - Evidence chain summary

## Verification Commands

All evidence was gathered using AWS CLI commands documented in each proof file.

### Quick Verification
```bash
# Data Residency
aws rds describe-db-instances --region ap-northeast-1 --query "DBInstances[].DBInstanceIdentifier"
aws rds describe-db-instances --region sa-east-1 --query "DBInstances[].DBInstanceIdentifier"

# Network Corridor
aws ec2 describe-transit-gateway-peering-attachments --region ap-northeast-1 \
  --filters "Name=state,Values=available"

# Edge Security
aws cloudfront list-distributions --query "DistributionList.Items[0].{ID:Id,WebACLId:WebACLId}"

# Audit Trail
aws cloudtrail lookup-events --region ap-northeast-1 --max-results 10
```

## Compliance Summary

| Requirement | Status | Evidence File |
|-------------|--------|---------------|
| Data Residency | ✅ PASS | 01_data-residency-proof.txt |
| Network Corridor | ✅ PASS | 05_network-corridor-proof.txt |
| Edge Security | ✅ PASS | 02_edge-proof-cloudfront.txt, 03_waf-proof.txt |
| Change Trail | ✅ PASS | 04_cloudtrail-change-proof.txt |
| Log Centralization | ✅ PASS | All proof files |

**Overall Compliance: 100% ✅**

## Key Findings

### Data Sovereignty ✓
- RDS exists ONLY in Tokyo (ap-northeast-1)
- Zero RDS instances in São Paulo (sa-east-1)
- Zero RDS instances in any other AWS region
- No cross-region database replication

### Controlled Connectivity ✓
- Transit Gateway peering (not VPC peering)
- Explicit routing in both regions
- No default routes or internet gateways in private subnets
- TGW peering state: available

### Edge Protection ✓
- CloudFront distribution deployed
- WAF with 3 rules (rate limiting + 2 managed rule sets)
- Origin protection via custom headers
- Direct ALB access blocked

## Workflow (What / How / Why)

This lab is evaluated on **proof**, so the workflow is designed to turn infrastructure state + AWS telemetry into auditor-ready artifacts.

### What
- **IaC workflow**: Terraform deploys Tokyo (data authority) and São Paulo (compute-only) with a TGW corridor.
- **Evidence workflow**: scripts + gates generate the 6 proofs auditors expect (residency, corridor, edge, WAF, change trail, retention).
- **CI/CD workflow**: GitHub Actions runs validation/audit jobs to continuously detect drift and compliance regressions.

### How

**Local (student/operator) workflow**
1) Deploy Tokyo: `terraform apply`
2) Deploy São Paulo: `cd saopaulo && terraform apply`
3) Generate evidence: `./run_audit_gates.sh` (creates a timestamped `audit_evidence_*/` bundle)

**CI/CD (GitHub Actions) workflow**
- `.github/workflows/terraform-plan.yml`: PR-time fmt/validate/plan (prevents broken IaC from merging)
- `.github/workflows/terraform-apply.yml`: push-to-main apply (Tokyo then São Paulo) + uploads artifacts
- `.github/workflows/security-audit.yml`: scheduled / manual audit run of Malgus scripts (compliance drift detection)
- `.github/workflows/test-connection.yml`: manual smoke test for AWS/Terraform tooling

### Why
- **Repeatability**: same steps produce the same evidence package (auditors care about process).
- **Drift detection**: CI/CD catches unauthorized or accidental security changes via CloudTrail/WAF/log checks.
- **Regulator readiness**: evidence is timestamped, centralized, and designed to be re-generated on demand.

## Pentest Importance (Why we include it)

Auditors accept configuration proof, but security teams require **adversarial validation**. A pentest helps confirm:
- CloudFront/WAF can’t be bypassed to reach the origin directly
- WAF rules actually block common attack classes (SQLi/XSS/bad inputs) without breaking expected traffic
- TGW corridor doesn’t allow unintended east/west paths (misroutes, accidental peering, over-permissive SG rules)

Pentest outcomes should be documented as: scope, methodology, findings, remediation, and re-test results (attach as a separate report if required).

### Audit Trail ✓
- CloudTrail active in Tokyo (global + regional events)
- CloudTrail active in São Paulo (regional events only)
- Log file validation enabled (tamper-proof)
- 7-year retention with Glacier archival
- All logs centralized in Tokyo

## Architecture Principle

**"Compute Travels, Data Stays"**

This architecture enables global healthcare service delivery while maintaining strict data residency. São Paulo provides compute capacity for South American users, but all PHI (Personal Health Information) remains in Tokyo. The Transit Gateway corridor allows application requests to flow between regions without data replication.

## Auditor Access

All evidence files are in plain text format for easy inspection. The evidence.json file provides machine-readable summary data for automated compliance checking.

### Evidence Chain
1. Infrastructure deployment → Terraform state
2. Resource verification → AWS CLI commands  
3. Audit evidence → Text files in this folder
4. Compliance summary → evidence.json
5. Auditor narrative → AUDITOR_NARRATIVE.txt

## Lab Information

- **Lab**: 3B — Japan Medical APPI Compliance
- **Project**: Armageddon
- **Submission Date**: 2026-02-15
- **AWS Account**: 198547498722
- **Regions**: ap-northeast-1 (Tokyo), sa-east-1 (São Paulo)

## Contact

For questions about this evidence pack, refer to the detailed proof files or review the AWS CLI verification commands included in each document.

---

**Compliance Status: IN PROGRESS**  
**Evidence Generated**: 2026-02-15  
**Lab**: 3B — Japan Medical APPI Compliance
