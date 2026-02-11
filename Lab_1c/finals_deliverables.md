# Final Deliverables

## Bonus A - Prove EC2 is Private (No Public IP)

Command run:

```powershell
aws ec2 describe-instances --region us-east-1 --instance-ids i-0bff937d4cd318644 --query 'Reservations[].Instances[].PublicIpAddress'
```

Output:

```text
[]
```

Interpretation: no public IP is attached to this EC2 instance.

## Bonus A - Prove VPC Endpoints Exist

Command run:

```powershell
aws ec2 describe-vpc-endpoints --region us-east-1 --filters "Name=vpc-id,Values=vpc-0bfaaf0af785cd1e8" --query "VpcEndpoints[].ServiceName"
```

Output:

```json
[
    "com.amazonaws.us-east-1.s3",
    "com.amazonaws.us-east-1.secretsmanager",
    "com.amazonaws.us-east-1.kms",
    "com.amazonaws.us-east-1.ec2messages",
    "com.amazonaws.us-east-1.ssm",
    "com.amazonaws.us-east-1.logs",
    "com.amazonaws.us-east-1.ssmmessages"
]
```

Interpretation: required VPC endpoints are present in the lab VPC.

Expected services check:
- `ssm`: present (`com.amazonaws.us-east-1.ssm`)
- `ec2messages`: present (`com.amazonaws.us-east-1.ec2messages`)
- `ssmmessages`: present (`com.amazonaws.us-east-1.ssmmessages`)
- `logs`: present (`com.amazonaws.us-east-1.logs`)
- `secretsmanager`: present (`com.amazonaws.us-east-1.secretsmanager`)
- `s3`: present (`com.amazonaws.us-east-1.s3`)
- Extra endpoint also present: `kms` (`com.amazonaws.us-east-1.kms`)

## Bonus A - Prove Session Manager Path Works (No SSH)

Command run:

```powershell
aws ssm describe-instance-information --region us-east-1 --query "InstanceInformationList[].InstanceId"
```

Output:

```json
[
    "i-0bff937d4cd318644"
]
```

Interpretation: the private EC2 instance is managed by SSM and reachable without SSH.

## Bonus A - Prove Instance Can Read Parameter Store and Secrets Manager

Validation executed from instance context via SSM Run Command (no SSH), CommandId:

```text
fe0209bb-cbdf-4847-b54a-06c8c992c993
```

Commands executed on the instance:

```bash
aws ssm get-parameter --name /lab/db/endpoint --region us-east-1 --query "Parameter.Name" --output text
aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql --region us-east-1 --query "Name" --output text
```

Output from the instance:

```text
/lab/db/endpoint
lab1a/rds/mysql
```

Interpretation: the instance role can read both Parameter Store and Secrets Manager.

## Bonus A - Prove CloudWatch Logs Delivery Path Is Available

Command run:

```powershell
aws logs describe-log-streams --region us-east-1 --log-group-name /aws/ec2/chrisbarm-rds-app
```

Output:

```json
{
    "logStreams": []
}
```

Interpretation: CloudWatch Logs API path is reachable in this environment; there are currently no log streams in this group.

## Bonus B - Verification Status (Captured February 11, 2026)

Command run:

```powershell
aws elbv2 describe-load-balancers --region us-east-1 --names chrisbarm-alb01 --query "LoadBalancers[0].State.Code"
```

Output:

```text
An error occurred (LoadBalancerNotFound) when calling the DescribeLoadBalancers operation: Load balancers '[chrisbarm-alb01]' not found
```

Command run:

```powershell
aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[].{Name:LoadBalancerName,State:State.Code,Arn:LoadBalancerArn}"
```

Output:

```json
[]
```

Interpretation: no ALB exists in this account/region for Bonus B yet, so listener/target-health/WAF-for-resource checks are blocked until ALB creation.

Command run:

```powershell
aws elbv2 describe-target-groups --region us-east-1 --query "TargetGroups[].{Name:TargetGroupName,Arn:TargetGroupArn,VpcId:VpcId}"
```

