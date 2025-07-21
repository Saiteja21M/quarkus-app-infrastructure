# provider configuration for AWS
provider "aws" {
  region     = "eu-central-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.81.0"
    }
  }
  backend "s3" {
    bucket         = "my-terraform-app-state-bucket"
    key            = "terraform/state"
    region         = "eu-central-1"
    use_lockfile   = true
  }
}

variable "aws_access_key" {}
variable "aws_secret_key" {}