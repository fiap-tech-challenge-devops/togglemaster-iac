# Handoff deste stage para o stage addons e para o repositório GitOps.
#
# O Parameter Store é a fronteira: quem consome não precisa de acesso ao tfstate,
# que fica num bucket restrito e cujo formato é detalhe interno do Terraform.
#
# Os módulos eks-karpenter, eks-aws-lb-controller, ecr e iam-irsa já publicam os
# próprios valores (create_ssm_parameters). Aqui ficam os que não pertencem a
# nenhum módulo específico.

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

# URL completa, e não host e porta separados: é o formato que o evaluation-service
# espera na variável de ambiente.
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

resource "aws_ssm_parameter" "registry_url" {
  name        = "${local.ssm_prefix}/ecr/registry-url"
  description = "URL base do registry ECR — alvo do docker login nas esteiras."
  type        = "String"
  value       = module.ecr.registry_url

  tags = local.tags
}

# A versão do chart do Karpenter é decisão de infraestrutura (depende da versão do
# Kubernetes), mas quem instala o chart é o Argo CD. Publicar aqui evita que os
# dois repositórios divirjam silenciosamente.
resource "aws_ssm_parameter" "karpenter_chart_version" {
  name        = "${local.ssm_prefix}/karpenter/chart-version"
  description = "Versão do chart do Karpenter compatível com a versão do cluster."
  type        = "String"
  value       = var.karpenter_chart_version

  tags = local.tags
}
