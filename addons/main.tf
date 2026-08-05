# Componentes que rodam dentro do cluster.
#
# A divisão entre este stage e o Argo CD é por DONO, não por ferramenta: cada
# recurso tem exatamente um. O Terraform é dono da plataforma — controllers que
# nascem e morrem com o cluster e mudam a cada trimestre. O Argo CD é dono dos
# cinco microsserviços, que mudam a cada merge.
#
# O que quebra numa arquitetura assim não é Terraform ou GitOps: é os dois
# gerenciando o mesmo recurso e revertendo um ao outro a cada reconcile.

# ── Valores publicados pelo stage infra ───────────────────────────────────────
# Lidos do Parameter Store, e não por terraform_remote_state: este state não
# precisa conhecer o formato interno do outro, só o contrato dos parâmetros.
locals {
  ssm_prefix = "/${var.system}/iac"
}

data "aws_ssm_parameter" "vpc_id" {
  name = "${local.ssm_prefix}/vpc-id"
}

data "aws_ssm_parameter" "lb_controller_role_arn" {
  name = "${local.ssm_prefix}/lb-controller/role-arn"
}

data "aws_ssm_parameter" "external_secrets_role_arn" {
  name = "${local.ssm_prefix}/irsa/external-secrets-role-arn"
}

data "aws_ssm_parameter" "keda_role_arn" {
  name = "${local.ssm_prefix}/irsa/keda-role-arn"
}

data "aws_ssm_parameter" "karpenter_controller_role_arn" {
  name = "${local.ssm_prefix}/karpenter/controller-role-arn"
}

data "aws_ssm_parameter" "karpenter_node_role_name" {
  name = "${local.ssm_prefix}/karpenter/node-role-name"
}

data "aws_ssm_parameter" "karpenter_interruption_queue" {
  name = "${local.ssm_prefix}/karpenter/interruption-queue-name"
}

# A versão do chart do Karpenter é decisão de infraestrutura — depende da versão
# do Kubernetes —, então vem do stage que conhece essa versão.
data "aws_ssm_parameter" "karpenter_chart_version" {
  name = "${local.ssm_prefix}/karpenter/chart-version"
}

locals {
  cluster_name = data.aws_eks_cluster.this.name

  vpc_id                        = nonsensitive(data.aws_ssm_parameter.vpc_id.value)
  lb_controller_role_arn        = nonsensitive(data.aws_ssm_parameter.lb_controller_role_arn.value)
  external_secrets_role_arn     = nonsensitive(data.aws_ssm_parameter.external_secrets_role_arn.value)
  keda_role_arn                 = nonsensitive(data.aws_ssm_parameter.keda_role_arn.value)
  karpenter_controller_role_arn = nonsensitive(data.aws_ssm_parameter.karpenter_controller_role_arn.value)
  karpenter_node_role_name      = nonsensitive(data.aws_ssm_parameter.karpenter_node_role_name.value)
  karpenter_interruption_queue  = nonsensitive(data.aws_ssm_parameter.karpenter_interruption_queue.value)
  karpenter_chart_version       = nonsensitive(data.aws_ssm_parameter.karpenter_chart_version.value)
}
