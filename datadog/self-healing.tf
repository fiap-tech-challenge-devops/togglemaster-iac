locals {
  # Só o monitor de taxa de erro do evaluation-service aciona o webhook: é a
  # única falha com remediação ligada. Ver ADR 0032.
  #
  # Vai dentro de {{#is_alert}} na mensagem, então o aviso de 5% não chega aqui
  # — a remediação automática é autorizada só pelo patamar crítico. Ver 0034.
  #
  # Em linha própria: handle colado numa URL corre risco de ser absorvido pelo
  # parser, e a falha seria o webhook nunca disparar, em silêncio.
  remediacao = {
    "evaluation-service" = "\n\n@webhook-${datadog_webhook.self_healing.name}"
  }
}

# O PAT como variável secreta, não literal no header: com is_secret o painel
# mostra mascarado e a API não devolve o valor. Literal, ele fica legível para
# qualquer pessoa com acesso de leitura às integrações.
resource "datadog_webhook_custom_variable" "github_dispatch_token" {
  name      = "GITHUB_DISPATCH_TOKEN"
  value     = var.github_dispatch_token
  is_secret = true
}

resource "datadog_webhook" "self_healing" {
  name      = "self-healing"
  url       = "https://api.github.com/repos/${var.github_org}/${var.github_repo}/dispatches"
  encode_as = "json"

  # format() em vez da string literal para criar a dependência explícita: o
  # webhook não pode existir antes da variável que ele referencia.
  custom_headers = jsonencode({
    "Accept"        = "application/vnd.github+json"
    "Authorization" = format("Bearer $%s", datadog_webhook_custom_variable.github_dispatch_token.name)
  })

  # A transição vai no payload para o porteiro filtrar. Com o handle dentro de
  # {{#is_alert}}, Warn e Recovered já não chegam aqui — mas o filtro fica:
  # ele é a única defesa se alguém editar a mensagem pela UI.
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
