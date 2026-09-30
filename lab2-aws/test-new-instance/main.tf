terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-1"
}

# Set true to reproduce Test 2 (AccessDenied). Set false for Test 3 (compliant launch).
variable "associate_public_ip" {
  type    = bool
  default = true
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

data "aws_vpc" "lab" {
  filter {
    name   = "tag:Name"
    values = ["lab1-vpc"]
  }
}

data "aws_subnet" "public" {
  filter {
    name   = "tag:Name"
    values = ["lab1-public-a"]
  }
}

data "aws_subnet" "private" {
  filter {
    name   = "tag:Name"
    values = ["lab1-private-a"]
  }
}

data "aws_security_group" "ec2" {
  filter {
    name   = "group-name"
    values = ["lab1-ec2-sg"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.lab.id]
  }
}

data "aws_key_pair" "lab" {
  key_name = "lab1-ec2-key"
}

# Non-compliant: public subnet + public IP (denied by DenyEc2PublicIp).
# Compliant: private subnet + no public IP.
resource "aws_instance" "lab2" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = var.associate_public_ip ? data.aws_subnet.public.id : data.aws_subnet.private.id
  vpc_security_group_ids      = [data.aws_security_group.ec2.id]
  key_name                    = data.aws_key_pair.lab.key_name
  associate_public_ip_address = var.associate_public_ip

  tags = {
    Name   = "lab2-ec2"
    Lab    = "lab2"
    Public = tostring(var.associate_public_ip)
  }
}

output "instance_id" {
  value = aws_instance.lab2.id
}

output "private_ip" {
  value = aws_instance.lab2.private_ip
}

output "public_ip" {
  value = aws_instance.lab2.public_ip
}

output "subnet_id" {
  value = aws_instance.lab2.subnet_id
}
