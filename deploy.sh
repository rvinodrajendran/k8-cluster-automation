#!/bin/bash

set -e

echo "=========================================="
echo " Kubernetes Cluster Automation"
echo "=========================================="
echo

read -p "Enter master1 private IP: " MASTER_IP
read -p "Enter client1 private IP: " CLIENT1_IP
read -p "Enter client2 private IP: " CLIENT2_IP

echo
echo "=========================================="
echo " Cluster Information"
echo "=========================================="
echo "Master1 : $MASTER_IP"
echo "Client1 : $CLIENT1_IP"
echo "Client2 : $CLIENT2_IP"
echo

cat > inventory.ini <<EOF
[master]
master1 ansible_host=$MASTER_IP ansible_connection=local

[workers]
client1 ansible_host=$CLIENT1_IP ansible_user=ubuntu
client2 ansible_host=$CLIENT2_IP ansible_user=ubuntu

[k8s_cluster:children]
master
workers
EOF

echo "=========================================="
echo " Ansible Inventory"
echo "=========================================="
cat inventory.ini

echo
echo "=========================================="
echo " Testing Ansible Connectivity"
echo "=========================================="

ansible all -m ping

echo
echo "=========================================="
echo " Connectivity Successful!"
echo "=========================================="
