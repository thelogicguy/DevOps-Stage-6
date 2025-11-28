#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

hostnamectl set-hostname ${hostname}
timedatectl set-timezone UTC

apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    python3 \
    python3-pip

cat >> /etc/security/limits.conf <<EOF
*                soft    nofile          65535
*                hard    nofile          65535
EOF

cat >> /etc/sysctl.conf <<EOF
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.swappiness = 10
EOF

sysctl -p

mkdir -p /var/log/app
chmod 755 /var/log/app

echo "Initial setup complete"