# Omrin

A self-hosted infrastructure setup using **Ansible**, **Docker Compose**, and **Traefik**. Omrin provisions a fresh VPS from a bare OS into a hardened, Docker-based host with automatic HTTPS routing for every service you add.

## Overview

Omrin is designed to run on a **VPS** (e.g. Contabo, Hetzner) or a **locally provisioned VM** (via Vagrant, for testing). It handles everything from the first root login to running services:

- **Ansible** provisions the server: creates a deploy user, hardens SSH, installs Docker, configures the firewall, and deploys services.
- **Docker Compose** orchestrates each service as an isolated stack.
- **Traefik** acts as a reverse proxy, automatically routing subdomains to containers and provisioning Let's Encrypt TLS certificates.
- **Vagrant** provides a throwaway local VM so you can test the full provisioning flow before touching a real server.

## How it works

Provisioning happens in two phases, run as two separate playbooks:

| Phase        | Playbook         | Connects as | What it does                                                                                                        |
| :----------- | :--------------- | :---------- | :------------------------------------------------------------------------------------------------------------------ |
| 1. Bootstrap | `bootstrap.yaml` | `root`      | Creates the deploy user, installs its SSH key, grants passwordless sudo. After this, you log in as the deploy user. |
| 2. Main      | `main.yaml`      | deploy user | Hardens SSH (disables root login + password auth), installs Docker, configures UFW, deploys all enabled services.   |

The split exists because phase 1 needs root (the only account that exists on a fresh VPS), while phase 2 runs as your unprivileged deploy user with sudo. Running bootstrap first means that by the time SSH hardening happens in phase 2, your key-based login as the deploy user already works — so you never lock yourself out.

## Project Structure

```
.
├── ansible/
│   ├── ansible.cfg               # Ansible configuration (roles path, ssh settings)
│   ├── requirements.yaml         # Ansible Galaxy collections to install
│   │
│   ├── group_vars/
│   │   ├── all.yaml              # Non-secret configuration (user, domain, paths, service list)
│   │   ├── secrets.yaml          # Encrypted secrets (Ansible Vault) — NOT committed in plaintext
│   │   └── secrets.yaml.example  # Template showing the secrets structure
│   │
│   ├── inventory/                # Which hosts to target
│   │   ├── vagrant/              # Local test VM (bootstrap + main inventories)
│   │   └── contabo/              # Production VPS (bootstrap + main inventories)
│   │
│   ├── playbooks/
│   │   ├── bootstrap.yaml        # Phase 1: initial server setup (run as root)
│   │   └── main.yaml             # Phase 2: docker, firewall, ssh hardening, services
│   │
│   ├── roles/
│   │   ├── docker/               # Docker Engine + Compose plugin installation
│   │   ├── firewall/             # UFW configuration (allows SSH, HTTP, HTTPS)
│   │   ├── ssh/                  # SSH hardening (disable root login + password auth)
│   │   └── services/             # Deploys each enabled service via Docker Compose
│   │
│   └── services/                 # Service definitions
│       ├── service.env.j2        # Template that generates each service's .env file
│       ├── traefik/              # Reverse proxy compose file
│       └── syncbrowser/          # Syncthing + Filebrowser compose file
│
├── scripts/
│   └── test_setup.sh             # Smoke test for the Vagrant VM (ssh, sudo, firewall checks)
├── Vagrantfile                   # Local development VM definition
└── README.md
```

## Configuration

### Non-secret values — `group_vars/all.yaml`

| Variable              | Meaning                                                                   |
| :-------------------- | :------------------------------------------------------------------------ |
| `new_user`            | The deploy user Ansible creates and uses for phase 2.                     |
| `ssh_port`            | Port sshd listens on. Change from `22` if you want a non-standard port.   |
| `domain`              | Base domain. Services are routed at `<service>.<domain>`.                 |
| `root_path`           | Where service compose files live on the server (`/home/<user>/Omrin`).    |
| `data_path`           | Where persistent service data is stored (`/data/omrin`).                  |
| `ssh_public_key_path` | Local path to the public key installed for the deploy user.               |
| `services`            | List of services with an `enabled` flag. Toggle a service off to stop it. |

### Secrets — `group_vars/secrets.yaml` (Ansible Vault)

Secrets are encrypted with Ansible Vault and decrypted at runtime using the vault password file. The structure (see `secrets.yaml.example`):

```yaml
email: you@example.com # used by Traefik for Let's Encrypt registration

service_secrets:
  vaultwarden:
    PORT: 10030
  radicale:
    PORT: 10020
    USERS_FILE: /home/aditya/.config/radicale/users
  paperless-personal:
    PORT: 10050
    DB_USER: aditya
    DB_PASSWORD: changeme
    STORAGE_BOX: /mnt/storagebox/paperless-personal
```

