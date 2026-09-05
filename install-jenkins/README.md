# install-jenkins — Ansible Jenkins LTS on Amazon Linux 2023

Installs **Jenkins LTS** on an existing EC2 instance provisioned by [`deploy-vm`](../deploy-vm/README.md) (Amazon Linux 2023, port **8080**, user `ec2-user`).

This project does **not** create AWS resources. Run it after `terraform apply` in `deploy-vm` (or against any matching AL2023 host).

## What it installs

| Component | Detail |
|-----------|--------|
| Java | Amazon Corretto 21 (`java-21-amazon-corretto`) |
| fontconfig | Required Jenkins dependency |
| Jenkins | LTS from `pkg.jenkins.io/rpm-stable` |
| Service | `systemd` unit `jenkins`, listening on port **8080** |

After install, the playbook prints the initial admin password from `/var/lib/jenkins/secrets/initialAdminPassword`.

## Prerequisites

- [ansible-core](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) `>= 2.15`
- SSH access to the Jenkins EC2 (same private key used with `deploy-vm`)
- A running Jenkins-role VM with security group allowing TCP **22** and **8080** from your IP (default `deploy-vm` layout)

```bash
# Optional: confirm ansible is available
ansible --version
```

## Quick start

```bash
cd install-jenkins

cp inventory.ini.example inventory.ini
# Set the Jenkins public IP and private key path in inventory.ini
```

Fill the host from Terraform:

```bash
terraform -chdir=../deploy-vm output -json public_ips
# Use the "jenkins" value as the inventory host
```

Example `inventory.ini`:

```ini
[jenkins]
203.0.113.10 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

Run the playbook:

```bash
ansible-playbook site.yml
```

Optional full package upgrade before install (slower):

```bash
ansible-playbook site.yml -e jenkins_update_packages=true
```

## After install

1. Open `http://<jenkins-public-ip>:8080` (from the CIDR allowed in `deploy-vm`).
2. Paste the initial admin password printed by the playbook (or run `sudo cat /var/lib/jenkins/secrets/initialAdminPassword` on the host).
3. Complete the Jenkins setup wizard (suggested plugins, first admin user).

## Variables

Defaults live in [`roles/jenkins/defaults/main.yml`](roles/jenkins/defaults/main.yml). Override in [`group_vars/all.yml`](group_vars/all.yml) or with `-e`.

| Name | Default | Description |
|------|---------|-------------|
| `jenkins_http_port` | `8080` | Port to wait for after start (must match SG) |
| `jenkins_java_package` | `java-21-amazon-corretto` | Java runtime package |
| `jenkins_update_packages` | `false` | Run `dnf` upgrade of all packages first |
| `jenkins_repo_baseurl` | `https://pkg.jenkins.io/rpm-stable` | Jenkins LTS yum base URL |
| `jenkins_gpg_key_url` | `https://pkg.jenkins.io/rpm-stable/jenkins.io-2026.key` | Repo GPG key |

## Layout

```
install-jenkins/
  ansible.cfg
  inventory.ini.example
  site.yml
  group_vars/all.yml
  roles/jenkins/
    defaults/main.yml
    handlers/main.yml
    tasks/main.yml
```

## Out of scope

- EC2 / VPC / security groups (see `deploy-vm`)
- Docker, reverse proxy, TLS, Jenkins Configuration as Code
- Suggested plugins or job definitions
- Ubuntu/Debian targets (Amazon Linux 2023 only)
