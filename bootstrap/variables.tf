variable "region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "system" {
  description = "Nome do sistema — prefixo dos recursos."
  type        = string
  default     = "togglemaster"
}

variable "github_org" {
  description = "Organização do GitHub dona dos repositórios."
  type        = string
  default     = "fiap-tech-challenge-devops"
}

variable "iac_repository" {
  description = "Repositório que executa as esteiras de IaC. Só ele pode assumir a role de infraestrutura."
  type        = string
  default     = "togglemaster-iac"
}

variable "create_github_oidc_provider" {
  description = "Cria o OIDC provider do GitHub. Use false se ele já existir na conta — nesse caso o ARN é resolvido por data source."
  type        = bool
  default     = true
}

variable "iac_role_name" {
  description = "Nome da IAM role assumida pelas esteiras de IaC via OIDC."
  type        = string
  default     = "github-actions-iac"
}
