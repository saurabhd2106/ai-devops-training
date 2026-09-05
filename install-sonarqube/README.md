# install-sonarqube — Ansible SonarQube Community Build on Amazon Linux 2023

Installs **SonarQube Community Build** on an existing EC2 instance provisioned by [`deploy-vm`](../deploy-vm/README.md) (Amazon Linux 2023, port **9000**, user `ec2-user`).

This project does **not** create AWS resources. Run it after `terraform apply` in `deploy-vm` (or against any matching AL2023 host).

## What it installs

| Component | Detail |
|-----------|--------|
| Java | Amazon Corretto 21 JDK (`java-21-amazon-corretto-devel`) |
| fontconfig / unzip | Report fonts and zip extraction |
| SonarQube | Community Build from official zip (default `26.8.0.126808`) |
| Database | Embedded H2 (evaluation / lab only) |
| Service | `systemd` unit `sonarqube`, listening on port **9000** |

Elasticsearch host settings (`vm.max_map_count`, `fs.file-max`, file/process limits) are applied automatically.

## Prerequisites

- [ansible-core](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) `>= 2.15`
- SSH access to the SonarQube EC2 (same private key used with `deploy-vm`)
- A running SonarQube-role VM with security group allowing TCP **22** and **9000** from your IP (default `deploy-vm` layout)

```bash
# Optional: confirm ansible is available
ansible --version
```

## Quick start

```bash
cd install-sonarqube

cp inventory.ini.example inventory.ini
# Set the SonarQube public IP and private key path in inventory.ini
```

Fill the host from Terraform:

```bash
terraform -chdir=../deploy-vm output -json public_ips
# Use the "sonarqube" value as the inventory host
```

Example `inventory.ini`:

```ini
[sonarqube]
203.0.113.10 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

Run the playbook:

```bash
ansible-playbook site.yml
```

Optional full package upgrade before install (slower):

```bash
ansible-playbook site.yml -e sonarqube_update_packages=true
```

## After install

1. Open `http://<sonarqube-public-ip>:9000` (from the CIDR allowed in `deploy-vm`).
2. Sign in with **admin** / **admin** and change the password when prompted.
3. Complete the first-run setup in the UI.

First start can take several minutes while Elasticsearch extracts; the playbook waits up to 300 seconds for port 9000.

## Variables

Defaults live in [`roles/sonarqube/defaults/main.yml`](roles/sonarqube/defaults/main.yml). Override in [`group_vars/all.yml`](group_vars/all.yml) or with `-e`.

| Name | Default | Description |
|------|---------|-------------|
| `sonarqube_version` | `26.8.0.126808` | Community Build version (zip / jar name) |
| `sonarqube_http_port` | `9000` | Web UI port (must match SG) |
| `sonarqube_java_package` | `java-21-amazon-corretto-devel` | Full JDK package |
| `sonarqube_update_packages` | `false` | Run `dnf` upgrade of all packages first |
| `sonarqube_download_url` | binaries.sonarsource.com zip URL | Distribution download URL |
| `sonarqube_wait_timeout` | `300` | Seconds to wait for HTTP port after start |

## Layout

```
install-sonarqube/
  ansible.cfg
  inventory.ini.example
  site.yml
  group_vars/all.yml
  roles/sonarqube/
    defaults/main.yml
    handlers/main.yml
    tasks/main.yml
    templates/sonarqube.service.j2
```

## Out of scope

- EC2 / VPC / security groups (see `deploy-vm`)
- PostgreSQL or other external JDBC databases
- Docker, reverse proxy, TLS
- Ubuntu/Debian targets (Amazon Linux 2023 only)
