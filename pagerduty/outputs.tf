output "servico" {
  description = "Nome do serviço no PagerDuty. O handle do monitor é @pagerduty-<este valor>."
  value       = pagerduty_service.togglemaster.name
}

output "handle_do_monitor" {
  description = "String a usar na mensagem do monitor no stage datadog."
  value       = "@pagerduty-${pagerduty_service.togglemaster.name}"
}
