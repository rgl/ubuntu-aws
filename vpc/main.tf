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
  version = "5.13.0"

  name            = var.vpc_name
  azs             = local.azs
  cidr            = var.vpc_cidr
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets
}

resource "local_file" "packer_vpc" {
  content  = <<-EOF
  subnet_id = "${module.vpc.public_subnets[0]}"
  EOF
  filename = "${path.module}/../vpc.auto.pkrvars.hcl"
}
