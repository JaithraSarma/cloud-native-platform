terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Remote state in S3 with DynamoDB locking (configure per environment)
  # backend "s3" {
  #   bucket         = "tfstate-cloudplatform"
  #   key            = "aws/cloud-platform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "tfstate-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}
