# Omrin 

A self-hosted infrastructure setup using **Docker, Traefik, and Ansible**.

## Overview

Omrin is ment to run on a **VPS** or a **self provisioned VM**:

* Uses **Ansible** for provisioning and deployment
* Uses **Docker Compose** for service orchestration
* Uses **Traefik** as a reverse proxy with automatic routing
* Supports **local development (Vagrant)** for testing

## Project Structure


```
.
├── ansible/
│   ├── group_vars/
│   │   ├── all.yaml              # Non-secret configuration
│   │   ├── secrets.yaml          # Encrypted secrets (Ansible Vault)
│   │   └── secrets.yaml.example  # Template for secrets
│   │
│   ├── inventory/                # Inventory definitions (Vagrant / VPS)
│   │   ├── vagrant/              
│   │   └── contabo/
│   │
│   ├── playbooks/                # Entry points for provisioning
│   │   ├── bootstrap.yaml        # Initial server setup
│   │   └── main.yaml             # Main deployment
│   │
│   ├── roles/                   
│   │   ├── docker/               # Docker installation & setup
│   │   ├── firewall/             # UFW configuration
│   │   ├── ssh/                  # SSH hardening
│   │   └── services/             # Service deployment logic
│   │
│   └── services/                 # Service definitions
│       └── service.env.j2        # Template for env generation
│
├── scripts/                      # Utility scripts
├── Vagrantfile                   # Local development environment
└── README.md
```

## Services

### 🧩 Services

| S.No | Name | Description |
|:-----|:-----|:------------|
| 01 | [Traefik](https://github.com/traefik/traefik) | Reverse proxy with automatic routing and TLS |
| 02 | [Syncthing](https://github.com/syncthing/syncthing) | Peer-to-peer file synchronization |
| 03 | [Filebrowser](https://github.com/filebrowser/filebrowser) | Web UI for file management |
| 04 | [Prometheus](https://github.com/prometheus/prometheus) | Metrics collection system |
| 05 | [Grafana](https://github.com/grafana/grafana) | Visualization dashboard for metrics |
| 06 | [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | Lightweight Bitwarden-compatible password manager |
| 07 | [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) | Document management system (law & personal) |
| 08 | [Photoview](https://github.com/photoview/photoview) | Self-hosted photo gallery |
| 09 | [Radicale](https://github.com/Kozea/Radicale) | CalDAV/CardDAV server for contacts and calendars |
| 10 | [Umami](https://github.com/umami-software/umami) | Privacy-focused web analytics |
| 11 | [Pastebin](https://github.com/PrivateBin/PrivateBin) | Secure pastebin/snippet sharing |
| 12 | [Crafty Controller](https://github.com/crafty-controller/crafty-4) | Game server management panel |
| 13 | [Homarr](https://github.com/ajnart/homarr) | Dashboard for self-hosted services |

## Configuration & Secrets

* Non-sensitive values → `group_vars/all.yaml`
* Secrets → `group_vars/secrets.yaml` (encrypted via Ansible Vault)

Environment files are **generated dynamically** per service using:

```
service.env.j2
```

Use the following from inside `ansible/` to edit secrets file

```bash
ansible-vault edit group_vars/secrets.yaml --vault-password-file=../.vault_pass
```

## Backup Strategy

* Databases (Vaultwarden, Paperless, etc.)
* User uploads / synced data

Stored in:

```
/data/omrin/
```

Backed up to:

* **Hetzner Storage Box**
* **OneDrive**
