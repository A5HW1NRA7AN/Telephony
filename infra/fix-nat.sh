#!/bin/bash
echo "=== Updating sip-trunk with NAT settings ==="
cat << 'EOF' > /etc/asterisk/pjsip_custom.conf
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
contact=sip:lead-telephony.pstn.twilio.com:5060

[sip-trunk]
type=identify
endpoint=sip-trunk
match=54.172.60.0/30,54.244.51.0/30,54.171.127.192/30,35.156.191.128/30,54.65.63.192/30,54.169.127.128/30,54.252.254.64/30,177.71.206.192/30
EOF

echo "=== Updating PJSIP Transport for NAT ==="
# We also need to make sure the global transport knows our public IP
cat << 'EOF' >> /etc/asterisk/pjsip_custom.conf

[0.0.0.0-udp](+)
type=transport
local_net=172.31.0.0/16
external_media_address=35.79.91.209
external_signaling_address=35.79.91.209
EOF

echo "=== Reloading Asterisk ==="
fwconsole reload
asterisk -rx "pjsip reload"
