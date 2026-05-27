#!/bin/bash
# ==============================================================================
# Packaging and Deployment Script for Asterisk Lead-Service Stack
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

echo "[+] Target private server: $PRIVATE_IP (via Bastion: $BASTION_IP)"

# Prepare target directory structures
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -W %h:%p admin@$BASTION_IP" admin@$PRIVATE_IP "mkdir -p /home/admin/asterisk"

echo "[+] Archiving code and configuration files..."
# Create a deployment tarball containing service, compose, and environment configs
tar --exclude='**/target' --exclude='**/.idea' --exclude='**/*.iml' -czf deploy.tar.gz -C .. service docker-compose.yml .env.example

echo "[+] Uploading deployment package to private Asterisk server..."
scp -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -W %h:%p admin@$BASTION_IP" deploy.tar.gz admin@$PRIVATE_IP:/home/admin/asterisk/deploy.tar.gz

echo "[+] Copying greeting audio asset..."
scp -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -W %h:%p admin@$BASTION_IP" greeting.mp3 admin@$PRIVATE_IP:/tmp/greeting.mp3

echo "[+] Extracting files and setting up greeting audio..."
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -W %h:%p admin@$BASTION_IP" admin@$PRIVATE_IP "bash -s" <<EOF
  set -e
  # Extract deployment package
  cd /home/admin/asterisk
  tar -xzf deploy.tar.gz
  rm -f deploy.tar.gz

  # Setup greeting audio on Asterisk
  sudo cp /tmp/greeting.mp3 /var/lib/asterisk/sounds/custom/greeting.mp3
  sudo chown asterisk:asterisk /var/lib/asterisk/sounds/custom/greeting.mp3
  sudo rm -f /tmp/greeting.mp3
  
  # Ensure dialplan reload
  sudo fwconsole reload
EOF

# Clean up local tarball
rm -f deploy.tar.gz

echo "[+] Deployment package successfully extracted on private host."
