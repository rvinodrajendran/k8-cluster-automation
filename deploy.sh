#!/bin/bash

set -e

echo "=========================================="
echo " Kubernetes Cluster Automation"
echo "=========================================="
echo

# --------------------------------------------------
# Install Ansible
# --------------------------------------------------

echo "Checking Ansible installation..."

if ! command -v ansible >/dev/null 2>&1; then
    echo "Ansible is not installed."
    echo "Installing Ansible..."

    sudo apt update
    sudo apt install -y ansible
else
    echo "Ansible is already installed."
fi

echo
ansible --version | head -n 1

# --------------------------------------------------
# Get PEM key
# --------------------------------------------------

echo
echo "=========================================="
echo " SSH Key Setup"
echo "=========================================="
echo

PEM_FILE="/tmp/k8s-kodekloud.pem"

echo "Paste your complete PEM key below."
echo "After the final line, type ENDPEM and press Enter."
echo

rm -f "$PEM_FILE"

while IFS= read -r line
do
    if [[ "$line" == "ENDPEM" ]]; then
        break
    fi

    echo "$line" >> "$PEM_FILE"
done

chmod 400 "$PEM_FILE"

echo
echo "PEM key received."

# --------------------------------------------------
# Get IP addresses
# --------------------------------------------------

echo
echo "=========================================="
echo " Kubernetes Node IPs"
echo "=========================================="
echo

read -p "Enter master1 private IP: " MASTER_IP
read -p "Enter client1 private IP: " CLIENT1_IP
read -p "Enter client2 private IP: " CLIENT2_IP

echo
echo "Master1 : $MASTER_IP"
echo "Client1 : $CLIENT1_IP"
echo "Client2 : $CLIENT2_IP"

# --------------------------------------------------
# Generate SSH key on master
# --------------------------------------------------

echo
echo "=========================================="
echo " Generating Master SSH Key"
echo "=========================================="
echo

MASTER_KEY="$HOME/.ssh/k8s_cluster_ed25519"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ ! -f "$MASTER_KEY" ]; then
    ssh-keygen \
        -t ed25519 \
        -f "$MASTER_KEY" \
        -N "" \
        -C "k8s-cluster-master"

    echo "Master SSH key created."
else
    echo "Master SSH key already exists."
fi

# --------------------------------------------------
# Configure worker SSH access
# --------------------------------------------------

echo
echo "=========================================="
echo " Configuring Worker SSH Access"
echo "=========================================="
echo

echo "Connecting to client1..."

cat "${MASTER_KEY}.pub" | ssh \
    -i "$PEM_FILE" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "ubuntu@$CLIENT1_IP" \
    'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'

echo "✓ client1 SSH access configured."

echo
echo "Connecting to client2..."

cat "${MASTER_KEY}.pub" | ssh \
    -i "$PEM_FILE" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "ubuntu@$CLIENT2_IP" \
    'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'

echo "✓ client2 SSH access configured."

# --------------------------------------------------
# Remove temporary PEM
# --------------------------------------------------

rm -f "$PEM_FILE"

echo
echo "Temporary PEM file removed."

# --------------------------------------------------
# Test SSH from master to workers
# --------------------------------------------------

echo
echo "=========================================="
echo " Testing SSH Connectivity"
echo "=========================================="
echo

echo "Testing client1..."

ssh \
    -i "$MASTER_KEY" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "ubuntu@$CLIENT1_IP" \
    "hostname"

echo "✓ client1 SSH working."

echo
echo "Testing client2..."

ssh \
    -i "$MASTER_KEY" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "ubuntu@$CLIENT2_IP" \
    "hostname"

echo "✓ client2 SSH working."

# --------------------------------------------------
# Create Ansible inventory
# --------------------------------------------------

echo
echo "=========================================="
echo " Creating Ansible Inventory"
echo "=========================================="
echo

cat > inventory.ini <<EOF
[master]
master1 ansible_host=$MASTER_IP ansible_connection=local

[workers]
client1 ansible_host=$CLIENT1_IP ansible_user=ubuntu ansible_ssh_private_key_file=$MASTER_KEY
client2 ansible_host=$CLIENT2_IP ansible_user=ubuntu ansible_ssh_private_key_file=$MASTER_KEY

[k8s_cluster:children]
master
workers
EOF

echo
echo "Inventory created:"
echo

cat inventory.ini

# --------------------------------------------------
# Test Ansible connectivity
# --------------------------------------------------

echo
echo "=========================================="
echo " Testing Ansible Connectivity"
echo "=========================================="
echo

ansible all -m ping

echo
echo "=========================================="
echo " Ansible Connectivity Successful!"
echo "=========================================="

# --------------------------------------------------
# Deploy Kubernetes
# --------------------------------------------------

echo
echo "=========================================="
echo " Starting Kubernetes Deployment"
echo "=========================================="
echo

ansible-playbook site.yml

# --------------------------------------------------
# Final cluster status
# --------------------------------------------------

echo
echo "=========================================="
echo " Kubernetes Cluster Status"
echo "=========================================="
echo

kubectl get nodes -o wide

echo
echo "=========================================="
echo " Kubernetes Cluster Ready!"
echo "=========================================="
echo
