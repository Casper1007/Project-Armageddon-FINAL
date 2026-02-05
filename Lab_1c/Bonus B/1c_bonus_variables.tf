variable "domain_name" {
  description = "Base domain students registered (e.g., chrisbdevsecops.com)."
  type        = string
  default     = "chrisbdevsecops.com"
}

variable "app_subdomain" {
  description = "App hostname prefix (e.g., app.chrisbdevsecops.com)."
  type        = string
  default     = "app"
}

variable "certificate_validation_method" {
  description = "ACM validation method. Students can do DNS (Route53) or EMAIL."
  type        = string
  default     = "DNS"
}

variable "enable_waf" {
  description = "Toggle WAF creation."
  type        = bool
  default     = true
}

variable "alb_5xx_threshold" {
  description = "Alarm threshold for ALB 5xx count."
  type        = number
  default     = 10
}

variable "alb_5xx_period_seconds" {
  description = "CloudWatch alarm period."
  type        = number
  default     = 300
}

variable "alb_5xx_evaluation_periods" {
  description = "Evaluation periods for alarm."
  type        = number
  default     = 1
}

variable "create_route53_zone" {
  description = "Create a public Route53 hosted zone for domain_name when using DNS validation."
  type        = bool
  default     = true
}