# ── Security Groups ───────────────────────────────────────────────────────────

# 1. Bastion SG: Accessible from anywhere for SSH jump-host access
resource "aws_security_group" "bastion_sg" {
  name        = "${var.cluster_name}-bastion-sg"
  description = "Security group for Bastion jump host"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-bastion-sg"
  }
}

# 2. Proxy SG: Inbound HTTP/SIP/RTP from external, SSH only from Bastion
resource "aws_security_group" "proxy_sg" {
  name        = "${var.cluster_name}-proxy-sg"
  description = "Security group for Nginx and SIP/RTP proxy"
  vpc_id      = module.vpc.vpc_id

  # SSH only from Bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Inbound HTTP/HTTPS from whitelisted CIDRs
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_ingress_cidrs
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_ingress_cidrs
  }

  # Inbound SIP signalling from Twilio
  ingress {
    from_port   = 5060
    to_port     = 5060
    protocol    = "udp"
    cidr_blocks = var.sip_signalling_cidrs
  }

  ingress {
    from_port   = 5060
    to_port     = 5060
    protocol    = "tcp"
    cidr_blocks = var.sip_signalling_cidrs
  }

  # Inbound RTP media from Twilio (Asterisk uses 10000-20000)
  ingress {
    from_port   = 10000
    to_port     = 20000
    protocol    = "udp"
    cidr_blocks = var.sip_media_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-proxy-sg"
  }
}

# 3. Asterisk SG: Inbound ONLY from Bastion and Proxy, full access within VPC
resource "aws_security_group" "asterisk_sg" {
  name        = "${var.cluster_name}-asterisk-sg"
  description = "Security group for private Asterisk server"
  vpc_id      = module.vpc.vpc_id

  # SSH only from Bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # All TCP and UDP traffic from Proxy (covers HTTP reverse proxying and forwarded SIP/RTP)
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.proxy_sg.id]
  }

  # Full communication within VPC subnets
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-asterisk-sg"
  }
}
