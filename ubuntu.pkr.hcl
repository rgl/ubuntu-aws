packer {
  required_plugins {
    # see https://github.com/hashicorp/packer-plugin-amazon
    amazon = {
      version = "1.3.4"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "subnet_id" {
  type = string
}

variable "image_name" {
  type    = string
  default = "rgl-ubuntu"
}

source "amazon-ebs" "ubuntu" {
  # NB you can list the current images with aws cli as, e.g.:
  #     aws ec2 describe-images \
  #       --region eu-west-1 \
  #       --owners 099720109477 \
  #       --filters \
  #         'Name=name,Values=ubuntu/images/*/ubuntu-*-22.04-amd64-server-*' \
  #         'Name=state,Values=available' \
  #       --query 'Images[*].[CreationDate,Name,ImageId]' \
  #       --no-cli-pager \
  #       --output json \
  #       | jq -r 'sort_by(.[0]) | reverse | .[] | @tsv' \
  #       | head -3
  # e.g. ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20250112
  source_ami_filter {
    most_recent = true
    owners      = ["099720109477"] # Canonical.
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
  }
  region                      = var.region
  temporary_key_pair_name     = var.image_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  ami_name                    = var.image_name
  ami_description             = "See https://github.com/rgl/ubuntu-aws."
  instance_type               = "t3.micro" # 2 cpu. 1 GiB RAM. Nitro System. see https://aws.amazon.com/ec2/instance-types/t3/
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  imds_support = "v2.0"
  ssh_username = "ubuntu"
  run_volume_tags = {
    Name  = var.image_name
    Owner = "rgl"
  }
  run_tags = {
    Name  = var.image_name
    Owner = "rgl"
  }
  tags = {
    Name  = var.image_name
    Owner = "rgl"
  }
}

build {
  sources = [
    "source.amazon-ebs.ubuntu"
  ]

  provisioner "shell" {
    execute_command = "sudo -S {{ .Vars }} bash {{ .Path }}"
    scripts = [
      "upgrade.sh",
    ]
  }

  provisioner "shell" {
    execute_command   = "sudo -S {{ .Vars }} bash {{ .Path }}"
    expect_disconnect = true
    inline            = ["set -eux && reboot"]
  }

  provisioner "shell" {
    execute_command = "sudo -S {{ .Vars }} bash {{ .Path }}"
    inline          = ["set -eux && cloud-init status --long --wait"]
  }

  provisioner "shell" {
    execute_command = "sudo -S {{ .Vars }} bash {{ .Path }}"
    scripts = [
      "provision.sh",
    ]
  }

  provisioner "shell" {
    execute_command = "sudo -S {{ .Vars }} bash {{ .Path }}"
    scripts = [
      "provision-docker.sh",
      "provision-docker-compose.sh",
    ]
  }

  provisioner "shell" {
    execute_command = "sudo -S {{ .Vars }} bash {{ .Path }}"
    scripts = [
      "generalize.sh",
    ]
  }

  post-processor "manifest" {
    output     = "ubuntu-packer-manifest.json"
    strip_path = true
  }
}
