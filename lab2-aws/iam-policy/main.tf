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

# Reuse Lab 1 identities — do not create new users.
data "aws_iam_user" "terraform_deployer" {
  user_name = "terraform-deployer"
}

data "aws_iam_user" "cloud_engineer" {
  user_name = "cloud-engineer"
}

data "aws_iam_role" "devops_admin" {
  name = "DevOpsAdminRole"
}

data "aws_iam_role" "terraform_deployer" {
  name = "TerraformDeployerRole"
}

data "aws_instance" "lab1" {
  filter {
    name   = "tag:Name"
    values = ["lab1-ec2"]
  }

  filter {
    name   = "instance-state-name"
    values = ["pending", "running", "stopping", "stopped"]
  }
}

# Marker on the existing Lab 1 instance (in-place tag, not a recreate).
# StartInstances does not send ec2:AssociatePublicIpAddress, so the Bool
# condition below never matches on start. This tag is the enforceable stand-in.
# true = Lab 1 instance is still "would get a public IP on start" (Tests 4).
# false = remediated in place (Test 5). Does not replace the instance.
variable "lab1_public_ip_on_start" {
  type    = bool
  default = true
}

resource "aws_ec2_tag" "lab1_public_ip" {
  resource_id = data.aws_instance.lab1.id
  key         = "AssociatePublicIp"
  value       = var.lab1_public_ip_on_start ? "true" : "false"
}

# Preventive guardrail (IAM stand-in for an Organizations SCP).
# Deny is explicit: it wins over AdministratorAccess on the same identity.
data "aws_iam_policy_document" "deny_public_ip" {
  statement {
    sid    = "DenyEc2PublicIp"
    effect = "Deny"

    actions = [
      "ec2:RunInstances",
      "ec2:StartInstances",
    ]

    # RunInstances evaluates AssociatePublicIpAddress on the ENI.
    resources = [
      "arn:aws:ec2:*:*:network-interface/*",
      "arn:aws:ec2:*:*:instance/*",
    ]

    condition {
      test     = "Bool"
      variable = "ec2:AssociatePublicIpAddress"
      values   = ["true"]
    }
  }

  # StartInstances: IAM/SCP never receive AssociatePublicIpAddress on that API,
  # so a resource tag is used. Flip it to false (no instance replace) for Test 5.
  statement {
    sid       = "DenyStartIfPublicIpTagged"
    effect    = "Deny"
    actions   = ["ec2:StartInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/AssociatePublicIp"
      values   = ["true"]
    }
  }
}

resource "aws_iam_policy" "deny_public_ip" {
  name        = "DenyEc2PublicIp"
  description = "Lab 2 SCP substitute: deny launching or starting EC2 with a public IP"
  policy      = data.aws_iam_policy_document.deny_public_ip.json
}

resource "aws_iam_user_policy_attachment" "terraform_deployer" {
  user       = data.aws_iam_user.terraform_deployer.user_name
  policy_arn = aws_iam_policy.deny_public_ip.arn
}

resource "aws_iam_user_policy_attachment" "cloud_engineer" {
  user       = data.aws_iam_user.cloud_engineer.user_name
  policy_arn = aws_iam_policy.deny_public_ip.arn
}

resource "aws_iam_role_policy_attachment" "devops_admin" {
  role       = data.aws_iam_role.devops_admin.name
  policy_arn = aws_iam_policy.deny_public_ip.arn
}

resource "aws_iam_role_policy_attachment" "terraform_deployer" {
  role       = data.aws_iam_role.terraform_deployer.name
  policy_arn = aws_iam_policy.deny_public_ip.arn
}

output "policy_arn" {
  value = aws_iam_policy.deny_public_ip.arn
}

output "policy_name" {
  value = aws_iam_policy.deny_public_ip.name
}

output "attached_to" {
  value = {
    users = [
      data.aws_iam_user.terraform_deployer.user_name,
      data.aws_iam_user.cloud_engineer.user_name,
    ]
    roles = [
      data.aws_iam_role.devops_admin.name,
      data.aws_iam_role.terraform_deployer.name,
    ]
  }
}
