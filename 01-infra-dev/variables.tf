###############################################################################
# Variables
###############################################################################


variable "aws_region" {
  default = "ap-south-2"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
  default     = "aws-digi"
}

variable "repo_url" {
  description = "Git repository URL to clone on the instance"
  type        = string
  default = "https://github.com/cura-fitness/cura-devops"
}

variable "project" {
  description = "Project name - used for resource naming and tagging"
  type        = string
  default     = "cura"
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}