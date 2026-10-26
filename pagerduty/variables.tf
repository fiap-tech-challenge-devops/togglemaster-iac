variable "pagerduty_token" {
  description = "Token de API do PagerDuty."
  type        = string
  sensitive   = true
}

variable "pagerduty_subdomain" {
  description = "Subdomínio da conta PagerDuty, a parte antes de .pagerduty.com."
  type        = string
}

variable "pagerduty_user_email" {
  description = "E-mail da conta que recebe o plantão. Precisa existir no PagerDuty."
  type        = string
}

variable "datadog_api_key" {
  description = "API key do Datadog."
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Application key do Datadog."
  type        = string
  sensitive   = true
}

variable "datadog_site" {
  description = "Site do Datadog."
  type        = string
  default     = "datadoghq.com"
}

variable "environment" {
  description = "Ambiente ao qual o serviço de plantão corresponde."
  type        = string
  default     = "prod"
}

# Mesmo nome da variável no stage datadog, de propósito: o handle
# @pagerduty-<serviço> é derivado dos dois lados e precisa bater.
variable "service_namespace" {
  description = "Prefixo do nome do serviço no PagerDuty."
  type        = string
  default     = "togglemaster"
}
