# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.11.0"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/aws
    # see https://github.com/hashicorp/terraform-provider-aws
    aws = {
      source  = "hashicorp/aws"
      version = "5.89.0"
    }
    # see https://registry.terraform.io/providers/hashicorp/local
    # see https://github.com/hashicorp/terraform-provider-local
    local = {
      source  = "hashicorp/local"
      version = "2.5.2"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Owner = "rgl"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "vpc_name" {
  type    = string
  default = "rgl-ubuntu"
}

variable "vpc_cidr" {
  type        = string
  description = "Defines the CIDR block."
  default     = "10.42.0.0/16"
  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.vpc_cidr))
    error_message = "Invalid CIDR block format. Please provide a valid CIDR block."
  }
}

locals {
  azs             = slice(data.aws_availability_zones.available.names, 0, 1)
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 3, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 3, k + 3)]
}

data "aws_availability_zones" "available" {
  state = "available"
}

# see https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws
# see https://github.com/terraform-aws-modules/terraform-aws-vpc
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name            = var.vpc_name
  azs             = local.azs
  cidr            = var.vpc_cidr
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets
}

resource "local_file" "packer_vpc" {
  content  = <<-EOF
  region    = ${jsonencode(var.region)}
  subnet_id = ${jsonencode(module.vpc.public_subnets[0])}
  EOF
  filename = "${path.module}/../vpc.auto.pkrvars.hcl"
}
