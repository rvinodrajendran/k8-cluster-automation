# Kubernetes Cluster Automation with Ansible

Automate the deployment of a **3-node Kubernetes cluster** on Ubuntu EC2 instances using **Ansible and kubeadm**.

This project is designed for learning and lab environments where three Ubuntu EC2 instances are created manually and the Kubernetes installation/configuration is then automated.

The project configures:

* 1 Kubernetes control-plane node (`master1`)
* 2 Kubernetes worker nodes (`client1`, `client2`)
* containerd as the container runtime
* Kubernetes `kubeadm`, `kubelet`, and `kubectl`
* Flannel as the Container Network Interface (CNI)
* SSH access between the control-plane and worker nodes
* Kubernetes cluster initialization
* Automatic worker-node joining
* Final Kubernetes cluster verification

---

## Architecture

```text
                    Kubernetes Cluster
                         |
                  +--------------+
                  |   master1    |
                  | Control Plane|
                  |              |
                  | kubeadm      |
                  | kubectl      |
                  | kubelet      |
                  | containerd   |
                  +------+-------+
                         |
              Kubernetes API Server
                         |
             +-----------+-----------+
             |                       |
      +------+-------+        +------+-------+
      |   client1    |        |   client2    |
      |   Worker     |        |   Worker     |
      |              |        |              |
      | kubelet      |        | kubelet      |
      | containerd   |        | containerd   |
      +--------------+        +--------------+
```

---

# What This Project Does

The user manually creates three Ubuntu EC2 instances.

After connecting to `master1`, only the repository needs to be cloned and the deployment script needs to be executed.

The script then performs the following workflow:

```text
User creates 3 EC2 instances
          |
          v
SSH into master1
          |
          v
Install Git
          |
          v
Clone this repository
          |
          v
Run ./deploy.sh
          |
          v
Paste KodeKloud PEM key
          |
          v
Enter 3 private IP addresses
          |
          v
Configure SSH access
          |
          v
Install Ansible
          |
          v
Configure all Kubernetes nodes
          |
          v
Install containerd
          |
          v
Install Kubernetes
          |
          v
Initialize master1
          |
          v
Install Flannel
          |
          v
Join client1 and client2
          |
          v
kubectl get nodes
```

The goal is that the user does not need to manually configure each Kubernetes node.

---

# Requirements

## AWS

You need three Ubuntu EC2 instances.

Recommended lab setup:

| Node    | Role                     |
| ------- | ------------------------ |
| master1 | Kubernetes control plane |
| client1 | Kubernetes worker        |
| client2 | Kubernetes worker        |

The instances should be able to communicate with each other using their **private IP addresses**.

---

# Security Group Requirements

The three EC2 instances must be able to communicate with each other.

For a temporary learning environment, one simple approach is:

```text
Source: The same Security Group
Protocol: All traffic
```

This allows the instances belonging to the same Security Group to communicate with each other.

For production environments, use more restrictive rules.

## Important Kubernetes Port

The workers must be able to reach the Kubernetes API server on:

```text
TCP 6443
```

For example:

```text
client1 ---> master1:6443
client2 ---> master1:6443
```

If this connection is blocked, `kubeadm join` will fail.

---

# Local SSH Access

The EC2 instances are initially accessed from the user's laptop using the SSH `.pem` key provided by the lab/cloud environment.

Example:

```bash
ssh -i your-key.pem ubuntu@<public-ip>
```

You only need to manually connect to `master1` to begin the automation.

---

# Initial Setup on master1

SSH into `master1`.

Install Git:

```bash
sudo apt update
sudo apt install -y git
```

Clone the repository:

```bash
git clone git@github.com:rvinodrajendran/k8-cluster-automation.git
```

Enter the project:

```bash
cd k8-cluster-automation
```

Make the deployment script executable:

```bash
chmod +x deploy.sh
```

---

# Run the Automation

Start the deployment:

```bash
./deploy.sh
```

The script will first check whether Ansible is installed.

If Ansible is not installed, it installs it automatically.

---

# Step 1 — Provide the PEM Key

The script asks you to paste the private SSH key.

You will see:

```text
Paste your complete PEM key below.
After the final line, type ENDPEM and press Enter.
```

Paste the complete key:

```text
-----BEGIN OPENSSH PRIVATE KEY-----
...
...
-----END OPENSSH PRIVATE KEY-----
```

Then type:

```text
ENDPEM
```

on a new line.

The key is temporarily stored on `master1` so that the script can establish the initial SSH connection to the worker nodes.

The temporary key is deleted after the worker SSH configuration is completed.

---

# Step 2 — Enter the Private IP Addresses

The script asks for:

```text
Enter master1 private IP:
Enter client1 private IP:
Enter client2 private IP:
```

Enter the private IP address of each EC2 instance.

Example:

