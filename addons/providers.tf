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

data "aws_ssm_parameter" "cluster_name" {
  name = "/${var.system}/iac/cluster-name"
}

data "aws_eks_cluster" "this" {
  name = nonsensitive(data.aws_ssm_parameter.cluster_name.value)
}

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
