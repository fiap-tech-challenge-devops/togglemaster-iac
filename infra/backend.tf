terraform {
  # Backend parcial: bucket, region e use_lockfile vêm por -backend-config nos
  # workflows. O bucket é criado pelo stage bootstrap.
  backend "s3" {
    key = "togglemaster/infra.tfstate"
  }
}
