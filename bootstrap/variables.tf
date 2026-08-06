variable "region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "system" {
  description = "Nome do sistema — prefixo do bucket de state."
  type        = string
  default     = "togglemaster"
}
