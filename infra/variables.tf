variable "aws_region" {
  description = "AWS region to deploy the PBX server"
  type        = string
  default     = "ap-northeast-1"
}

variable "cluster_name" {
  description = "Prefix name for the resources"
  type        = string
  default     = "asterisk-telephony"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for the Asterisk/FreePBX server"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Name for the auto-generated SSH key pair"
  type        = string
  default     = "asterisk-key-pair"
}

variable "allowed_http_ingress_cidrs" {
  description = "List of CIDR blocks allowed to access the HTTP proxy (FreePBX web console, lead-service)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ami_username" {
  description = "Asterisk Manager Interface (AMI) username for lead-service to connect"
  type        = string
}

variable "ami_password" {
  description = "Asterisk Manager Interface (AMI) password"
  type        = string
  sensitive   = true
}

variable "sip_provider_domain" {
  description = "SIP provider domain for the trunk (e.g. your-domain.pstn.twilio.com, or any SIP provider)"
  type        = string
}

variable "sip_provider_ip_ranges" {
  description = "Comma-separated CIDR ranges for SIP signalling from your provider (used in PJSIP identify match)"
  type        = string
  default     = "54.172.60.0/30,54.244.51.0/30,54.171.127.192/30,35.156.191.128/30,54.65.63.192/30,54.169.127.128/30,54.252.254.64/30,177.71.206.192/30"
}

variable "sip_signalling_cidrs" {
  description = "List of CIDR blocks to allow SIP (UDP 5060) inbound — should match your SIP provider's signalling IPs"
  type        = list(string)
  default = [
    "54.172.60.0/30", "54.244.51.0/30", "54.171.127.192/30",
    "35.156.191.128/30", "54.65.63.192/30", "54.169.127.128/30",
    "54.252.254.64/30", "177.71.206.192/30"
  ]
}

variable "sip_media_cidrs" {
  description = "List of CIDR blocks to allow RTP media (UDP 10000-20000) — should match your SIP provider's media IPs"
  type        = list(string)
  default = [
    "54.172.60.0/23", "34.203.250.0/23", "54.244.51.0/24",
    "35.166.33.0/24", "54.171.127.192/26", "52.215.127.0/24",
    "35.156.191.128/26", "18.195.48.0/24", "54.65.63.192/26",
    "3.112.80.0/24", "54.169.127.128/26", "3.0.73.0/24",
    "54.252.254.64/26", "3.104.90.0/24", "177.71.206.192/26",
    "18.228.249.0/24"
  ]
}

variable "inbound_did" {
  description = "Your inbound phone number / DID (e.g. +13364904091)"
  type        = string
}

variable "dialplan_context" {
  description = "Asterisk dialplan context name for inbound calls — must match telephony.lead-context-allowlist in lead-service"
  type        = string
  default     = "from-missed-call"
}
