#!/bin/bash
# ==============================================================================
# Remote Service Restart Script for Asterisk & Lead-Service Stack
# ==============================================================================

set -e

# Change directory to the infra folder (where the script is located)
cd "$(dirname "$0")"

# Verify terraform outputs exist
if ! terraform output > /dev/null 2>&1; then
  echo "[-] Terraform outputs not found. Run 'terraform apply' first."
  exit 1
fi

echo "[+] Fetching network details from Terraform..."
BASTION_IP=$(terraform output -raw bastion_public_ip)
PRIVATE_IP=$(terraform output -raw asterisk_private_ip)
KEY_FILE="asterisk-key.pem"

if [ -z "$BASTION_IP" ] || [ -z "$PRIVATE_IP" ]; then
  echo "[-] Failed to fetch IPs from Terraform outputs."
  exit 1
fi

echo "[+] Connecting to private host $PRIVATE_IP (via Bastion: $BASTION_IP)..."

# SSH and restart services
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -W %h:%p admin@$BASTION_IP" admin@$PRIVATE_IP "bash -s" <<EOF
  set -e
  echo "[+] Restarting Asterisk service on host..."
  sudo systemctl restart asterisk
  sleep 2

  echo "[+] Rebuilding and restarting docker compose stack..."
  cd /home/admin/asterisk
  # If a .env file doesn't exist yet on first deploy, create it from example
  if [ ! -f .env ]; then
    echo "[!] .env file not found. Initializing with defaults from .env.example..."
    cp .env.example .env
    echo "[!] Please remember to update /home/admin/asterisk/.env with correct registry settings."
  fi
  
  sudo docker compose up -d --build
EOF

echo "[+] All services successfully restarted."
