output "state_bucket" {
  description = "Bucket S3 do state remoto. Use em -backend-config=bucket=..."
  value       = aws_s3_bucket.tfstate.id
}

output "iac_role_arn" {
  description = "ARN da role OIDC das esteiras de IaC. Configure no secret AWS_OIDC_ROLE_ARN do repositório."
  value       = aws_iam_role.iac.arn
}

output "github_oidc_provider_arn" {
  description = "ARN do OIDC provider do GitHub, para outras roles federadas (ex.: push no ECR pelas esteiras dos microsserviços)."
  value       = local.github_oidc_arn
}

output "backend_config_hint" {
  description = "Argumentos de -backend-config usados pelos stages infra e addons."
  value       = "-backend-config=bucket=${aws_s3_bucket.tfstate.id} -backend-config=region=${var.region} -backend-config=use_lockfile=true"
}
