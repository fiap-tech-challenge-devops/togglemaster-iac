# O mapeamento do canal é Terraform; o que não é, e não tem como ser, é a
# autorização OAuth do app do Datadog no workspace. Numa conta Datadog nova,
# refazer o OAuth é o único passo manual — o resto volta por apply. Ver ADR 0028.
resource "datadog_integration_slack_channel" "alertas" {
  count = var.slack_workspace == "" ? 0 : 1

  account_name = var.slack_workspace
  channel_name = var.slack_channel

  display {
    message  = true
    notified = true
    snapshot = true
    tags     = true

    # É o que separa ChatOps de notificação: silenciar o monitor sem sair do Slack.
    mute_buttons = true
  }
}
