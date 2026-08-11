
locals {
  ssm_prefix = "/${var.system}/iac"
}

resource "aws_ssm_parameter" "cluster_name" {
  name        = "${local.ssm_prefix}/cluster-name"
  description = "Nome do cluster EKS. Lido pelo stage addons para configurar os providers."
  type        = "String"
  value       = module.eks.cluster_name

  tags = local.tags
}

resource "aws_ssm_parameter" "oidc_provider_arn" {
  name        = "${local.ssm_prefix}/oidc-provider-arn"
  description = "ARN do OIDC provider do cluster, para criar novas roles IRSA."
  type        = "String"
  value       = module.eks.oidc_provider_arn

  tags = local.tags
}

resource "aws_ssm_parameter" "oidc_provider_url" {
  name        = "${local.ssm_prefix}/oidc-provider-url"
  description = "URL do issuer OIDC do cluster."
  type        = "String"
  value       = module.eks.oidc_provider_url

  tags = local.tags
}

resource "aws_ssm_parameter" "vpc_id" {
  name        = "${local.ssm_prefix}/vpc-id"
  description = "ID da VPC do cluster."
  type        = "String"
  value       = module.vpc.vpc_id

  tags = local.tags
}

resource "aws_ssm_parameter" "redis_url" {
  name        = "${local.ssm_prefix}/redis-url"
  description = "REDIS_URL do evaluation-service."
  type        = "String"
  value       = "redis://${module.redis.primary_endpoint_address}:${module.redis.port}/0"

  tags = local.tags
}

resource "aws_ssm_parameter" "sqs_queue_url" {
  name        = "${local.ssm_prefix}/sqs-queue-url"
  description = "URL da fila de eventos de avaliação."
  type        = "String"
  value       = module.sqs.queue_url

  tags = local.tags
}

resource "aws_ssm_parameter" "karpenter_chart_version" {
  name        = "${local.ssm_prefix}/karpenter/chart-version"
  description = "Versão do chart do Karpenter compatível com a versão do cluster."
  type        = "String"
  value       = var.karpenter_chart_version

  tags = local.tags
}
