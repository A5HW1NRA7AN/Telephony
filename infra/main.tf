terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── SSH Key (auto-generated) ──────────────────────────────────────────────────

resource "tls_private_key" "asterisk_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "asterisk_key_pair" {
  key_name   = var.key_name
  public_key = tls_private_key.asterisk_key.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.asterisk_key.private_key_pem
  filename        = "${path.module}/asterisk-key.pem"
  file_permission = "0400"
}

# ── VPC for EC2 ──────────────────────────────────────────────────────────────

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Environment = "Dev"
    Project     = "Asterisk-Telephony"
  }
}

