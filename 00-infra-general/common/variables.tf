variable "aws_region" {
  default = "eu-south-1"
}

variable "project" {
  description = "Project name - used for resource naming and tagging"
  type        = string
  default     = "cura"
}

variable "environment" {
  description = "Environment name (e.g. dev, common, prod)"
  type        = string
  default     = "common"
}