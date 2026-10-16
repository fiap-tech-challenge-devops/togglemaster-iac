locals {
  notify = var.notification_targets == "" ? "" : "\n\n${var.notification_targets}"
}

resource "datadog_monitor" "auth_5xx" {
  name = "[${var.environment}] auth-service — taxa de erro acima de ${var.error_rate_threshold}%"
  type = "query alert"

  query = <<-EOT
    sum(last_5m):(
      sum:trace.http.server.request.errors{service:auth-service,env:${var.environment}}.as_count()
      /
      sum:trace.http.server.request.hits{service:auth-service,env:${var.environment}}.as_count()
    ) * 100 > ${var.error_rate_threshold}
  EOT

  message = <<-EOT
    O `auth-service` está respondendo erro em mais de ${var.error_rate_threshold}% das requisições nos últimos 5 minutos.

    Como ele autentica as chamadas entre serviços, uma falha aqui derruba o fluxo de avaliação inteiro.

    Trace: https://app.${var.datadog_site}/apm/services/auth-service?env=${var.environment}${local.notify}
  EOT

  monitor_thresholds {
    critical = var.error_rate_threshold
  }

  # Tráfego é esparso neste ambiente: 28 requisições na última semana. Sem isto,
  # toda janela sem chamada viraria alerta.
  notify_no_data      = false
  require_full_window = false

  # Métrica de APM chega com atraso de ingestão; avaliar o minuto corrente daria
  # falso positivo na virada da janela.
  evaluation_delay = 60

  tags = [
    "service:auth-service",
    "env:${var.environment}",
    "managed-by:terraform",
  ]
}
