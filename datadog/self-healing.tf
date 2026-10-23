locals {
  # Só o monitor de taxa de erro do evaluation-service aciona o webhook: é a
  # única falha com remediação ligada. Ver ADR 0032.
  #
  # Em linha própria: handle colado numa URL corre risco de ser absorvido pelo
  # parser, e a falha seria o webhook nunca disparar, em silêncio.
  remediacao = {
    "evaluation-service" = "\n\n@webhook-${datadog_webhook.self_healing.name}"
  }
}

resource "datadog_webhook" "self_healing" {
  name      = "self-healing"
  url       = "https://api.github.com/repos/${var.github_org}/${var.github_repo}/dispatches"
  encode_as = "json"

  custom_headers = jsonencode({
    "Accept"        = "application/vnd.github+json"
    "Authorization" = "Bearer ${var.github_dispatch_token}"
  })

  # A transição vai no payload porque o webhook também dispara em Recovered,
  # Renotify, Warn e No Data — o porteiro da Action filtra por ela.
  payload = jsonencode({
    event_type = "datadog-alert"
    client_payload = {
      transicao = "$ALERT_TRANSITION"
      ciclo     = "$ALERT_CYCLE_KEY"
      servico   = "$TAGS[service]"
      monitor   = "$ALERT_TITLE"
      alerta_id = "$ALERT_ID"
      link      = "$LINK"
    }
  })
}
