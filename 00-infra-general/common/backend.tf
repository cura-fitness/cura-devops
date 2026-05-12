# main/backend.tf
terraform {
  backend "s3" {
    bucket       = "cura-infra-terraform-state"
    key          = "common/terraform.tfstate"
    region       = "ap-south-2"
    encrypt      = true
    use_lockfile = true
  }
}