locals {
  notify = var.notification_targets == "" ? "" : "\n\n${var.notification_targets}"

  # Nos oito monitores: a escolha foi paginar tudo, aceitando que o incidente
  # do evaluation abra e resolva sozinho quando o self-healing agir.
  #
  # Nos quatro de taxa de erro ele entra só no patamar crítico; nos de latência
  # segue em toda transição, porque lá não existe escada.
  paginar = var.pagerduty_habilitado ? "\n\n@pagerduty-${var.service_namespace}-${var.environment}" : ""

  # O canal é registrado à mão; o handle é código. Formato qualificado pela
  # conta, que é o documentado. O Datadog aceita handle inexistente sem
  # reclamar — se o nome da conta não bater, o alerta some em silêncio.
  slack = var.slack_workspace == "" ? "" : "\n\n@slack-${var.slack_workspace}-${trimprefix(var.slack_channel, "#")}"

  # Latência por serviço, porque os papéis são diferentes: o evaluation faz
  # fan-out para flag, targeting, auth e Redis; o auth é uma query só.
  #
  # O analytics fica de fora: é consumidor de SQS escalado a zero pelo KEDA, e
  # não tem span http.server.request. Precisa de query própria.
  servicos = {
    "auth-service" = {
      papel       = "autentica as chamadas entre serviços"
      impacto     = "uma falha aqui derruba o fluxo de avaliação inteiro"
      latencia_ms = 500
    }
    "evaluation-service" = {
      papel       = "orquestra a avaliação de flags"
      impacto     = "é a porta de entrada do fluxo de leitura"
      latencia_ms = 2000
    }
    "flag-service" = {
      papel       = "responde a configuração das flags"
      impacto     = "o evaluation estoura o timeout de 5s e devolve 502"
      latencia_ms = 1000
    }
    "targeting-service" = {
      papel       = "resolve as regras de segmentação"
      impacto     = "o evaluation estoura o timeout de 5s e devolve 502"
      latencia_ms = 1000
    }
  }
}

resource "datadog_monitor" "taxa_de_erro" {
  for_each = local.servicos

  # Os dois patamares no nome: o avaliador que procurar o 5% do enunciado
  # encontra, e a escada por cima fica visível no print.
  name = "[${var.environment}] ${each.key} — taxa de erro: aviso ${var.error_rate_warning}%, crítico ${var.error_rate_threshold}%"
  type = "query alert"

  query = <<-EOT
    sum(last_5m):(
      sum:trace.http.server.request.errors{service:${each.key},env:${var.environment}}.as_count()
      /
      sum:trace.http.server.request.hits{service:${each.key},env:${var.environment}}.as_count()
    ) * 100 > ${var.error_rate_threshold}
  EOT

  # Os blocos is_warning/is_alert são o mecanismo do Datadog para rotear por
  # estado. Handle FORA deles notifica em toda transição — é onde o Slack mora,
  # porque o ChatOps quer ver subir e recuperar.
  #
  # O PagerDuty reaparece em TODA saída do crítico, senão o incidente não
  # resolve. São duas saídas, não uma: na descida a razão drena pela faixa de
  # aviso antes de chegar a zero, então a transição comum é alert → warn → OK.
  #
  # Tag de fechamento em linha própria: handle colado nela corre o risco de ter
  # o {{/is_alert}} absorvido pelo parser, e a falha seria o webhook nunca
  # disparar, em silêncio. Mesmo motivo do handle em linha própria na 0032.
  message = <<-EOT
    {{#is_warning}}A taxa de erro do `${each.key}` passou de ${var.error_rate_warning}%, ainda abaixo do patamar crítico de ${var.error_rate_threshold}%. Não pagina e não aciona remediação — é para olhar antes de chegar lá.{{/is_warning}}
    {{#is_alert}}O `${each.key}` está respondendo erro em mais de ${var.error_rate_threshold}% das requisições nos últimos 5 minutos.{{/is_alert}}

    Ele ${each.value.papel}, e ${each.value.impacto}.

    Traces: https://app.${var.datadog_site}/apm/services/${each.key}?env=${var.environment}${local.notify}${local.slack}
    {{#is_alert}}${local.paginar}${lookup(local.remediacao, each.key, "")}
    {{/is_alert}}
    {{#is_recovery}}${local.paginar}
    {{/is_recovery}}
    {{#is_alert_to_warning}}${local.paginar}
    {{/is_alert_to_warning}}
  EOT

  monitor_thresholds {
    critical = var.error_rate_threshold
    warning  = var.error_rate_warning
  }

  # Tráfego é esparso: sem isto, toda janela sem chamada viraria alerta.
  notify_no_data      = false
  require_full_window = false
  evaluation_delay    = 60

  tags = [
    "service:${each.key}",
    "env:${var.environment}",
    "signal:errors",
    "managed-by:terraform",
  ]
}

resource "datadog_monitor" "latencia" {
  for_each = local.servicos

  name = "[${var.environment}] ${each.key} — p95 acima de ${each.value.latencia_ms}ms"
  type = "query alert"

  # A métrica é trace.http.server.request, sem sufixo: o .duration pertence ao
  # namespace antigo, marcado como depreciado e sem dado. É distribuição em
  # SEGUNDOS, daí a divisão — o limiar fica em ms só para o nome ficar legível.
  query = <<-EOT
    percentile(last_5m):p95:trace.http.server.request{service:${each.key},env:${var.environment}} > ${each.value.latencia_ms / 1000}
  EOT

  message = <<-EOT
    O `${each.key}` está com p95 acima de ${each.value.latencia_ms}ms nos últimos 5 minutos.

    Latência alta costuma aparecer **antes** da taxa de erro: o serviço ainda responde, só que tarde. Se o chamador tiver timeout, o erro aparece nele, não aqui.

    Traces: https://app.${var.datadog_site}/apm/services/${each.key}?env=${var.environment}${local.notify}${local.slack}${local.paginar}
  EOT

  monitor_thresholds {
    critical = each.value.latencia_ms / 1000
  }

  notify_no_data      = false
  require_full_window = false
  evaluation_delay    = 60

  tags = [
    "service:${each.key}",
    "env:${var.environment}",
    "signal:latency",
    "managed-by:terraform",
  ]
}
