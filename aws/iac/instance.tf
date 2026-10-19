# Find the latest Amazon Linux 2023 x86_64 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Register the public SSH key with AWS
resource "aws_key_pair" "app" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand("~/.ssh/todo-summary-assistant.pub"))

  tags = {
    Name = "${var.project_name}-key"
  }
}

# Application server
resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  key_name                    = aws_key_pair.app.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  user_data = <<-USERDATA
  #!/bin/bash
  set -euxo pipefail

  # Install Docker and curl
  dnf install -y docker curl

  # Start Docker automatically
  systemctl enable --now docker

  # Install Docker Compose CLI plugin
  install -d -m 0755 /usr/local/lib/docker/cli-plugins

  curl -fsSL \
    https://github.com/docker/compose/releases/download/v5.6.0/docker-compose-linux-x86_64 \
    -o /usr/local/lib/docker/cli-plugins/docker-compose

  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

  # Allow ec2-user to run Docker commands
  usermod -aG docker ec2-user
  USERDATA

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-ec2"
  }
}

output "ec2_instance_id" {
  description = "ID of the application EC2 instance"
  value       = aws_instance.app.id
}

output "ec2_public_ip" {
  description = "Public IPv4 address of the application instance"
  value       = aws_instance.app.public_ip
}

output "application_url" {
  description = "URL for the frontend application"
  value       = "http://${aws_instance.app.public_ip}:3000"
}
