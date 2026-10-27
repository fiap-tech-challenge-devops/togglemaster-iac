locals {
  servico = "${var.service_namespace}-${var.environment}"
}

# data, não resource: criar e destruir usuário a cada apply dispararia convite
# por e-mail toda noite. O plantonista já existe na conta.
data "pagerduty_user" "plantao" {
  email = var.pagerduty_user_email
}

data "pagerduty_vendor" "datadog" {
  name = "Datadog"
}

# Sem schedule: o tier gratuito permite um só, e uma escalation policy pode
# apontar direto para o usuário. Schedule entraria se houvesse rodízio real.
resource "pagerduty_escalation_policy" "plantao" {
  name        = "${local.servico} — plantão"
  description = "Gerenciada por Terraform. Ver ADR 0033."
  num_loops   = 2

  rule {
    escalation_delay_in_minutes = 15

    target {
      type = "user_reference"
      id   = data.pagerduty_user.plantao.id
    }
  }
}

resource "pagerduty_service" "togglemaster" {
  name              = local.servico
  description       = "Serviços do ToggleMaster em ${var.environment}."
  escalation_policy = pagerduty_escalation_policy.plantao.id

  # Resolve sozinho se o alerta parar e ninguém reconhecer: o self-healing
  # conserta em ~50s, e o incidente não deveria sobreviver à causa.
  auto_resolve_timeout    = 14400
  acknowledgement_timeout = 1800
}

resource "pagerduty_service_integration" "datadog" {
  name    = data.pagerduty_vendor.datadog.name
  service = pagerduty_service.togglemaster.id
  vendor  = data.pagerduty_vendor.datadog.id
}

# A outra metade da integração. Fica neste stage, e não no datadog/, porque
# consome a integration_key acima — assim a chave não atravessa fronteira de
# stage e o plan do datadog continua sem dependência de AWS. Ver ADR 0033.
# O api_token é "opcional" no schema, mas não na prática: sem ele a API do
# Datadog recusa com "The integration is not installed". Ele não serve só para
# ler schedules — é o que instala a integração na conta. Medido em 26/10.
resource "datadog_integration_pagerduty" "conta" {
  subdomain = var.pagerduty_subdomain
  api_token = var.pagerduty_token
}

resource "datadog_integration_pagerduty_service_object" "togglemaster" {
  depends_on = [datadog_integration_pagerduty.conta]

  service_name = pagerduty_service.togglemaster.name
  service_key  = pagerduty_service_integration.datadog.integration_key
}
