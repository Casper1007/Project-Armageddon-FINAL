# Deliverable A — Audit Evidence Pack

## 1. Data Residency Proof (RDS only in Tokyo)
**Tokyo: RDS exists**

```
aws rds describe-db-instances --region ap-northeast-1 \
	--query "DBInstances[].{DB:DBInstanceIdentifier,AZ:AvailabilityZone,Region:'ap-northeast-1',Endpoint:Endpoint.Address}"
```

**São Paulo: No RDS**

```
aws rds describe-db-instances --region sa-east-1 \
	--query "DBInstances[].DBInstanceIdentifier"
```

---

## 2. Edge Proof (CloudFront logs show cache + access)
**Request headers:**

```
curl -I https://chrisbdevsecops.com/api/public-feed
```

**CloudFront log evidence:**
Submit CloudFront standard log evidence (Hit/Miss/RefreshHit)

---

## 3. WAF Proof
Provide WAF log snippet or Insights summary. WAF logging destination options: CloudWatch Logs, S3, Firehose.

---

## 4. Change Proof (CloudTrail)
CloudTrail has event history with a 90-day immutable record of management events.
Capture: who changed SG / TGW route / WAF / CloudFront config

---

## 5. Network Corridor Proof (TGW)
Prove TGW attachments exist in both regions and routes point cross-region CIDRs to TGW.

---

## 6. AWS CLI Verification (S3 logs)
```
aws s3 ls s3://Class_Lab3/
aws s3 ls s3://Class_Lab3/cloudfront-logs/ --recursive | tail -n 20
aws s3 cp s3://Class_Lab3/cloudfront-logs/<somefile>.gz .
```

---

## Terraform Outputs
**Tokyo**
- VPC CIDR: 10.0.0.0/16
- RDS Endpoint: chrisbarm-rds01.cjyguam6c4nd.ap-northeast-1.rds.amazonaws.com
- TGW ID: tgw-0971b8f31d478de41
- TGW Peering Attachment ID: tgw-attach-02bf98e9d3e7dc692

**São Paulo**
- TGW ID: tgw-0c6571915609a9ca0

---

## Malgus Scripts (Purpose & Usage)
- **malgus_residency_proof.py**: Verifies RDS exists only in Tokyo, not São Paulo.
- **malgus_tgw_corridor_proof.py**: Shows TGW attachments and routes for legal corridor.
- **malgus_cloudtrail_last_changes.py**: Pulls recent CloudTrail events for config changes.
- **malgus_waf_summary.py**: Summarizes WAF logs (Allow vs Block) from CloudWatch Logs.
- **malgus_cloudfront_log_explainer.py**: Analyzes CloudFront logs for Hit/Miss/RefreshHit.

---

# Deliverable B — Auditor Narrative (Template)
この設計はAPPI（個人情報保護法）に準拠しており、データベース（RDS）は東京リージョンにのみ存在します。これにより、日本国外への個人データの移転リスクを排除しています。CloudFrontを利用することで、エッジキャッシュによる高速な配信とアクセスログの証拠が得られます。WAFによる攻撃防御とログ記録、CloudTrailによる設定変更の追跡も実装済みです。TGW（トランジットゲートウェイ）を用いたネットワークコリドーにより、リージョン間の通信経路も監査可能です。S3バケットには全ての証拠ログが保存され、CLIコマンドで検証できます。これらの設計により、APPIの要件を満たしつつ、DBを海外に置く必要性がありません。
