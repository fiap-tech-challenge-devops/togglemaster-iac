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

variable "module_ref" {
  description = "Tag da biblioteca terraform-aws-modules consumida por este stage. Fixar em tag, e não em main, impede que um commit na biblioteca altere o plano daqui sem uma mudança explícita neste repositório."
  type        = string
  default     = "v0.1.0"
}

variable "admin_iam_arns" {
  description = "Principals IAM que recebem acesso cluster-admin no EKS, além da role da esteira. Informe seu usuário para conseguir usar kubectl na máquina local."
  type        = list(string)
  default     = []
}

# ── Rede ──────────────────────────────────────────────────────────────────────

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

# ── EKS ───────────────────────────────────────────────────────────────────────

variable "cluster_version" {
  description = "Versão do Kubernetes do control plane."
  type        = string
  default     = "1.32"
}

# O node group é o baseline: dimensionado para o sistema em repouso. Todo o burst
# vai para o Karpenter, em SPOT — por isso min = max = 1.
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

# ── RDS ───────────────────────────────────────────────────────────────────────

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

# ── ElastiCache ───────────────────────────────────────────────────────────────

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

# ── ECR / CI ──────────────────────────────────────────────────────────────────

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

# ── Kubernetes ────────────────────────────────────────────────────────────────

variable "app_namespace" {
  description = "Namespace onde os microsserviços rodam. Precisa bater com o que está no repositório GitOps."
  type        = string
  default     = "togglemaster"
}
