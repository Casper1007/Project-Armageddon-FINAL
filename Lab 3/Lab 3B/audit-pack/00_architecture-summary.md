# Lab 3B Architecture Summary — Japan Medical APPI Compliance

## Overview
Global healthcare platform serving patients worldwide while maintaining strict APPI (Act on the Protection of Personal Information) compliance for Japanese medical records.

## Architecture Design Principle
**"Compute Travels, Data Stays"**

### Data Residency Enforcement
- **PHI Storage**: Tokyo (ap-northeast-1) ONLY
- **Compute Availability**: Global via São Paulo (sa-east-1)
- **Edge Acceleration**: CloudFront for worldwide low-latency access
- **Legal Corridor**: Cross-region TGW peering (not VPC peering)

## Regional Breakdown

### Tokyo (Shinjuku) — Data Authority Region
**Resources:**
- RDS MySQL (chrisbarm-rds01) — **PHI Storage**
- VPC (10.0.0.0/16)
- Transit Gateway (shinjuku-tgw01)
- CloudTrail (audit-trail-tokyo) — Global service events
- S3 Audit Buckets (all logs centralized here)
- EC2 application instances
- ALB for internal routing

**Purpose:** Data sovereignty compliance — all personal health information resides in Japan

### São Paulo (Liberdade) — Compute Spoke Region
**Resources:**
- VPC (10.1.0.0/16)
- Transit Gateway (liberdade-tgw01)
- Auto Scaling Group (compute-only instances)
- Application Load Balancer (origin for CloudFront)
- CloudTrail (audit-trail-saopaulo) — Regional events only
- **NO RDS** — No database replication allowed

**Purpose:** Provide compute capacity for South American users while maintaining data in Tokyo

### Global (Edge) — CloudFront + WAF
**Resources:**
- CloudFront Distribution (pending deployment)
- WAF Web ACL (liberdade-waf-acl)
- Rate limiting (2000 req/5min per IP)
- AWS Managed Rules (Core + Known Bad Inputs)

**Purpose:** Global edge acceleration with security enforcement

## Network Architecture

### The "Legal Corridor" — Transit Gateway Peering
```
┌─────────────────────────────────────────────────────┐
│ Tokyo (ap-northeast-1)                              │
│ ┌─────────────┐         ┌──────────────┐            │
│ │ RDS MySQL   │◄────────│  VPC         │            │
│ │ (PHI Data)  │         │  10.0.0.0/16 │            │
│ └─────────────┘         └──────┬───────┘            │
│                                │                     │
│                         ┌──────▼───────┐             │
│                         │ Shinjuku TGW │             │
│                         │ (Hub)        │             │
│                         └──────┬───────┘             │
└────────────────────────────────┼──────────────────────┘
                                 │ TGW Peering
                                 │ (Cross-Region)
                                 │ Status: available
┌────────────────────────────────▼──────────────────────┐
│ São Paulo (sa-east-1)          │                      │
│                         ┌──────┴───────┐              │
│                         │ Liberdade TGW│              │
│                         │ (Spoke)      │              │
│                         └──────┬───────┘              │
│                                │                      │
│                         ┌──────▼───────┐              │
│                         │  VPC         │              │
│                         │  10.1.0.0/16 │              │
│                         └──────┬───────┘              │
│                                │                      │
│                         ┌──────▼───────┐              │
│                         │ Compute ASG  │              │
│                         │ (No DB)      │              │
│                         └──────────────┘              │
└───────────────────────────────────────────────────────┘
                         │
                         │ Origin Protocol
                         │ (Custom Header Auth)
                         ▼
┌────────────────────────────────────────────────────────┐
│ CloudFront Edge (Global)                               │
│ ┌──────────┐    ┌─────────┐    ┌──────────────────┐   │
│ │   WAF    │───►│CloudFront│───►│ Global Users     │   │
│ │ (Filter) │    │  Cache   │    │ (Low Latency)    │   │
│ └──────────┘    └─────────┘    └──────────────────┘   │
└────────────────────────────────────────────────────────┘
```

### Routing Rules
**Tokyo TGW Route Table:**
- 10.0.0.0/16 → local VPC (propagated)
- 10.1.0.0/16 → São Paulo via TGW peering (static)

**São Paulo TGW Route Table:**
- 10.1.0.0/16 → local VPC (propagated)
- 10.0.0.0/16 → Tokyo via TGW peering (static)

