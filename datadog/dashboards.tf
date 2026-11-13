# Dashboard de performance dos microsserviços.
#
# `datadog_dashboard_json` e não `datadog_dashboard`: o arquivo é o export da
# UI, sem tradução. Isso preserva o ciclo que se usa de verdade — mexer na
# interface, exportar, substituir o arquivo, abrir PR. Traduzir os 13 widgets
# para HCL ganharia diff legível e perderia esse caminho de volta.
#
# O preço, assumido: um apply desfaz qualquer edição feita na UI. Era a
# objeção da ADR 0026, e segue válida — o Git passa a ser a verdade. Ver 0038.
resource "datadog_dashboard_json" "microservices_performance" {
  dashboard = file("${path.module}/dashboards/microservices-performance.json")
}

output "dashboard_performance_url" {
  description = "URL do dashboard de performance, para o roteiro da demonstração."
  value       = "https://app.${var.datadog_site}/dashboard/${datadog_dashboard_json.microservices_performance.id}"
}
