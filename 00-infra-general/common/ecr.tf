terraform {
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

###############################################################################
# Locals
###############################################################################
locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  ecr_users = {
    reader = {
      name        = "${local.name_prefix}-ecr-reader"
      description = "Allow pulling images from the project ECR repositories"
      actions = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages",
        "ecr:ListImages",
      ]
    }
    writer = {
      name        = "${local.name_prefix}-ecr-writer"
      description = "Allow pushing images to the project ECR repositories"
      actions = [
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages",
        "ecr:ListImages",
      ]
    }
  }
}

###############################################################################
# ECR Repositories
###############################################################################
resource "aws_ecr_repository" "repos" {
  for_each = toset([
    "${local.name_prefix}/back",
    "${local.name_prefix}/front"
  ])

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  tags                 = local.common_tags
}

###############################################################################
# IAM Users
###############################################################################
resource "aws_iam_user" "ecr" {
  for_each = local.ecr_users

  name = each.value.name
  tags = local.common_tags
}

resource "aws_iam_policy" "ecr" {
  for_each = local.ecr_users

  name        = each.value.name
  description = each.value.description

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid      = "ECRAccess"
        Effect   = "Allow"
        Action   = each.value.actions
        Resource = [for repo in aws_ecr_repository.repos : repo.arn]
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_user_policy_attachment" "ecr" {
  for_each = local.ecr_users

  user       = aws_iam_user.ecr[each.key].name
  policy_arn = aws_iam_policy.ecr[each.key].arn
}

###############################################################################
# Outputs
###############################################################################
output "repo_urls" {
  value = {
    for k, v in aws_ecr_repository.repos :
    k => v.repository_url
  }
}

output "ecr_user_arns" {
  value = {
    for k, v in aws_iam_user.ecr :
    k => v.arn
  }
}