### Why TGW Instead of VPC Peering?
- Centralized routing control
- Scalable hub-and-spoke for future expansion
- Audit-friendly (all routes visible in TGW route tables)
- Regulatory compliance evidence (clearer network segmentation)

## Security & Compliance Layers

### Layer 1: Edge Protection
- **WAF**: Rate limiting + managed rule sets
- **CloudFront**: Geo-restriction capable, DDoS protection
- **Custom Headers**: Origin verification (X-Origin-Verify)

### Layer 2: Network Isolation
- **Private Subnets**: RDS in private subnets only
- **Security Groups**: Principle of least privilege
- **Transit Gateway**: Explicit routing (no default routes to internet)

### Layer 3: Audit & Logging
- **CloudTrail**: All management events (Tokyo + São Paulo)
- **VPC Flow Logs**: Network traffic analysis
- **CloudFront Logs**: Request/response analysis
- **WAF Logs**: Security event tracking

### Layer 4: Data Protection
- **Encryption at Rest**: RDS encryption enabled
- **Encryption in Transit**: TLS everywhere
- **Secrets Management**: AWS Secrets Manager + SSM Parameter Store
- **S3 Versioning**: Immutability for audit logs

## Audit Evidence Chain

### 1. Data Residency Proof
**Command:**
```bash
aws rds describe-db-instances --region ap-northeast-1  # Shows chrisbarm-rds01
aws rds describe-db-instances --region sa-east-1      # Returns []
```

### 2. Network Corridor Proof
**Command:**
```bash
aws ec2 describe-transit-gateway-peering-attachments \
  --region ap-northeast-1 --filters "Name=state,Values=available"
```

### 3. Change Trail Proof
**Command:**
```bash
aws cloudtrail lookup-events --region ap-northeast-1 \
  --max-results 50 --query "Events[?contains(EventName, 'Create')]"
```

### 4. Edge Security Proof
**Command:**
```bash
aws cloudfront get-distribution --id <cloudfront-distribution-id> | jq '.Distribution.DistributionConfig.WebACLId'
```

### 5. Log Retention Proof
**S3 Buckets (All in Tokyo):**
- chrisbarm-cloudtrail-logs-198547498722
- chrisbarm-cloudfront-logs-198547498722
- chrisbarm-waf-logs-198547498722 (CloudWatch Logs)
- chrisbarm-flowlogs-198547498722

## Compliance Statement

**This architecture satisfies APPI requirements because:**

1. **Data Localization**: PHI never leaves Japan (RDS in Tokyo only)
2. **Controlled Access**: TGW enforces explicit routing rules
3. **Audit Trail**: Immutable 7-year log retention in Tokyo
4. **Change Tracking**: CloudTrail captures "who changed what, when"
5. **Edge Security**: WAF + CloudFront protect without data transfer
6. **Network Evidence**: TGW routes prove compute-only corridor

## Key Metrics
- **Regions Deployed**: 2 (Tokyo, São Paulo)
- **PHI Storage Regions**: 1 (Tokyo only)
- **Transit Gateways**: 2 (1 per region)
- **TGW Peering Attachments**: 1 (available)
- **RDS Instances**: 1 (Tokyo)
- **CloudFront Distributions**: 1 (deployed)
- **WAF Rules**: 3 (Rate Limit + 2 Managed Rule Sets)

## Workflow (What / How / Why)

### What
- Terraform creates the compliant topology (Tokyo data authority, São Paulo compute-only, TGW corridor).
- Evidence scripts convert AWS control-plane state (RDS/TGW/CloudFront/WAF/CloudTrail) into timestamped proof artifacts.
- CI/CD continuously validates IaC correctness and re-runs audit checks to catch drift.

### How
- **Deploy (two-phase TGW peering)**: Tokyo apply (creates peering request) → São Paulo apply (accepts peering) → Tokyo apply (adds static routes)
- **Generate evidence**: `run_audit_gates.sh` runs the Malgus scripts and produces an evidence bundle
- **CI/CD**: GitHub Actions workflows in `.github/workflows/` run plan/apply/audit tasks on PR/push/schedule

### Why
- Audits require both architecture and **repeatable evidence generation**.
- CI/CD provides continuous assurance: you can prove “still compliant” instead of “was compliant once.”

---
**Generated**: 2026-02-15  
**Lab**: 3B — Japan Medical APPI Compliance  
**Student**: Lab Evidence Submission
