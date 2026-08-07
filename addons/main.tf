
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
