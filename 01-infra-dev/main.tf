###############################################################################
# Provider
###############################################################################
terraform {
  required_version = ">= 1.6"

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
}

###############################################################################
# Data – latest Amazon Linux 2023 AMI (official AWS image)
###############################################################################
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

###############################################################################
# IAM – EC2 role (ECR pull only)
###############################################################################
resource "aws_iam_role" "ec2" {
  name = "${local.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

###############################################################################
# ECR Pull Policy (minimal required permissions)
###############################################################################
resource "aws_iam_role_policy" "ecr_pull" {
  name = "${local.name_prefix}-ecr-pull"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

###############################################################################
# Instance Profile
###############################################################################
resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}

###############################################################################
# User-data – runs as root; installs Docker, Docker Compose, clones repo
# Everything is placed under /home/ec2-user so the default user owns it.
###############################################################################
locals {
  user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail

    # ── System update ────────────────────────────────────────────────────────
    dnf update -y

    # ── Docker + AWS CLI ─────────────────────────────────────────────────────
    dnf install -y docker git aws-cli
    systemctl enable --now docker
    usermod -aG docker ec2-user

    # ── Docker Compose v2 CLI plugin ─────────────────────────────────────────
    COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
      | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL \
      "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    # Install plugin for ec2-user as well
    mkdir -p /home/ec2-user/.docker/cli-plugins
    ln -sf /usr/local/lib/docker/cli-plugins/docker-compose \
      /home/ec2-user/.docker/cli-plugins/docker-compose
    chown -R ec2-user:ec2-user /home/ec2-user/.docker

    # ── Clone repository ─────────────────────────────────────────────────────
    REPO_DIR="/home/ec2-user/app"
    git clone "${var.repo_url}" "$REPO_DIR"
    chown -R ec2-user:ec2-user "$REPO_DIR"

    # ── ECR login helper script ───────────────────────────────────────────────
    tee /usr/local/bin/ecr-login > /dev/null <<'EOF'
    #!/bin/bash
    aws ecr get-login-password --region ${var.aws_region} \
      | docker login --username AWS --password-stdin \
          "$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${var.aws_region}.amazonaws.com"
    EOF
    chmod +x /usr/local/bin/ecr-login

    # ── Create systemd service for Docker Compose ────────────────────────────
    tee /etc/systemd/system/app.service > /dev/null <<'EOF'
    [Unit]
    Description=Docker Compose App (03-dev)
    Documentation=https://docs.docker.com/compose
    After=network.target docker.service
    Requires=docker.service

    [Service]
    Type=simple
    User=ec2-user
    Group=ec2-user
    WorkingDirectory=/home/ec2-user/app/03-dev
    ExecStartPre=/usr/local/bin/ecr-login
    ExecStartPre=/usr/bin/docker compose pull --ignore-pull-failures
    ExecStart=/usr/bin/docker compose up --build
    ExecStop=/usr/bin/docker compose down
    Restart=on-failure
    RestartSec=10
    StartLimitIntervalSec=60
    StartLimitBurst=3
    StandardOutput=journal
    StandardError=journal

    [Install]
    WantedBy=multi-user.target
    EOF

    # ── Enable and start the service ─────────────────────────────────────────
    systemctl daemon-reload
    systemctl enable app.service
    systemctl start app.service

    echo "Bootstrap complete" | tee /var/log/bootstrap-complete
  EOT
}

###############################################################################
# EC2 Instance
###############################################################################
resource "aws_instance" "this" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data                   = local.user_data

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only – security best practice
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ec2" })

  lifecycle {
    ignore_changes = [ami]
  }
}

###############################################################################
# Elastic IP
###############################################################################
resource "aws_eip" "this" {
  instance = aws_instance.this.id
  domain   = "vpc"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-eip" })
}