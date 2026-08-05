# ── Rede ──────────────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "ID da VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas."
  value       = module.vpc.private_subnet_ids
}

# ── EKS ───────────────────────────────────────────────────────────────────────
output "cluster_name" {
  description = "Nome do cluster EKS. Consumido pelo workflow de apply."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do cluster."
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster."
  value       = module.eks.oidc_provider_arn
}

output "update_kubeconfig_command" {
  description = "Comando para apontar o kubectl local para o cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# ── Karpenter ─────────────────────────────────────────────────────────────────
# Valores que o repositório GitOps referencia nos values do chart e no EC2NodeClass.
output "karpenter" {
  description = "Valores do Karpenter para o repositório GitOps."
  value = {
    controller_role_arn     = module.karpenter.controller_role_arn
    node_role_name          = module.karpenter.node_role_name
    interruption_queue_name = module.karpenter.interruption_queue_name
    chart_version           = var.karpenter_chart_version
  }
}

output "lb_controller_role_arn" {
  description = "ARN da role do AWS Load Balancer Controller."
  value       = module.lb_controller.role_arn
}

# ── Bancos e mensageria ───────────────────────────────────────────────────────
output "rds_endpoints" {
  description = "Endpoints dos três RDS."
  value       = { for k, m in module.rds : k => m.db_instance_endpoint }
}

output "rds_secret_names" {
  description = "Nomes dos secrets com as connection strings. É o valor de remoteRef.key nos ExternalSecrets."
  value       = { for k, m in module.rds_secret : k => m.secret_name }
}

output "redis_url" {
  description = "URL de conexão do Redis."
  value       = "redis://${module.redis.primary_endpoint_address}:${module.redis.port}/0"
}

output "sqs_queue_url" {
  description = "URL da fila de eventos de avaliação."
  value       = module.sqs.queue_url
}

output "sqs_queue_arn" {
  description = "ARN da fila de eventos de avaliação."
  value       = module.sqs.queue_arn
}

output "dynamodb_table_name" {
  description = "Nome da tabela de analytics."
  value       = module.dynamodb.table_name
}

# ── ECR ───────────────────────────────────────────────────────────────────────
output "registry_url" {
  description = "URL base do registry — alvo do docker login."
  value       = module.ecr.registry_url
}

output "repository_urls" {
  description = "URL de cada repositório, por serviço. Vai no campo image.repository dos values do GitOps."
  value       = module.ecr.repository_urls
}

output "ci_role_arn" {
  description = "ARN da role de push no ECR. Configure no secret AWS_ROLE_ARN dos repositórios dos microsserviços."
  value       = aws_iam_role.ci.arn
}

# ── Identidades no cluster ────────────────────────────────────────────────────
output "irsa_role_arns" {
  description = "ARNs das roles IRSA, para as annotations dos ServiceAccounts no repositório GitOps."
  value = {
    apps             = module.irsa_apps.role_arn
    external_secrets = module.irsa_eso.role_arn
    keda             = module.irsa_keda.role_arn
  }
}
