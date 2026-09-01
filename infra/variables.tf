variable "region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "system" {
  description = "Nome do sistema — base do padrão <tipo>-<sistema>."
  type        = string
  default     = "togglemaster"
}

variable "admin_iam_arns" {
  description = "Principals IAM que recebem acesso cluster-admin no EKS, além da role da esteira. Sem o seu usuário aqui, o kubectl local não autentica no cluster."
  type        = list(string)
  default = [
    "arn:aws:iam::762103020993:user/vitor.aws",
    "arn:aws:iam::762103020993:user/quebradas",
  ]
}

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas, uma por AZ."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas, uma por AZ."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "cluster_version" {
  description = "Versão do Kubernetes do control plane."
  type        = string
  default     = "1.34"
}

variable "node_instance_types" {
  description = "Tipos de instância do node group de baseline. t3.large: 2 vCPU, 8 GB, 35 pods — cabe o sistema em repouso."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_desired_size" {
  description = "Nós desejados no baseline."
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Mínimo de nós do baseline."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Máximo de nós do baseline. Igual ao mínimo: quem escala é o Karpenter."
  type        = number
  default     = 1
}

variable "karpenter_chart_version" {
  description = "Versão do chart do Karpenter, exportada no SSM para o repositório GitOps consumir. Karpenter >= 1.2 é obrigatório em Kubernetes 1.32."
  type        = string
  default     = "1.3.3"
}

variable "rds_engine_version" {
  description = "Versão do PostgreSQL."
  type        = string
  default     = "16"
}

variable "rds_instance_class" {
  description = "Classe de instância dos RDS."
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "Armazenamento por instância RDS, em GB."
  type        = number
  default     = 20
}

variable "redis_engine_version" {
  description = "Versão da engine Redis."
  type        = string
  default     = "7.1"
}

variable "redis_node_type" {
  description = "Tipo de nó do ElastiCache."
  type        = string
  default     = "cache.t4g.micro"
}

variable "app_namespace" {
  description = "Namespace onde os microsserviços rodam. Precisa bater com o que está no repositório GitOps."
  type        = string
  default     = "togglemaster"
}
