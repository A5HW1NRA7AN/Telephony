#!/bin/bash
echo "=== Current bindaddr and enabled settings ==="
grep -n "bindaddr\|^enabled" /etc/asterisk/manager.conf

echo "=== Fixing: force bindaddr=0.0.0.0 and enabled=yes ==="
# FreePBX's format may use different spacing — use a broader pattern
sed -i 's/^enabled\s*=.*/enabled = yes/' /etc/asterisk/manager.conf
sed -i 's/^bindaddr\s*=.*/bindaddr = 0.0.0.0/' /etc/asterisk/manager.conf

echo "=== After fix ==="
grep -n "bindaddr\|^enabled" /etc/asterisk/manager.conf

echo "=== Full reload ==="
fwconsole reload

sleep 3

echo "=== Port 5038 status ==="
ss -tlnp | grep 5038
