output "region" {
  description = "AWS deployment region"
  value       = var.aws_region
}

output "bastion_public_ip" {
  description = "Public IP of the Bastion jump host"
  value       = aws_instance.bastion.public_ip
}

output "proxy_public_ip" {
  description = "Public IP of the Nginx/SIP Proxy host"
  value       = aws_eip.proxy_eip.public_ip
}

output "asterisk_private_ip" {
  description = "Private IP of the Asterisk server"
  value       = aws_instance.asterisk_server.private_ip
}

output "ssh_bastion_tunnel_cmd" {
  description = "SSH command to log in to the private instance through the Bastion jump host"
  value       = "ssh -i ./asterisk-key.pem -J admin@${aws_instance.bastion.public_ip} admin@${aws_instance.asterisk_server.private_ip}"
}

output "freepbx_url" {
  description = "FreePBX Web Admin URL (accessible publicly through the proxy)"
  value       = "http://${aws_eip.proxy_eip.public_ip}"
}
