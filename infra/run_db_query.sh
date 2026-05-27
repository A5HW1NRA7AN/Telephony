#!/bin/bash
# ==============================================================================
# Database Query Helper Script for Asterisk Ingestion Logs
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

echo "[+] Connecting to private database host $PRIVATE_IP (via Bastion: $BASTION_IP)..."

# Run query inside the Postgres container on the private host
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -W %h:%p admin@$BASTION_IP" admin@$PRIVATE_IP \
  "sudo docker exec -i \$(sudo docker ps -qf name=postgres) psql -P pager=off -U lead_user -d lead_db -c \"SELECT id, processing_status, idempotency_key, asterisk_unique_id, sent_at FROM telephony_call_lead_ingest_log ORDER BY updated_at DESC LIMIT 5;\""
