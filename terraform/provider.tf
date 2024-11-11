# ./terraform/provider.tf

# terraformとawsプロバイダのバージョン
terraform {
  required_version = ">= 1.6.2, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.4.0"
    }
  }
}

provider "aws" {
  profile = var.profile
  region  = var.region

  default_tags {
    tags = {
      "ManagedBy" = "terraform"
      "Project"   = "tf-study32"
    }
  }
}

# # アカウントIDを動的に取得
# data "aws_caller_identity" "current" {}