```text
Master1 : 172.31.32.237
Client1 : 172.31.38.181
Client2 : 172.31.45.95
```

These addresses are used to create the Ansible inventory.

---

# Step 3 — SSH Key Bootstrap

The script creates an ED25519 SSH key on `master1`:

```text
~/.ssh/k8s_cluster_ed25519
```

The public key:

```text
~/.ssh/k8s_cluster_ed25519.pub
```

is automatically added to:

```text
client1 ~/.ssh/authorized_keys
client2 ~/.ssh/authorized_keys
```

The original lab `.pem` key is only used for this initial bootstrap.

After that, Ansible uses the new SSH key created on `master1`.

---

# Step 4 — Ansible Inventory

The script automatically creates:

```text
inventory.ini
```

Example:

```ini
[master]
master1 ansible_host=172.31.32.237 ansible_connection=local

[workers]
client1 ansible_host=172.31.38.181 ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/.ssh/k8s_cluster_ed25519
client2 ansible_host=172.31.45.95 ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/.ssh/k8s_cluster_ed25519

[k8s_cluster:children]
master
workers
```

`inventory.ini` is generated automatically and is ignored by Git.

---

# Step 5 — Ansible Connectivity Test

The script runs:

```bash
ansible all -m ping
```

Expected result:

```text
master1 | SUCCESS
client1 | SUCCESS
client2 | SUCCESS
```

This confirms that Ansible can communicate with all three machines.

---

# Step 6 — Common Node Configuration

The `common` role configures all three nodes.

It:

* Sets the hostname
* Disables swap
* Removes swap from `/etc/fstab`
* Loads the `overlay` kernel module
* Loads the `br_netfilter` kernel module
* Enables Kubernetes networking settings
* Enables IPv4 forwarding

The resulting hostnames are:

```text
master1
client1
client2
```

---

# Step 7 — Install containerd

The `containerd` role installs and configures containerd.

It:

* Installs containerd
* Creates `/etc/containerd`
* Generates the default configuration
* Enables systemd cgroups
* Restarts containerd
* Enables containerd at boot

Kubernetes uses containerd as the container runtime.

---

# Step 8 — Install Kubernetes

The Kubernetes role installs:

```text
kubelet
kubeadm
kubectl
```

The project currently uses the Kubernetes `v1.34` package repository.

The Kubernetes packages are also held to prevent unexpected automatic upgrades:

```text
kubelet
kubeadm
kubectl
```

---

# Step 9 — Initialize the Control Plane

The control plane is initialized using:

```bash
kubeadm init
```

The API server advertises the private IP of `master1`.

The cluster uses:

```text
Pod Network CIDR:
10.244.0.0/16
```

This CIDR matches the Flannel network used by the project.

---

# Step 10 — Configure kubectl

The Kubernetes administrator configuration is copied to:

```text
/home/ubuntu/.kube/config
```

This allows the `ubuntu` user on `master1` to use:

```bash
kubectl
```

without manually setting `KUBECONFIG` each time.

---

# Step 11 — Install Flannel

Flannel is installed as the Kubernetes CNI.

The deployment uses:

```text
https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

Flannel provides pod-to-pod networking across the Kubernetes nodes.

---

# Step 12 — Join Worker Nodes

The worker role obtains a Kubernetes join command from `master1`:

```bash
kubeadm token create --print-join-command
```

The generated command is then executed on:

```text
client1
client2
```

The workers join the Kubernetes cluster automatically.

---

# Step 13 — Final Cluster Check

At the end of the deployment, the script runs:

```bash
kubectl get nodes -o wide
```

Expected result:

```text
NAME      STATUS   ROLES           VERSION
client1   Ready    <none>          v1.34.x
client2   Ready    <none>          v1.34.x
master1   Ready    control-plane   v1.34.x
```

All three nodes should show:

```text
Ready
```

---

# Project Structure

```text
k8-cluster-automation/
│
├── ansible.cfg
├── deploy.sh
├── site.yml
├── .gitignore
│
├── group_vars/
│   └── all.yml
│
└── roles/
    │
    ├── common/
    │   └── tasks/
    │       └── main.yml
    │
    ├── containerd/
    │   └── tasks/
    │       └── main.yml
    │
    ├── control-plane/
    │   └── tasks/
    │       └── main.yml
    │
    ├── kubernetes/
    │   └── tasks/
    │       └── main.yml
    │
    └── worker/
        └── tasks/
            └── main.yml
