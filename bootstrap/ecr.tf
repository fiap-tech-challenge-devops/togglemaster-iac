locals {
  services = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

module "ecr" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//ecr?ref=v0.1.0"

  namespace        = var.system
  repository_names = local.services

  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true

  untagged_image_expiration_days = 7
  max_tagged_images              = 30

  create_ssm_parameters = true
  ssm_parameter_prefix  = "/${var.system}/iac/ecr"

  tags = { System = var.system }
}

resource "aws_ssm_parameter" "registry_url" {
  name        = "/${var.system}/iac/ecr/registry-url"
  description = "URL base do registry ECR — alvo do docker login nas esteiras."
  type        = "String"
  value       = module.ecr.registry_url

  tags = { System = var.system }
}
