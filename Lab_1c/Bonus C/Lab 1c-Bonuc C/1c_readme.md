# Lab 1C — Terraform: EC2 → RDS + Secrets/Params + Observability + Incident Alerts

## Purpose
Modern companies do not build AWS by clicking around in the console.
They use Infrastructure as Code (IaC) so environments are repeatable, reviewable, auditable, and recoverable.

This repo is intentionally incomplete:
- It declares required resources
- Students must configure the details (rules, policies, user_data, app logging, etc.)

## Requirements (must exist in Terraform)
- VPC, public/private subnets, IGW, NAT, routing
- EC2 app host + IAM role/profile
- RDS (private) + subnet group + SG with inbound from EC2 SG
- Parameter Store values (/lab/db/*)
- Secrets Manager secret (db creds)
- CloudWatch log group
- CloudWatch alarm (DBConnectionErrors >= 3 per 5 min)
- SNS topic + subscription

## Student Deliverables
- `terraform plan` output
- `terraform apply` evidence (outputs)
- CLI verification commands (from Lab 1b)
- Incident runbook execution notes (alarm fired + recovered)