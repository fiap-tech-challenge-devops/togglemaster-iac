variable "region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "system" {
  description = "Nome do sistema — prefixo do bucket de state e dos repositórios ECR."
  type        = string
  default     = "togglemaster"
}

variable "github_org" {
  description = "Organização do GitHub dona dos repositórios dos microsserviços."
  type        = string
  default     = "fiap-tech-challenge-devops"
}

variable "ci_role_name" {
  description = "Nome da IAM role assumida pelas esteiras dos microsserviços para publicar no ECR."
  type        = string
  default     = "github-actions-ecr-push"
}
