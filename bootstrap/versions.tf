terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Sem bloco backend versionado, de propósito.
  #
  # Na primeira execução o backend S3 ainda não pode existir — o bucket dele é o
  # que este stage cria. Depois do apply, o workflow gera um backend.tf e roda
  # `terraform init -force-copy`, migrando o state para o bucket. Da segunda
  # execução em diante o stage usa backend remoto como qualquer outro, e
  # converge normalmente.
  #
  # O backend.tf gerado é ignorado pelo git (ver .gitignore).
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
