###############################################################################
# Lab 2: Resource Renames (Chewbacca -> Chrisbarm)
#
# These `moved` blocks preserve Terraform state addresses so Terraform doesn't
# destroy/recreate resources just because we renamed the blocks.
###############################################################################

moved {
  from = aws_cloudfront_distribution.chewbacca_cf01
  to   = aws_cloudfront_distribution.chrisbarm_cf01
}

moved {
  from = aws_cloudfront_cache_policy.chewbacca_cache_static01
  to   = aws_cloudfront_cache_policy.chrisbarm_cache_static01
}

moved {
  from = aws_cloudfront_cache_policy.chewbacca_cache_api_disabled01
  to   = aws_cloudfront_cache_policy.chrisbarm_cache_api_disabled01
}

moved {
  from = aws_cloudfront_origin_request_policy.chewbacca_orp_api01
  to   = aws_cloudfront_origin_request_policy.chrisbarm_orp_api01
}

moved {
  from = aws_cloudfront_origin_request_policy.chewbacca_orp_static01
  to   = aws_cloudfront_origin_request_policy.chrisbarm_orp_static01
}

moved {
  from = aws_cloudfront_response_headers_policy.chewbacca_rsp_static01
  to   = aws_cloudfront_response_headers_policy.chrisbarm_rsp_static01
}

moved {
  from = aws_security_group_rule.chewbacca_alb_ingress_cf44301
  to   = aws_security_group_rule.chrisbarm_alb_ingress_cf44301
}

moved {
  from = random_password.chewbacca_origin_header_value01
  to   = random_password.chrisbarm_origin_header_value01
}

moved {
  from = aws_lb_listener_rule.chewbacca_require_origin_header01
  to   = aws_lb_listener_rule.chrisbarm_require_origin_header01
}

moved {
  from = aws_lb_listener_rule.chewbacca_default_block01
  to   = aws_lb_listener_rule.chrisbarm_default_block01
}

