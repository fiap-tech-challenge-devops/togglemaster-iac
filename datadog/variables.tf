variable "datadog_api_key" {
  description = "API key da conta Datadog, entregue por tf-vars."
  type        = string
  sensitive   = true
}

# Gerenciar configuração exige API key E Application key; só o envio de
# telemetria funciona com a primeira sozinha.
variable "datadog_app_key" {
  description = "Application key da conta Datadog, entregue por tf-vars. Exigida pelo provider para gerenciar monitor, webhook e integrações."
  type        = string
  sensitive   = true
}

variable "datadog_site" {
  description = "Site da conta Datadog. Ex.: datadoghq.com, us5.datadoghq.com, datadoghq.eu."
  type        = string
  default     = "datadoghq.com"
}

variable "environment" {
  description = "Valor da tag env nos recursos do Datadog. Precisa bater com deployment.environment.name que os serviços enviam."
  type        = string
  default     = "prod"
}

variable "service_namespace" {
  description = "Valor de service.namespace que os serviços enviam, usado para escopar queries."
  type        = string
  default     = "togglemaster"
}

variable "error_rate_threshold" {
  description = "Percentual de erro que dispara o alerta. O enunciado pede 5%."
  type        = number
  default     = 5
}

# Vazio enquanto Slack e PagerDuty não estão conectados. Ganha os handles
# (@slack-canal, @pagerduty-servico) quando as integrações existirem.
variable "notification_targets" {
  description = "Handles de notificação acrescentados à mensagem do monitor."
  type        = string
  default     = ""
}
