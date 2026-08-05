variable "region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "system" {
  description = "Nome do sistema — prefixo dos parâmetros SSM publicados pelo stage infra."
  type        = string
  default     = "togglemaster"
}

# ── Versões dos charts ────────────────────────────────────────────────────────
# Fixadas de propósito. Um chart sem versão resolve para a mais recente a cada
# apply, e o resultado passa a depender de quando você rodou.
#
# Confira as disponíveis com: helm search repo <repo>/<chart> --versions

variable "metrics_server_chart_version" {
  description = "Versão do chart do metrics-server."
  type        = string
  default     = "3.12.2"
}

variable "aws_lb_controller_chart_version" {
  description = "Versão do chart do AWS Load Balancer Controller."
  type        = string
  default     = "1.8.1"
}

variable "external_secrets_chart_version" {
  description = "Versão do chart do External Secrets Operator."
  type        = string
  default     = "0.10.4"
}

variable "keda_chart_version" {
  description = "Versão do chart do KEDA."
  type        = string
  default     = "2.18.3"
}

variable "argocd_chart_version" {
  description = "Versão do chart argo-cd."
  type        = string
  default     = "7.7.11"
}

variable "argocd_apps_chart_version" {
  description = "Versão do chart argocd-apps, usado para criar a Application raiz."
  type        = string
  default     = "2.0.2"
}

# ── Componentes opcionais ─────────────────────────────────────────────────────

variable "enable_cert_manager" {
  description = "Instala o cert-manager. Necessário apenas se você for emitir certificados no cluster."
  type        = bool
  default     = false
}

variable "cert_manager_chart_version" {
  description = "Versão do chart do cert-manager."
  type        = string
  default     = "v1.15.3"
}

variable "enable_kube_prometheus_stack" {
  description = "Instala Prometheus, Alertmanager e Grafana. Pesado para o node group de baseline — ligue só com o Karpenter operando."
  type        = bool
  default     = false
}

variable "kube_prometheus_stack_chart_version" {
  description = "Versão do chart do kube-prometheus-stack."
  type        = string
  default     = "62.7.0"
}

# ── Karpenter ─────────────────────────────────────────────────────────────────

variable "karpenter_node_capacity_types" {
  description = "Tipos de capacidade que o NodePool pode provisionar. Spot primeiro, on-demand como fallback quando não há spot disponível."
  type        = list(string)
  default     = ["spot", "on-demand"]
}

variable "karpenter_node_instance_categories" {
  description = "Categorias de instância elegíveis."
  type        = list(string)
  default     = ["t", "m", "c"]
}

variable "karpenter_cpu_limit" {
  description = "Teto de vCPU que o Karpenter pode provisionar no total. É a trava de custo do NodePool."
  type        = number
  default     = 32
}

# ── Argo CD e repositório GitOps ──────────────────────────────────────────────

variable "argocd_namespace" {
  description = "Namespace do Argo CD."
  type        = string
  default     = "argocd"
}

variable "argocd_helm_values" {
  description = "Documentos YAML adicionais para o chart do Argo CD."
  type        = list(string)
  default     = []
}

variable "gitops_repo_url" {
  description = "Repositório que o Argo CD observa. Contém apenas os manifests dos cinco microsserviços."
  type        = string
  default     = "https://github.com/fiap-tech-challenge-devops/togglemaster-gitops.git"
}

variable "gitops_repo_revision" {
  description = "Branch ou tag acompanhada pela Application raiz."
  type        = string
  default     = "main"
}

variable "gitops_root_path" {
  description = "Caminho, dentro do repositório GitOps, da Application raiz do padrão app-of-apps."
  type        = string
  default     = "argocd"
}

variable "gitops_repo_username" {
  description = "Usuário para clonar o repositório GitOps. Desnecessário se o repositório for público."
  type        = string
  default     = null
}

variable "gitops_repo_password" {
  description = "Token de acesso ao repositório GitOps. Passe por TF_VAR_gitops_repo_password, nunca em arquivo versionado."
  type        = string
  default     = null
  sensitive   = true
}

variable "app_namespace" {
  description = "Namespace dos microsserviços. Precisa bater com o que o repositório GitOps usa."
  type        = string
  default     = "togglemaster"
}