Output:

```json
[]
```

Command run:

```powershell
aws wafv2 list-web-acls --region us-east-1 --scope REGIONAL
```

Output:

```json
{
    "WebACLs": []
}
```

Command run:

```powershell
aws cloudwatch describe-alarms --region us-east-1 --alarm-name-prefix chrisbarm-alb-5xx
```

Output:

```json
{
    "MetricAlarms": [],
    "CompositeAlarms": []
}
```

Command run:

```powershell
aws cloudwatch list-dashboards --region us-east-1 --dashboard-name-prefix chrisbarm
```

Output:

```json
{
    "DashboardEntries": []
}
```

Endpoint check commands run:

```powershell
curl -I https://chrisbdevsecops.com
curl -I https://app.chrisbdevsecops.com
```

Output observed from this workstation:

```text
curl: (35) schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS (0x8009030E)
```

Interpretation: Bonus B resources are not currently deployed; local TLS stack/proxy settings also affect direct curl validation from this machine.

## Bonus C - Verification Status (Route53 + ACM)

Command run:

```powershell
aws route53 list-hosted-zones-by-name --dns-name chrisbdevsecops.com --query "HostedZones[].Id"
```

Output:

```json
[
    "/hostedzone/Z0975220SJ1BK9DTNT7A"
]
```

Command run:

```powershell
aws route53 list-resource-record-sets --hosted-zone-id Z0975220SJ1BK9DTNT7A --query "ResourceRecordSets[?Name=='app.chrisbdevsecops.com.']"
```

Output:

```json
[]
```

Command run:

```powershell
Resolve-DnsName app.chrisbdevsecops.com
```

Output (key result):

```text
app.chrisbdevsecops.com CNAME www.acm-validations.aws
```

Interpretation: current `app` record appears to be ACM validation CNAME, not an ALIAS/CNAME to ALB.

Command run:

```powershell
aws acm describe-certificate --region us-east-1 --certificate-arn arn:aws:acm:us-east-1:198547498722:certificate/3de0afe2-3d6d-48b6-9d5a-36d672c8a363 --query "Certificate.Status"
```

Output:

```text
"ISSUED"
```

Command run:

```powershell
aws acm list-certificates --region us-east-1 --includes keyTypes=RSA_2048 --query "CertificateSummaryList[?DomainName=='app.chrisbdevsecops.com'].[CertificateArn,Status,InUse]" --output table
```

Output:

```text
------------------------------------------------------------------------------------------------------------
|                                             ListCertificates                                             |
+---------------------------------------------------------------------------------------+---------+--------+
|  arn:aws:acm:us-east-1:198547498722:certificate/3de0afe2-3d6d-48b6-9d5a-36d672c8a363  |  ISSUED |  False |
+---------------------------------------------------------------------------------------+---------+--------+
```

Interpretation: ACM certificate is issued, but not attached/in use yet.

## Bonus D - Verification Status (Captured February 11, 2026)

Command run:

```powershell
aws route53 list-resource-record-sets --hosted-zone-id Z0975220SJ1BK9DTNT7A --query "ResourceRecordSets[?Name=='chrisbdevsecops.com.']"
```

Output:

```json
[
    {
        "Name": "chrisbdevsecops.com.",
        "Type": "NS",
        "TTL": 172800,
        "ResourceRecords": [
            { "Value": "ns-1205.awsdns-22.org." },
            { "Value": "ns-1788.awsdns-31.co.uk." },
            { "Value": "ns-359.awsdns-44.com." },
            { "Value": "ns-779.awsdns-33.net." }
        ]
    },
    {
        "Name": "chrisbdevsecops.com.",
        "Type": "SOA",
        "TTL": 900,
        "ResourceRecords": [
            { "Value": "ns-1205.awsdns-22.org. awsdns-hostmaster.amazon.com. 1 7200 900 1209600 86400" }
        ]
    }
]
```

Command run:

