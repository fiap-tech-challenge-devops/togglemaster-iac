terraform {
  # Backend parcial: bucket, region e use_lockfile vêm por -backend-config.
  backend "s3" {
    key = "togglemaster/addons.tfstate"
  }
}
