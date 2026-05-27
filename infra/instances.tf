# ── AMI (Debian 12) ──────────────────────────────────────────────────────────

data "aws_ami" "debian_12" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Instances ─────────────────────────────────────────────────────────────────

# 1. Bastion Host (Public Subnet)
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.debian_12.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.asterisk_key_pair.key_name

  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "${var.cluster_name}-bastion"
  }
}

# 2. Private Asterisk Server (Private Subnet)
resource "aws_instance" "asterisk_server" {
  ami           = data.aws_ami.debian_12.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.asterisk_key_pair.key_name

  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.asterisk_sg.id]

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-USERDATA
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

hostnamectl set-hostname freepbx.local
apt-get update -y
apt-get upgrade -y
apt-get install -y curl gnupg lsb-release git iptables

# ── Install Docker ───────────────────────────────────────────────────
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl start docker
systemctl enable docker

# ── Install FreePBX ──────────────────────────────────────────────────
cd /usr/src
wget https://github.com/FreePBX/sng_freepbx_debian_install/raw/master/sng_freepbx_debian_install.sh -O sng_freepbx_debian_install.sh
chmod +x sng_freepbx_debian_install.sh
./sng_freepbx_debian_install.sh

sleep 30

# ── Configure NAT Traversal (External IP = Proxy IP) ────────────────
PUBLIC_IP="${aws_eip.proxy_eip.public_ip}"
LOCAL_CIDR="10.0.1.0/24"

cat > /etc/asterisk/rtp_custom.conf <<NATCFG
[general]
externip=$PUBLIC_IP
localnet=$LOCAL_CIDR
NATCFG

# ── SIP Trunk Configuration ──────────────────────────────────────────
cat > /etc/asterisk/pjsip_custom.conf <<'EOC'
[sip-trunk]
type=endpoint
transport=0.0.0.0-udp
context=from-missed-call
disallow=all
allow=ulaw
aors=sip-trunk
rewrite_contact=yes
rtp_symmetric=yes
force_rport=yes

[sip-trunk]
type=aor
contact=sip:PLACEHOLDER_SIP_DOMAIN:5060

[sip-trunk]
type=identify
endpoint=sip-trunk
match=PLACEHOLDER_SIP_IPS

[0.0.0.0-udp](+)
type=transport
local_net=PLACEHOLDER_LOCAL_NET
external_media_address=PLACEHOLDER_PUBLIC_IP
external_signaling_address=PLACEHOLDER_PUBLIC_IP
EOC
sed -i "s|from-missed-call|${var.dialplan_context}|g; s|PLACEHOLDER_SIP_DOMAIN|${var.sip_provider_domain}|g; s|PLACEHOLDER_SIP_IPS|${var.sip_provider_ip_ranges}|g; s|PLACEHOLDER_LOCAL_NET|$LOCAL_CIDR|g; s|PLACEHOLDER_PUBLIC_IP|$PUBLIC_IP|g" /etc/asterisk/pjsip_custom.conf

# ── AMI User Configuration ───────────────────────────────────────────
cat > /etc/asterisk/manager_custom.conf <<'EOC'
[PLACEHOLDER_AMI_USER]
secret = PLACEHOLDER_AMI_PASS
deny=0.0.0.0/0.0.0.0
permit=0.0.0.0/0.0.0.0
read = system,call,log,verbose,command,agent,user,config,command,dtmf,reporting,cdr,dialplan,originate
write = system,call,log,verbose,command,agent,user,config,command,dtmf,reporting,cdr,dialplan,originate
EOC
sed -i "s|PLACEHOLDER_AMI_USER|${var.ami_username}|g; s|PLACEHOLDER_AMI_PASS|${var.ami_password}|g" /etc/asterisk/manager_custom.conf

# Force AMI to listen on 0.0.0.0
sed -i 's/^enabled\s*=.*/enabled = yes/' /etc/asterisk/manager.conf
sed -i 's/^bindaddr\s*=.*/bindaddr = 0.0.0.0/' /etc/asterisk/manager.conf

# ── Dialplan Configuration ───────────────────────────────────────────
cat > /etc/asterisk/extensions_custom.conf <<'EOC'
[from-missed-call]
exten => _+.,1,NoOp(INCOMING CALL TO: $${EXTEN} FROM: $${CALLERID(num)})
same => n,Set(__CALLED_NUM=$${EXTEN})
same => n,Ringing()
same => n,Wait(2)
same => n,Answer()
same => n,Wait(1)
same => n,Playback(custom/greeting)
same => n,Hangup()

exten => h,1,NoOp(Call ended — context=$${CONTEXT} uniqueid=$${UNIQUEID})
EOC
sed -i "s|from-missed-call|${var.dialplan_context}|g" /etc/asterisk/extensions_custom.conf

# ── Set Ownership and Reload ─────────────────────────────────────────
mkdir -p /var/lib/asterisk/sounds/custom
chown asterisk:asterisk /etc/asterisk/*_custom.conf
fwconsole reload
USERDATA

  tags = {
    Name = "${var.cluster_name}-server"
  }
}

# 3. Nginx / SIP Proxy Host (Public Subnet)
resource "aws_instance" "proxy" {
  ami           = data.aws_ami.debian_12.id
  instance_type = "t3.small"
  key_name      = aws_key_pair.asterisk_key_pair.key_name

  subnet_id                   = module.vpc.public_subnets[1]
  vpc_security_group_ids      = [aws_security_group.proxy_sg.id]
  associate_public_ip_address = true

  user_data = <<-USERDATA
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# Pre-configure debconf to avoid prompts during iptables-persistent install
echo iptables-persistent iptables-persistent/prules select true | debconf-set-selections
echo iptables-persistent iptables-persistent/prev6rules select true | debconf-set-selections

apt-get update -y
apt-get install -y nginx iptables-persistent curl

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Setup NAT / DNAT rules
PRIVATE_AST_IP="${aws_instance.asterisk_server.private_ip}"

# SIP Signalling (UDP/TCP 5060)
iptables -t nat -A PREROUTING -p udp --dport 5060 -j DNAT --to-destination $PRIVATE_AST_IP:5060
iptables -t nat -A PREROUTING -p tcp --dport 5060 -j DNAT --to-destination $PRIVATE_AST_IP:5060
# RTP Media (UDP 10000-20000)
iptables -t nat -A PREROUTING -p udp --dport 10000:20000 -j DNAT --to-destination $PRIVATE_AST_IP

# POSTROUTING Masquerade
iptables -t nat -A POSTROUTING -j MASQUERADE

# Save iptables rules
netfilter-persistent save

# Configure Nginx Reverse Proxy
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    # Lead Service API
    location /leads/ {
        proxy_pass http://\$PRIVATE_AST_IP:8080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # FreePBX Admin console
    location / {
        proxy_pass http://\$PRIVATE_AST_IP:80/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

systemctl restart nginx
USERDATA

  tags = {
    Name = "${var.cluster_name}-proxy"
  }
}

# ── Elastic IP for the Proxy (Twilio & Web Traffic entry point) ──────────────

resource "aws_eip" "proxy_eip" {
  domain   = "vpc"
  instance = aws_instance.proxy.id

  tags = {
    Name = "${var.cluster_name}-proxy-eip"
  }
}