```powershell
aws elbv2 describe-load-balancers --region us-east-1 --names chrisbarm-alb01 --query "LoadBalancers[0].LoadBalancerArn"
```

Output:

```text
An error occurred (LoadBalancerNotFound) when calling the DescribeLoadBalancers operation: Load balancers '[chrisbarm-alb01]' not found
```

Command run:

```powershell
aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[].{Name:LoadBalancerName,Arn:LoadBalancerArn}"
```

Output:

```json
[]
```

Command run:

```powershell
curl -I https://chrisbdevsecops.com
curl -I https://app.chrisbdevsecops.com
```

Output observed from this workstation:

```text
curl: (7) Failed to connect to chrisbdevsecops.com port 443 via 127.0.0.1 after 2041 ms: Could not connect to server
curl: (7) Failed to connect to app.chrisbdevsecops.com port 443 via 127.0.0.1 after 2038 ms: Could not connect to server
```

Command run:

```powershell
aws s3api list-buckets --query "Buckets[?contains(Name,'alb') || contains(Name,'waf') || contains(Name,'log')].Name"
```

Output:

```json
[]
```

Interpretation: Bonus D is not deployed yet in this account/region (no ALB/logging target), and local network/proxy settings also prevent direct curl validation from this workstation.

## Bonus E - Verification Status (Captured February 11, 2026)

Command run:

```powershell
aws wafv2 list-web-acls --region us-east-1 --scope REGIONAL
```

Output:

```json
{
    "WebACLs": []
}
```

Command run:

```powershell
aws logs describe-log-groups --region us-east-1 --log-group-name-prefix aws-waf-logs- --query "logGroups[].logGroupName"
```

Output:

```json
[]
```

Command run:

```powershell
aws logs describe-log-streams --region us-east-1 --log-group-name aws-waf-logs-chrisbarm-webacl01 --order-by LastEventTime --descending
```

Output:

```text
An error occurred (ResourceNotFoundException) when calling the DescribeLogStreams operation: The specified log group does not exist.
```

Command run:

```powershell
aws logs filter-log-events --region us-east-1 --log-group-name aws-waf-logs-chrisbarm-webacl01 --max-items 20
```

Output:

```text
An error occurred (ResourceNotFoundException) when calling the FilterLogEvents operation: The specified log group does not exist.
```

Command run:

```powershell
aws s3api list-buckets --query "Buckets[?starts_with(Name,'aws-waf-logs-')].Name"
```

Output:

```json
[]
```

Command run:

```powershell
aws firehose list-delivery-streams --region us-east-1
```

Output:

```text
An error occurred (SubscriptionRequiredException) when calling the ListDeliveryStreams operation: The AWS Access Key Id needs a subscription for the service
```

Interpretation: Bonus E WAF logging is not configured because no regional Web ACL/log destination exists in this environment yet.

## Bonus F - Verification Status (Captured February 11, 2026)

Prerequisite log group check command:

```powershell
aws logs describe-log-groups --region us-east-1 --log-group-name-prefix /aws/ec2/ --query "logGroups[].logGroupName"
```

Output:

```json
[
    "/aws/ec2/chewbacca-rds-app",
    "/aws/ec2/chrisbarm-rds-app"
]
```

CloudWatch Logs Insights test command (App query from runbook family):

```powershell
aws logs start-query --region us-east-1 --log-group-name /aws/ec2/chrisbarm-rds-app --start-time <last-15m-start> --end-time <now> --query-string "fields @timestamp, @message | filter @message like /ERROR|Exception|Traceback|DB|timeout|refused/ | stats count() as errors by bin(1m)"
```

Output:

```text
35831ae2-4259-4cb5-aecd-920ab90aae4a
```

Follow-up command:

```powershell
aws logs get-query-results --region us-east-1 --query-id 35831ae2-4259-4cb5-aecd-920ab90aae4a
```

Output:

