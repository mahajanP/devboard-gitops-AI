#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

# Update apt package index and install prerequisites
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the Docker CE repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index with the new repository
sudo apt-get update

# Install Docker CE + Compose plugin
# Note: To version lock a highly specific old version on Ubuntu,
# you can specify it like: sudo apt-get install -y docker-ce=5:25.0.3-1~ubuntu.22.04~jammy
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Pin/Lock the version to prevent accidental upgrades
sudo apt-mark hold docker-ce docker-ce-cli

sleep 2

# Configure daemon logging and storage drivers
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# Restart Docker service to apply configuration changes
sudo systemctl stop docker
sleep 2
sudo systemctl start docker

# Add current user to docker group (avoids needing sudo for docker commands)
sudo usermod -aG docker "$USER"

echo ""
echo "✅ Docker installed successfully!"
echo "   Docker version: $(docker --version)"
echo "   Compose version: $(docker compose version)"
echo ""
echo "⚠️  Run 'newgrp docker' or log out and back in for group changes to take effect."

