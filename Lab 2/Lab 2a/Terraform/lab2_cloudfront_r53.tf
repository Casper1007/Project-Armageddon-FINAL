/* Route53 aliases for CloudFront distribution.

resource "aws_route53_record" "chrisbarm_apex_a" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.chrisbarm_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.chrisbarm_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "chrisbarm_app_a" {
  zone_id = var.route53_zone_id
  name    = "${var.app_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.chrisbarm_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.chrisbarm_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "chrisbarm_apex_aaaa" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.chrisbarm_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.chrisbarm_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "chrisbarm_app_aaaa" {
  zone_id = var.route53_zone_id
  name    = "${var.app_subdomain}.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.chrisbarm_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.chrisbarm_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}
*/