```json
{
    "queryLanguage": "CWLI",
    "results": [],
    "statistics": {
        "recordsMatched": 0.0,
        "recordsScanned": 0.0,
        "estimatedRecordsSkipped": 0.0,
        "bytesScanned": 0.0,
        "estimatedBytesSkipped": 0.0,
        "logGroupsScanned": 1.0
    },
    "status": "Complete"
}
```

WAF Logs Insights test command:

```powershell
aws logs start-query --region us-east-1 --log-group-name aws-waf-logs-chrisbarm-webacl01 --start-time <last-15m-start> --end-time <now> --query-string "fields @timestamp, action | stats count() as hits by action"
```

Output:

```text
An error occurred (ResourceNotFoundException) when calling the StartQuery operation: Log group 'aws-waf-logs-chrisbarm-webacl01' does not exist for account ID '198547498722'
```

Interpretation: Bonus F query pack is executable for existing app log groups but currently returns no data; WAF query sections are blocked until Bonus E creates a WAF CloudWatch log group.

## JSON Scripts Appendix (A-F)

### Bonus A - SSM Parameters JSON (Step 4)

```json
{
  "commands": [
    "aws ssm get-parameter --name /lab/db/endpoint --region us-east-1 --query \"Parameter.Name\" --output text",
    "aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql --region us-east-1 --query \"Name\" --output text"
  ]
}
```

### Bonus A - Expected Endpoint Services JSON

```json
{
  "required_services": [
    "com.amazonaws.us-east-1.ssm",
    "com.amazonaws.us-east-1.ec2messages",
    "com.amazonaws.us-east-1.ssmmessages",
    "com.amazonaws.us-east-1.logs",
    "com.amazonaws.us-east-1.secretsmanager",
    "com.amazonaws.us-east-1.s3"
  ],
  "extra_services_seen": [
    "com.amazonaws.us-east-1.kms"
  ]
}
```

### Bonus B - Verification Command Manifest JSON

```json
{
  "bonus_b_checks": [
    {
      "id": "alb_state",
      "command": "aws elbv2 describe-load-balancers --region us-east-1 --names chrisbarm-alb01 --query \"LoadBalancers[0].State.Code\""
    },
    {
      "id": "listeners",
      "command": "aws elbv2 describe-listeners --region us-east-1 --load-balancer-arn <ALB_ARN> --query \"Listeners[].Port\""
    },
    {
      "id": "target_health",
      "command": "aws elbv2 describe-target-health --region us-east-1 --target-group-arn <TG_ARN>"
    },
    {
      "id": "waf_association",
      "command": "aws wafv2 get-web-acl-for-resource --region us-east-1 --resource-arn <ALB_ARN>"
    },
    {
      "id": "alb_5xx_alarm",
      "command": "aws cloudwatch describe-alarms --region us-east-1 --alarm-name-prefix chrisbarm-alb-5xx"
    },
    {
      "id": "dashboard_exists",
      "command": "aws cloudwatch list-dashboards --region us-east-1 --dashboard-name-prefix chrisbarm"
    }
  ]
}
```

### Bonus C - Verification Command Manifest JSON

```json
{
  "bonus_c_checks": [
    {
      "id": "hosted_zone",
      "command": "aws route53 list-hosted-zones-by-name --dns-name chrisbdevsecops.com --query \"HostedZones[].Id\""
    },
    {
      "id": "app_record",
      "command": "aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID> --query \"ResourceRecordSets[?Name=='app.chrisbdevsecops.com.']\""
    },
    {
      "id": "cert_status",
      "command": "aws acm describe-certificate --region us-east-1 --certificate-arn <CERT_ARN> --query \"Certificate.Status\""
    },
    {
      "id": "https_app",
      "command": "curl -I https://app.chrisbdevsecops.com"
    }
  ]
}
```

### Bonus D - Verification Command Manifest JSON

