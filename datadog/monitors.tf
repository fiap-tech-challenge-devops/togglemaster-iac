locals {
  notify = var.notification_targets == "" ? "" : "\n\n${var.notification_targets}"

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

  name = "[${var.environment}] ${each.key} — taxa de erro acima de ${var.error_rate_threshold}%"
  type = "query alert"

  query = <<-EOT
    sum(last_5m):(
      sum:trace.http.server.request.errors{service:${each.key},env:${var.environment}}.as_count()
      /
      sum:trace.http.server.request.hits{service:${each.key},env:${var.environment}}.as_count()
    ) * 100 > ${var.error_rate_threshold}
  EOT

  message = <<-EOT
    O `${each.key}` está respondendo erro em mais de ${var.error_rate_threshold}% das requisições nos últimos 5 minutos.

    Ele ${each.value.papel}, e ${each.value.impacto}.

    Traces: https://app.${var.datadog_site}/apm/services/${each.key}?env=${var.environment}${local.notify}
  EOT

  monitor_thresholds {
    critical = var.error_rate_threshold
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

  # trace.*.duration é distribuição em nanossegundos.
  query = <<-EOT
    percentile(last_5m):p95:trace.http.server.request.duration{service:${each.key},env:${var.environment}} > ${each.value.latencia_ms * 1000000}
  EOT

  message = <<-EOT
    O `${each.key}` está com p95 acima de ${each.value.latencia_ms}ms nos últimos 5 minutos.

    Latência alta costuma aparecer **antes** da taxa de erro: o serviço ainda responde, só que tarde. Se o chamador tiver timeout, o erro aparece nele, não aqui.

    Traces: https://app.${var.datadog_site}/apm/services/${each.key}?env=${var.environment}${local.notify}
  EOT

  monitor_thresholds {
    critical = each.value.latencia_ms * 1000000
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
