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
  type        = string
  default     = "us-west-1"
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# terraform-deployer — machine identity that applies 02-infrastructure
# -----------------------------------------------------------------------------

resource "aws_iam_user" "tf_deployer" {
  name = "terraform-deployer"
  path = "/"

  tags = {
    Lab  = "lab1"
    Role = "terraform-deployer"
  }
}

resource "aws_iam_user_policy_attachment" "tf_deployer_admin" {
  user       = aws_iam_user.tf_deployer.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_access_key" "tf_deployer" {
  user = aws_iam_user.tf_deployer.name
}

# Optional role the deployer can assume (satisfies "role attached" wording).
data "aws_iam_policy_document" "tf_deployer_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.tf_deployer.arn]
    }
  }
}

resource "aws_iam_role" "tf_deployer" {
  name               = "TerraformDeployerRole"
  assume_role_policy = data.aws_iam_policy_document.tf_deployer_assume.json
}

resource "aws_iam_role_policy_attachment" "tf_deployer" {
  role       = aws_iam_role.tf_deployer.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# -----------------------------------------------------------------------------
# cloud-engineer — human operator. No direct resource permissions.
# -----------------------------------------------------------------------------

resource "aws_iam_user" "cloud_engineer" {
  name = "cloud-engineer"
  path = "/"

  tags = {
    Lab  = "lab1"
    Role = "human-operator"
  }
}

resource "aws_iam_user_login_profile" "cloud_engineer" {
  user                    = aws_iam_user.cloud_engineer.name
  password_reset_required = false
  password_length         = 20
}

resource "aws_iam_access_key" "cloud_engineer" {
  user = aws_iam_user.cloud_engineer.name
}

# Only permission: assume DevOpsAdminRole. Nothing else.
data "aws_iam_policy_document" "cloud_engineer_assume_only" {
  statement {
    sid       = "AllowAssumeDevOpsAdmin"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.devops_admin.arn]
  }
}

resource "aws_iam_user_policy" "cloud_engineer_assume_only" {
  name   = "AssumeDevOpsAdminOnly"
  user   = aws_iam_user.cloud_engineer.name
  policy = data.aws_iam_policy_document.cloud_engineer_assume_only.json
}

# -----------------------------------------------------------------------------
# DevOpsAdminRole — what cloud-engineer uses to actually operate
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.cloud_engineer.arn]
    }
  }
}

resource "aws_iam_role" "devops_admin" {
  name               = "DevOpsAdminRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json

  tags = {
    Lab = "lab1"
  }
}

resource "aws_iam_role_policy_attachment" "devops_admin_permissions" {
  role       = aws_iam_role.devops_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "terraform_deployer_access_key_id" {
  value = aws_iam_access_key.tf_deployer.id
}

output "terraform_deployer_secret_access_key" {
  value     = aws_iam_access_key.tf_deployer.secret
  sensitive = true
}

output "cloud_engineer_console_password" {
  value     = aws_iam_user_login_profile.cloud_engineer.password
  sensitive = true
}

output "cloud_engineer_access_key_id" {
  value = aws_iam_access_key.cloud_engineer.id
}

output "cloud_engineer_secret_access_key" {
  value     = aws_iam_access_key.cloud_engineer.secret
  sensitive = true
}

output "devops_admin_role_arn" {
  value = aws_iam_role.devops_admin.arn
}

output "console_sign_in_url" {
  value = "https://${data.aws_caller_identity.current.account_id}.signin.aws.amazon.com/console"
}
