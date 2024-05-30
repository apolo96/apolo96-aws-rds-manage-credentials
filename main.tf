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
      Environment = "test"
      ProjectID   = "dragon"
    }
  }
}

resource "aws_security_group" "lambda_sg" {
  name   = "lambda-dragon-security-group"
  vpc_id = aws_default_vpc.default.id
}


