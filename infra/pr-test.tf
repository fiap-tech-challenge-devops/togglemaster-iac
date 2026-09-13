variable "pr_test_toggle" {
  description = "Interruptor sem efeito prático, usado para exercitar o fluxo de PR -> checks -> merge -> apply. Alterne entre true e false e abra um PR. Nenhum recurso depende dele: o plan mostra apenas uma mudança de output, com 0 to add, 0 to change, 0 to destroy. Remova este arquivo quando a esteira estiver validada."
  type        = bool
  default     = false
}

output "pr_test_toggle" {
  description = "Eco do interruptor de teste."
  value       = var.pr_test_toggle
}
