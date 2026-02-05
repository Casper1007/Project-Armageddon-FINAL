Here, it is assumed that you have your own URL. I'm using chrisbdevsecops.com as an example


Alright — Lab 1C-Bonus-B (and yes, we’ll assume the students own chrisbarm-growl.com).
This turns your stack into a real enterprise pattern:
  Public ALB (internet-facing)
  Private EC2 targets (no public IP)
  TLS with ACM for chrisbdevsecops.com
  WAF attached to ALB
  CloudWatch Dashboard
  SNS alarm on ALB 5xx spikes

This is exactly how modern companies ship: IaC + private compute + managed ingress + TLS + WAF + monitoring + paging. 
If you can submit this in Terraform, you’re no longer “a student who clicked around”— you’re a junior cloud engineers.

Below is a Terraform skeleton overlay you can add to your existing 1C + Bonus-A repo.

Add 1c_bonus_variables.tf (append to variables.tf)

Add file: bonus_b.tf
This assumes you already have from 1C / Bonus-A:
  aws_vpc.chrisbarm_vpc01
  aws_subnet.chrisbarm_public_subnets
  aws_subnet.chrisbarm_private_subnets
  aws_security_group.chrisbarm_ec2_sg01 (for private EC2)
  aws_instance.chrisbarm_ec201_private_bonus (private EC2 instance)
  aws_sns_topic.chrisbarm_sns_topic01 (SNS topic)

Add file: Bonus-B_outputs.tf

What you must implement (so you learn the right pain)
TLS (ACM) validation for app.chrisbdevsecpps.com
You gave them the domain; they must complete one of:
  DNS validation (best): create Route53 hosted zone + validation records in Terraform
  Email validation (acceptable): do it manually, then Terraform continues (less ideal)

Suggested student path (DNS):
  Create Route53 Hosted Zone for chrisbarm-growl.com
  Add aws_route53_record for ACM validation
  Add a CNAME (or ALIAS) pointing app.chrisbarm-growl.com → ALB DNS

  I didn’t auto-add Route53 resources because some students may manage DNS outside Route53. 
  But if you want, I can provide a Route53 skeleton too (Hosted Zone + records + ACM validation), 
  Chewbacca-style.

ALB SG rules
you must add:
  inbound 80/443 from 0.0.0.0/0
  outbound to targets on app port

EC2 runs app on the target port
They must ensure their user-data/app listens on port 80 (or update TG/SG accordingly).

Verification commands (CLI) for Bonus-B
1) ALB exists and is active
   
      aws elbv2 describe-load-balancers \
        --names chrisbarm-alb01 \
        --query "LoadBalancers[0].State.Code"

3) HTTPS listener exists on 443
   
      aws elbv2 describe-listeners \
        --load-balancer-arn <ALB_ARN> \
        --query "Listeners[].Port"

4) Target is healthy
   
      aws elbv2 describe-target-health \
        --target-group-arn <TG_ARN>

5) WAF attached
   
      aws wafv2 get-web-acl-for-resource \
        --resource-arn <ALB_ARN>

7) Alarm created (ALB 5xx)
   
      aws cloudwatch describe-alarms \
        --alarm-name-prefix chrisbarm-alb-5xx

9) Dashboard exists
    
      aws cloudwatch list-dashboards \
        --dashboard-name-prefix chrisbarm