Each key under `service_secrets.<name>` becomes an environment variable in that service's `.env` file. Services that need no extra variables can be omitted entirely (the template skips any service with no entry).

To edit secrets:

```bash
cd ansible
ansible-vault edit group_vars/secrets.yaml --vault-password-file=../.vault_pass
```

### How env files are generated

The `services/service.env.j2` template runs once per enabled service and writes a `.env` next to its compose file. Every service automatically gets:

```
DATA_PATH=<data_path>
DOMAIN=<domain>
EMAIL=<email>
```

plus any key/value pairs defined under `service_secrets.<name>`.

## Prerequisites

On your **local machine** (the control node):

- Ansible (`ansible-core` or full `ansible`)
- The `community.docker` collection:
  ```bash
  ansible-galaxy collection install -r ansible/requirements.yaml
  ```
- An SSH keypair whose public key path matches `ssh_public_key_path` in `all.yaml`
- A vault password file at `.vault_pass` (gitignored). Copy `.vault_pass_example` and put your real vault password in it.

On the **target server**:

- A fresh Debian 12 (Bookworm) install with root SSH access.

## Deploying to a fresh VPS

These steps assume a brand-new Debian 12 VPS where you can SSH in as `root`.

### 1. Point DNS at the server

Create an **A record** for your base domain and a **wildcard** (or per-service) record pointing at the VPS IP, so Traefik can route subdomains and pass Let's Encrypt's HTTP challenge:

```
A   omrin.in       <VPS_IP>
A   *.omrin.in     <VPS_IP>
```

### 2. (Optional) Add an SSH alias

So you don't hardcode the IP anywhere. In `~/.ssh/config`:

```
Host omrin
    HostName <VPS_IP>
    User root
    IdentityFile ~/.ssh/personal
```

The Contabo inventories reference the host `omrin`, which resolves through this config.

### 3. Configure your values

- Edit `ansible/group_vars/all.yaml` — set `domain`, confirm `new_user`, and adjust `ssh_port` if desired.
- Create/edit `ansible/group_vars/secrets.yaml` from the example, with your real email and any service secrets.

### 4. Run phase 1 — bootstrap (as root)

```bash
cd ansible
ansible-playbook playbooks/bootstrap.yaml \
  -i inventory/contabo/contabo-bootstrap.yaml
```

This creates your deploy user and installs your SSH key. **Verify you can log in as the deploy user before continuing:**

```bash
ssh aditya@<VPS_IP>     # or: ssh -p <ssh_port> aditya@<VPS_IP>
```

### 5. Run phase 2 — main deploy (as the deploy user)

```bash
ansible-playbook playbooks/main.yaml \
  -i inventory/contabo/contabo-main.yaml \
  --vault-password-file=../.vault_pass
```

This installs Docker, locks down SSH and the firewall, and starts every enabled service. Once it finishes, your services are reachable at `https://<service>.<domain>` with valid TLS certificates.

> **Note:** if you changed `ssh_port`, after phase 2 you must connect on the new port. Update the `Port` in your `~/.ssh/config` accordingly.

## Adding a new service

1. Create `ansible/services/<name>/docker-compose.yaml`. Reference env vars with `${VAR:?}` so deployment fails loudly if a var is missing. Add Traefik labels to expose it:
   ```yaml
   labels:
     - "traefik.enable=true"
     - "traefik.http.routers.<name>.rule=Host(`<name>.${DOMAIN:?}`)"
   ```
2. If the service needs secrets or extra env vars, add them under `service_secrets.<name>` in the vault.
3. Add the service to the `services` list in `all.yaml` with `enabled: true`.
4. Re-run the main playbook.

To disable a service, set `enabled: false` — the next run stops and removes it.

## Local testing with Vagrant

To test the full provisioning flow in a throwaway VM before deploying to production:

```bash
vagrant up          # boots a Debian 12 VM and runs both playbooks
./scripts/test_setup.sh   # smoke-tests ssh, sudo, and firewall
vagrant destroy     # tear it down
```

The Vagrantfile runs `bootstrap` then `main` automatically, using the `inventory/vagrant/` inventories.

## Backup Strategy

Persistent service data lives under `/data/omrin/` on the server. The important data (databases, password vaults, documents, calendar data) should be backed up off-server. To back up a service, stop it, archive its data directory, and copy it off the host:

```bash
docker compose -f ~/Omrin/<service>/docker-compose.yaml down
tar czf ~/backup-<service>.tar.gz /data/omrin/<service>/
docker compose -f ~/Omrin/<service>/docker-compose.yaml up -d
# then pull ~/backup-<service>.tar.gz to a local machine or external store
```

Recommended backup destinations: a Hetzner Storage Box, OneDrive, or any off-site location.

## License

MIT — see [LICENSE](./LICENSE).
