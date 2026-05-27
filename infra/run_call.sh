#!/bin/bash
# ==============================================================================
# Inbound Call Simulation Helper for Asterisk
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

echo "[+] Originating test call on private Asterisk server $PRIVATE_IP (via Bastion: $BASTION_IP)..."

# Run channel originate command in Asterisk
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -W %h:%p admin@$BASTION_IP" admin@$PRIVATE_IP \
  "sudo asterisk -rx \"channel originate Local/s@from-missed-call application Playback custom/greeting\""

echo "[+] Test call successfully originated. Check lead-service logs for AMI event capture."
