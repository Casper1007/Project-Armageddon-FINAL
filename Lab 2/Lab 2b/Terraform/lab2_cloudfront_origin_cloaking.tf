# Explanation: Chrisbarm only opens the hangar to CloudFront — everyone else gets the roar.

data "aws_ec2_managed_prefix_list" "chrisbarm_cf_origin_facing01" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# Explanation: Only CloudFront origin-facing IPs may speak to the ALB — direct-to-ALB attacks die here.
resource "aws_security_group_rule" "chrisbarm_alb_ingress_cf44301" {
  type              = "ingress"
  security_group_id = aws_security_group.chrisbarm_alb_sg01.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"

  prefix_list_ids = [
    data.aws_ec2_managed_prefix_list.chrisbarm_cf_origin_facing01.id
  ]
}

# Explanation: This is Chrisbarm's secret handshake — if the header isn't present, you don't get in.
resource "random_password" "chrisbarm_origin_header_value01" {
  length  = 32
  special = false
}

# Explanation: ALB checks for Chrisbarm's secret growl — no growl, no service.
resource "aws_lb_listener_rule" "chrisbarm_require_origin_header01" {
  listener_arn = aws_lb_listener.chrisbarm_http_listener01.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.chrisbarm_tg01.arn
  }

  condition {
    http_header {
      http_header_name = "X-Chrisbarm-Growl"
      values           = [random_password.chrisbarm_origin_header_value01.result]
    }
  }
}

# Explanation: If you don't know the growl, you get a 403 — Chrisbarm does not negotiate.
resource "aws_lb_listener_rule" "chrisbarm_default_block01" {
  listener_arn = aws_lb_listener.chrisbarm_http_listener01.arn
  priority     = 100  # ← Lower precedence than priority 10

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  condition {
    path_pattern { values = ["*"] }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Origin Cloaking Verification
# ═══════════════════════════════════════════════════════════════════════════════
# 
# Test 1: Direct ALB access should fail
#   curl -I https://$ALB_DNS
#   Expected: 403 Forbidden (no header present)
#
# Test 2: With correct header (CloudFront sends this automatically)
#   curl -I -H "X-Chrisbarm-Growl: <correct-32-char-secret>" https://$ALB_DNS
#   Expected: 200 OK (forwarded to target group)
#
# Test 3: With wrong header
#   curl -I -H "X-Chrisbarm-Growl: wrong-secret" https://$ALB_DNS
#   Expected: 403 Forbidden (header doesn't match)
# ═══════════════════════════════════════════════════════════════════════════════
