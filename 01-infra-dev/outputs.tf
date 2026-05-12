###############################################################################
# Outputs
###############################################################################
output "elastic_ip" {
  description = "Public Elastic IP address of the EC2 instance"
  value       = aws_eip.this.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.this.id
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i <your-key>.pem ec2-user@${aws_eip.this.public_ip}"
}
