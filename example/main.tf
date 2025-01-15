# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.10.4"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
    # see https://registry.terraform.io/providers/hashicorp/cloudinit
    # see https://github.com/hashicorp/terraform-provider-cloudinit
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.5"
    }
    # see https://registry.terraform.io/providers/hashicorp/aws
    # see https://github.com/hashicorp/terraform-provider-aws
    aws = {
      source  = "hashicorp/aws"
      version = "5.83.1"
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

variable "vpc_cidr" {
  type        = string
  description = "Defines the CIDR block."
  default     = "10.42.0.0/16"
  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.vpc_cidr))
    error_message = "Invalid CIDR block format. Please provide a valid CIDR block."
  }
}

variable "image_name" {
  type    = string
  default = "rgl-ubuntu"
}

variable "name_prefix" {
  type    = string
  default = "rgl-ubuntu"
}

locals {
  azs             = slice(data.aws_availability_zones.available.names, 0, 1)
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 3, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 3, k + 3)]
  app_ip_address  = cidrhost(local.public_subnets[0], 4)
  app_subnet_id   = module.vpc.public_subnets[0]
}

data "aws_availability_zones" "available" {
  state = "available"
}

# see https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws
# see https://github.com/terraform-aws-modules/terraform-aws-vpc
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.17.0"

  name            = var.name_prefix
  azs             = local.azs
  cidr            = var.vpc_cidr
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets
}

# NB this user cannot be "admin" nor "test" nor whatever Azure decided to deny.
variable "admin_username" {
  type    = string
  default = "rgl"
}

variable "admin_password" {
  type      = string
  default   = "HeyH0Password"
  sensitive = true
}

# NB when you run make terraform-apply this is set from the TF_VAR_admin_ssh_key_data environment variable, which comes from the ~/.ssh/id_rsa.pub file.
variable "admin_ssh_key_data" {}

output "app_ip_address" {
  value = aws_eip.app.public_ip
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity
data "aws_caller_identity" "current" {}

# also see https://cloud-images.ubuntu.com/locator/ec2/
# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "name"
    values = [var.image_name]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair
resource "aws_key_pair" "admin" {
  key_name   = "${var.name_prefix}-app-admin"
  public_key = var.admin_ssh_key_data
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface
resource "aws_network_interface" "app" {
  subnet_id       = local.app_subnet_id
  private_ips     = [local.app_ip_address]
  security_groups = [aws_security_group.app.id]
  tags = {
    Name = "${var.name_prefix}-app"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip
resource "aws_eip" "app" {
  domain                    = "vpc"
  associate_with_private_ip = aws_network_interface.app.private_ip
  instance                  = aws_instance.app.id
  depends_on                = [module.vpc]
  tags = {
    Name = "${var.name_prefix}-app"
  }
}

# NB the guest firewall is also configured by provision-firewall.sh.
# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "app" {
  vpc_id      = module.vpc.vpc_id
  name        = "app"
  description = "Application"
  tags = {
    Name = "${var.name_prefix}-app"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  tags = {
    Name = "${var.name_prefix}-app-ssh"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  tags = {
    Name = "${var.name_prefix}-app-http"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags = {
    Name = "${var.name_prefix}-app-all"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "app" {
  name = "${var.name_prefix}-app"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app.arn
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy
resource "aws_iam_policy" "app" {
  name = "${var.name_prefix}-app"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
        ]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${aws_iam_instance_profile.app.role}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:DescribeParameters"]
        Resource = "*"
      }
    ]
  })
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
resource "aws_iam_instance_profile" "app" {
  name = "${var.name_prefix}-app"
  role = aws_iam_role.app.name
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter
resource "aws_ssm_parameter" "app_message" {
  name  = "/${aws_iam_instance_profile.app.role}/message"
  type  = "String"
  value = "Hello, World!"
}

# see https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/config
# NB this can be read from the instance-metadata-service.
#    see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
# NB ANYTHING RUNNING IN THE VM CAN READ THIS DATA FROM THE INSTANCE-METADATA-SERVICE
#    UNLESS the firewall limits the access, like we do in provision-firewall.sh.
# NB cloud-init executes **all** these parts regardless of their result. they
#    should be idempotent.
# NB the output is saved at /var/log/cloud-init-output.log
data "cloudinit_config" "app" {
  part {
    content_type = "text/cloud-config"
    content      = <<-EOF
    #cloud-config
    runcmd:
      - echo 'Hello from cloud-config runcmd!'
    EOF
  }
  part {
    content_type = "text/x-shellscript"
    content      = file("provision-firewall.sh")
  }
  part {
    content_type = "text/x-shellscript"
    content      = file("provision-app.sh")
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "app" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "t3.micro" # 2 cpu. 1 GiB RAM. Nitro System. see https://aws.amazon.com/ec2/instance-types/t3/
  iam_instance_profile = aws_iam_instance_profile.app.name
  key_name             = aws_key_pair.admin.key_name
  user_data_base64     = data.cloudinit_config.app.rendered
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  network_interface {
    network_interface_id = aws_network_interface.app.id
    device_index         = 0
  }
  tags = {
    Name = var.image_name
  }
}
