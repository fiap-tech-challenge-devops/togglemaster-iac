provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "ToggleMaster"
      ManagedBy = "terraform"
      Stack     = "iac-addons"
    }
  }
}

# Este stage existe separado do infra por causa destas linhas. O Terraform não
# aceita que a configuração de um provider dependa de recursos criados no mesmo
# apply — e os providers abaixo precisam de um cluster que já exista.
#
# A leitura é via SSM, e não via terraform_remote_state, para não acoplar este
# state ao formato interno do outro.
data "aws_ssm_parameter" "cluster_name" {
  name = "/${var.system}/iac/cluster-name"
}

data "aws_eks_cluster" "this" {
  name = nonsensitive(data.aws_ssm_parameter.cluster_name.value)
}

# Token resolvido por exec a cada operação, em vez de um data source: o token do
# EKS expira em 15 minutos, e um valor capturado no plan já estaria vencido no
# apply de um plano grande.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--region", var.region]
    }
  }
}
