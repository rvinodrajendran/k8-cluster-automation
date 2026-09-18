#!/bin/bash
#
# Kubernetes cluster deployment.
#
# Two modes:
#   Interactive (default)  : prompts for the PEM key and node IPs (original lab flow).
#   Non-interactive        : set these env vars and no prompts are shown
#                            (used by Terraform):
#       MASTER_IP, CLIENT1_IP, CLIENT2_IP  - private IPs of the nodes
#       CLUSTER_KEY                        - path to a private key that can
#                                            already SSH to the workers as ubuntu

set -euo pipefail

cd "$(dirname "$0")"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)

if [[ -n "${CLUSTER_KEY:-}" && -n "${MASTER_IP:-}" && -n "${CLIENT1_IP:-}" && -n "${CLIENT2_IP:-}" ]]; then
    NON_INTERACTIVE=true
else
    NON_INTERACTIVE=false
fi

banner() {
    echo
    echo "=========================================="
    echo " $1"
    echo "=========================================="
    echo
}

banner "Kubernetes Cluster Automation"
echo "Mode: $([[ "$NON_INTERACTIVE" == true ]] && echo non-interactive || echo interactive)"

# --------------------------------------------------
# Install Ansible
# --------------------------------------------------

echo "Checking Ansible installation..."

if ! command -v ansible >/dev/null 2>&1; then
    echo "Ansible is not installed. Installing..."
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ansible
else
    echo "Ansible is already installed."
fi

ansible --version | head -n 1

if [[ "$NON_INTERACTIVE" == true ]]; then

    # --------------------------------------------------
    # Non-interactive: key and IPs come from the environment
    # --------------------------------------------------

    MASTER_KEY="$CLUSTER_KEY"
    chmod 600 "$MASTER_KEY"

    echo
    echo "Master1 : $MASTER_IP"
    echo "Client1 : $CLIENT1_IP"
    echo "Client2 : $CLIENT2_IP"

else

    # --------------------------------------------------
    # Interactive: get PEM key
    # --------------------------------------------------

    banner "SSH Key Setup"

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
    # Interactive: get IP addresses
    # --------------------------------------------------

    banner "Kubernetes Node IPs"

    read -rp "Enter master1 private IP: " MASTER_IP
    read -rp "Enter client1 private IP: " CLIENT1_IP
    read -rp "Enter client2 private IP: " CLIENT2_IP

    echo
    echo "Master1 : $MASTER_IP"
    echo "Client1 : $CLIENT1_IP"
    echo "Client2 : $CLIENT2_IP"

    # --------------------------------------------------
    # Generate SSH key on master
    # --------------------------------------------------

    banner "Generating Master SSH Key"

    MASTER_KEY="$HOME/.ssh/k8s_cluster_ed25519"

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    if [ ! -f "$MASTER_KEY" ]; then
        ssh-keygen -t ed25519 -f "$MASTER_KEY" -N "" -C "k8s-cluster-master"
        echo "Master SSH key created."
    else
        echo "Master SSH key already exists."
    fi

    # --------------------------------------------------
    # Configure worker SSH access
    # --------------------------------------------------

    banner "Configuring Worker SSH Access"

    for ip in "$CLIENT1_IP" "$CLIENT2_IP"; do
        echo "Connecting to $ip..."
        ssh -i "$PEM_FILE" "${SSH_OPTS[@]}" "ubuntu@$ip" \
            'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys' \
            < "${MASTER_KEY}.pub"
        echo "✓ $ip SSH access configured."
    done

    rm -f "$PEM_FILE"
    echo
    echo "Temporary PEM file removed."
fi

# --------------------------------------------------
# Wait for / test SSH from master to workers
# (workers may still be booting when Terraform triggers this)
# --------------------------------------------------

banner "Testing SSH Connectivity"

for ip in "$CLIENT1_IP" "$CLIENT2_IP"; do
    echo "Waiting for $ip..."
    for attempt in $(seq 1 60); do
        if ssh -i "$MASTER_KEY" "${SSH_OPTS[@]}" "ubuntu@$ip" "cloud-init status --wait >/dev/null 2>&1 || true; hostname"; then
            echo "✓ $ip SSH working."
            break
        fi
        if [[ "$attempt" -eq 60 ]]; then
            echo "✗ Could not reach $ip over SSH after 5 minutes."
            exit 1
        fi
        sleep 5
    done
done

# --------------------------------------------------
# Create Ansible inventory
# --------------------------------------------------

banner "Creating Ansible Inventory"

cat > inventory.ini <<INV
[master]
master1 ansible_host=$MASTER_IP ansible_connection=local

[workers]
client1 ansible_host=$CLIENT1_IP ansible_user=ubuntu ansible_ssh_private_key_file=$MASTER_KEY
client2 ansible_host=$CLIENT2_IP ansible_user=ubuntu ansible_ssh_private_key_file=$MASTER_KEY

[k8s_cluster:children]
master
workers
INV

cat inventory.ini

# --------------------------------------------------
# Test Ansible connectivity
# --------------------------------------------------

banner "Testing Ansible Connectivity"

ansible all -m ping

# --------------------------------------------------
# Deploy Kubernetes
# --------------------------------------------------

banner "Starting Kubernetes Deployment"

ansible-playbook site.yml

# --------------------------------------------------
# Final cluster status
# --------------------------------------------------

banner "Kubernetes Cluster Status"

# Workers take a few seconds to go Ready after Flannel starts
export KUBECONFIG="$HOME/.kube/config"
kubectl wait --for=condition=Ready nodes --all --timeout=180s || true
kubectl get nodes -o wide

banner "Kubernetes Cluster Ready!"
