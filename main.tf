terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "tfaws"
  default_tags {
    tags = {
      Environment  = var.environment
      ProjectID    = "dragon"
      Organization = var.organization
    }
  }
}