```json
{
  "bonus_d_checks": [
    {
      "id": "apex_record",
      "command": "aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID> --query \"ResourceRecordSets[?Name=='chrisbdevsecops.com.']\""
    },
    {
      "id": "alb_arn",
      "command": "aws elbv2 describe-load-balancers --region us-east-1 --names chrisbarm-alb01 --query \"LoadBalancers[0].LoadBalancerArn\""
    },
    {
      "id": "alb_attrs",
      "command": "aws elbv2 describe-load-balancer-attributes --region us-east-1 --load-balancer-arn <ALB_ARN>"
    },
    {
      "id": "traffic_apex",
      "command": "curl -I https://chrisbdevsecops.com"
    },
    {
      "id": "traffic_app",
      "command": "curl -I https://app.chrisbdevsecops.com"
    },
    {
      "id": "s3_logs",
      "command": "aws s3 ls s3://<BUCKET_NAME>/<PREFIX>/AWSLogs/<ACCOUNT_ID>/elasticloadbalancing/ --recursive"
    }
  ]
}
```

### Bonus E - Verification Command Manifest JSON

```json
{
  "bonus_e_checks": [
    {
      "id": "waf_logging_config",
      "command": "aws wafv2 get-logging-configuration --region us-east-1 --resource-arn <WEB_ACL_ARN>"
    },
    {
      "id": "traffic_apex",
      "command": "curl -I https://chrisbdevsecops.com/"
    },
    {
      "id": "traffic_app",
      "command": "curl -I https://app.chrisbdevsecops.com/"
    },
    {
      "id": "cw_streams",
      "command": "aws logs describe-log-streams --region us-east-1 --log-group-name aws-waf-logs-<project>-webacl01 --order-by LastEventTime --descending"
    },
    {
      "id": "cw_events",
      "command": "aws logs filter-log-events --region us-east-1 --log-group-name aws-waf-logs-<project>-webacl01 --max-items 20"
    },
    {
      "id": "s3_logs",
      "command": "aws s3 ls s3://aws-waf-logs-<project>-<account_id>/ --recursive"
    },
    {
      "id": "firehose_status",
      "command": "aws firehose describe-delivery-stream --region us-east-1 --delivery-stream-name aws-waf-logs-<project>-firehose01 --query \"DeliveryStreamDescription.DeliveryStreamStatus\""
    }
  ]
}
```

### Bonus F - Logs Insights Query Pack JSON

```json
{
  "time_window": "last 15 minutes",
  "log_groups": {
    "waf": "aws-waf-logs-<project>-webacl01",
    "app": "/aws/ec2/<project>-rds-app"
  },
  "queries": {
    "waf_top_actions": "fields @timestamp, action | stats count() as hits by action | sort hits desc",
    "waf_top_client_ips": "fields @timestamp, httpRequest.clientIp as clientIp | stats count() as hits by clientIp | sort hits desc | limit 25",
    "waf_top_uris": "fields @timestamp, httpRequest.uri as uri | stats count() as hits by uri | sort hits desc | limit 25",
    "waf_blocked_only": "fields @timestamp, action, httpRequest.clientIp as clientIp, httpRequest.uri as uri | filter action = \"BLOCK\" | stats count() as blocks by clientIp, uri | sort blocks desc | limit 25",
    "waf_blocking_rules": "fields @timestamp, action, terminatingRuleId, terminatingRuleType | filter action = \"BLOCK\" | stats count() as blocks by terminatingRuleId, terminatingRuleType | sort blocks desc | limit 25",
    "waf_suspicious_scanners": "fields @timestamp, httpRequest.clientIp as clientIp, httpRequest.uri as uri | filter uri =~ /wp-login|xmlrpc|\\.env|admin|phpmyadmin|\\.git|login/ | stats count() as hits by clientIp, uri | sort hits desc | limit 50",
    "app_errors_over_time": "fields @timestamp, @message | filter @message like /ERROR|Exception|Traceback|DB|timeout|refused/ | stats count() as errors by bin(1m)",
    "app_recent_db_failures": "fields @timestamp, @message | filter @message like /DB|mysql|timeout|refused|Access denied|could not connect/ | sort @timestamp desc | limit 50"
  }
}
```
