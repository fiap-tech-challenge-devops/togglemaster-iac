terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Sem bloco backend: este stage roda com state LOCAL, porque é ele que cria o
  # bucket onde os demais stages guardam o state. O state gerado aqui é
  # descartável — o workflow iac-bootstrap.yml verifica a existência do bucket
  # antes de aplicar, então reexecutar sem o state não recria nada.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "ToggleMaster"
      ManagedBy = "terraform"
      Stack     = "iac-bootstrap"
    }
  }
}
