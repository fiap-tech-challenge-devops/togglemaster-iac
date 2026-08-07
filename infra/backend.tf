terraform {
  backend "s3" {
    key = "togglemaster/infra.tfstate"
  }
}