```

---

# Ansible Roles

## common

Configures basic operating-system requirements for Kubernetes.

```text
roles/common/tasks/main.yml
```

## containerd

Installs and configures containerd.

```text
roles/containerd/tasks/main.yml
```

## kubernetes

Installs:

```text
kubeadm
kubelet
kubectl
```

```text
roles/kubernetes/tasks/main.yml
```

## control-plane

Initializes the Kubernetes control plane and configures `kubectl`.

```text
roles/control-plane/tasks/main.yml
```

## worker

Generates the Kubernetes join command and joins the workers to the cluster.

```text
roles/worker/tasks/main.yml
```

---

# Main Ansible Playbook

The main playbook is:

```text
site.yml
```

It performs three major phases:

```text
1. Configure all nodes
        ↓
2. Initialize master1
        ↓
3. Join client1 and client2
```

---

# Important Security Note

This project is intended primarily for **learning and temporary lab environments**.

The deployment script accepts the lab `.pem` private key as input.

The key is:

1. Entered by the user.
2. Temporarily written to `/tmp`.
3. Used to bootstrap SSH access.
4. Deleted after the worker SSH keys are configured.

The `.pem` key should **never be committed to Git**.

Never place the following into this repository:

```text
*.pem
*.key
private SSH keys
passwords
AWS credentials
API tokens
```

For production automation, use a more secure secret-management or SSH provisioning approach.

---

# Important AWS Note

The private IP addresses of temporary EC2 instances can change when new instances are created.

Therefore, this project intentionally asks the user for the three private IP addresses every time:

```text
master1 IP
client1 IP
client2 IP
```

The inventory is generated dynamically for each deployment.

---

# Starting a New Cluster

For a new lab session:

### 1. Create three EC2 instances

```text
master1
client1
client2
```

### 2. Configure the Security Group

Make sure the instances can communicate with each other.

### 3. SSH into master1

```bash
ssh -i your-key.pem ubuntu@<master-public-ip>
```

### 4. Install Git

```bash
sudo apt update
sudo apt install -y git
```

### 5. Clone the repository

```bash
git clone git@github.com:rvinodrajendran/k8-cluster-automation.git
```

### 6. Run the deployment

```bash
cd k8-cluster-automation
chmod +x deploy.sh
./deploy.sh
```

### 7. Enter

```text
PEM key
master1 private IP
client1 private IP
client2 private IP
```

Then allow the automation to complete.

---

# Troubleshooting

## Ansible says Permission denied (publickey)

Example:

```text
Permission denied (publickey)
```

Check that:

* The PEM key belongs to the EC2 instances.
* The worker username is `ubuntu`.
* The worker Security Group allows SSH.
* The worker private IP addresses are correct.

The script should normally handle the initial SSH key bootstrap automatically.

---

## kubeadm join times out

Example:

```text
Client.Timeout exceeded
```

Check that `client1` and `client2` can reach:

```text
master1:6443
```

The Kubernetes API server uses TCP port:

```text
6443
```

Check the AWS Security Group before troubleshooting Kubernetes itself.

---

## Nodes are NotReady

Check:

```bash
kubectl get nodes
```

Then:

```bash
kubectl get pods -A
```

Check the Flannel pods:

```bash
kubectl get pods -n kube-flannel -o wide
```

All Flannel pods should eventually become:

```text
Running
```

---

## Check Kubernetes services

On `master1`:

```bash
sudo systemctl status kubelet
```

```bash
sudo systemctl status containerd
```

---

# Useful Kubernetes Commands

After the cluster is ready:

### Nodes

```bash
kubectl get nodes
```

### Nodes with IP information

```bash
kubectl get nodes -o wide
```

### All pods

```bash
kubectl get pods -A
```

### Kubernetes namespaces

```bash
kubectl get namespaces
```

### Cluster information

```bash
kubectl cluster-info
```

### Detailed node information

```bash
kubectl describe node master1
```

---

# How the Automation Works

The automation can be summarized as:

```text
                     deploy.sh
                         |
          +--------------+--------------+
          |              |              |
        PEM             IPs          Ansible
          |              |              |
          +--------------+--------------+
                         |
                  SSH Bootstrap
                         |
              +----------+----------+
              |                     |
           client1               client2
              |                     |
              +----------+----------+
                         |
                   Ansible Ping
                         |
                  Common Configuration
                         |
              +----------+----------+
              |                     |
          containerd             Kubernetes
              |                     |
              +----------+----------+
                         |
                    kubeadm init
                         |
                    Flannel CNI
                         |
                   Worker Join
                         |
                +--------+--------+
                |        |        |
             master1  client1  client2
                |        |        |
                +--------+--------+
                         |
                  kubectl get nodes
                         |
                  Cluster Ready
```

---

# Goal of the Project

This project demonstrates a practical DevOps workflow combining:

* Linux
* AWS EC2
* SSH
* Git
* GitHub
* Bash scripting
* Ansible
* containerd
* Kubernetes
* kubeadm
* kubectl
* Flannel
* Infrastructure automation

The main learning objective is to understand how a Kubernetes cluster can be built repeatedly from fresh machines using automation instead of manually repeating every installation and configuration step.
