# Bonus-F: CloudWatch Logs Insights Query Pack (Runbook)
# Variables students fill in:
#   WAF log group: aws-waf-logs-<project>-webacl01
#   App log group: /aws/ec2/<project>-rds-app
# Time range: Last 15 minutes (or match incident window)
#
# A) WAF Queries
# A1) Top actions
#   fields @timestamp, action
#   | stats count() as hits by action
#   | sort hits desc
#
# A2) Top client IPs
#   fields @timestamp, httpRequest.clientIp as clientIp
#   | stats count() as hits by clientIp
#   | sort hits desc
#   | limit 25
#
# A3) Top requested URIs
#   fields @timestamp, httpRequest.uri as uri
#   | stats count() as hits by uri
#   | sort hits desc
#   | limit 25
#
# A4) Blocked requests only
#   fields @timestamp, action, httpRequest.clientIp as clientIp, httpRequest.uri as uri
#   | filter action = "BLOCK"
#   | stats count() as blocks by clientIp, uri
#   | sort blocks desc
#   | limit 25
#
# A5) Which WAF rule is blocking?
#   fields @timestamp, action, terminatingRuleId, terminatingRuleType
#   | filter action = "BLOCK"
#   | stats count() as blocks by terminatingRuleId, terminatingRuleType
#   | sort blocks desc
#   | limit 25
#
# A6) Suspicious paths (rate/spike)
#   fields @timestamp, httpRequest.clientIp as clientIp, httpRequest.uri as uri
#   | filter uri like /wp-login|xmlrpc|\.env|admin|phpmyadmin|\.git|\/login/i
#   | stats count() as hits by clientIp, uri
#   | sort hits desc
#   | limit 50
#
# A7) Suspicious scanners (common patterns)
#   fields @timestamp, httpRequest.clientIp as clientIp, httpRequest.uri as uri
#   | filter uri like /wp-login|xmlrpc|\.env|admin|phpmyadmin|\.git|\/login/i
#   | stats count() as hits by clientIp, uri
#   | sort hits desc
#   | limit 50
#
# A8) Country/geo (if present)
#   fields @timestamp, httpRequest.country as country
#   | stats count() as hits by country
#   | sort hits desc
#   | limit 25
#
# B) App Queries
# B1) Errors over time
#   fields @timestamp, @message
#   | filter @message like /ERROR|Exception|Traceback|DB|timeout|refused/i
#   | stats count() as errors by bin(1m)
#   | sort bin(1m) asc
#
# B2) Recent DB failures
#   fields @timestamp, @message
#   | filter @message like /DB|mysql|timeout|refused|Access denied|could not connect/i
#   | sort @timestamp desc
#   | limit 50
#
# B3) Creds vs network classifier
#   fields @timestamp, @message
#   | filter @message like /Access denied|authentication failed|timeout|refused|no route|could not connect/i
#   | stats count() as hits by
#     case(
#       @message like /Access denied|authentication failed/i, "Creds/Auth",
#       @message like /timeout|no route/i, "Network/Route",
#       @message like /refused/i, "Port/SG/ServiceRefused",
#       "Other"
#     )
#   | sort hits desc
#
# B4) JSON logs (if you emit JSON)
#   fields @timestamp, level, event, reason
#   | filter level="ERROR"
#   | stats count() as n by event, reason
#   | sort n desc
#
# C) Recovery check
#   curl https://app.chrisbdevsecops.com/list works
